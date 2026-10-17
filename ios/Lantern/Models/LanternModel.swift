import Foundation
import Combine
import AVFoundation
import UIKit
import FeelCore
import ARKit

/// UI and 10Hz transmission coordinator. All state is confined to the main queue.
final class LanternModel:ObservableObject {
    enum RunMode:String { case stopped="STOPPED",live="LIVE",simulation="SIMULATION" }
    enum SimulationScene:Equatable { case obstacles, memory }
    @Published private(set) var isStarting=false
    @Published private(set) var mode:RunMode = .stopped
    @Published private(set) var simulationScene:SimulationScene = .obstacles
    @Published private(set) var packet=FeelPacket.neutral(sequence:0)
    @Published private(set) var guidanceState:GuidanceState = .stopped
    @Published private(set) var status="Open the camera to begin"
    @Published private(set) var detectorStatus="Loading detector"
    @Published private(set) var detectorAvailable=false
    @Published private(set) var targetDescription="No target selected"
    @Published private(set) var calibrated=false
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none {
        didSet {
            guard oldValue != finder else { return }
            adaptive.reset()
            spatialMemory.stopGuidance(); memoryGuidance=nil
            finderEpoch += 1; perception.setFinder(finder,epoch:finderEpoch); frame=nil
            targetDescription="Searching: \(finder.rawValue)"; tick()
        }
    }
    @Published private(set) var spatialMemory=SpatialMemoryManager()
    @Published private(set) var memoryGuidance:MemoryGuidance?
    @Published private(set) var memoryNotice="Places last only until this sensing session ends."
    @Published var placeName=""
    @Published private(set) var simulatedPosition=Vector3.zero
    @Published private(set) var simulatedYaw=0.0
    @Published var simulatedTracking=true { didSet { if mode == .simulation,simulationScene == .memory { tick() } } }
    @Published var adaptiveProfile:AdaptiveProfile = .standard { didSet { adaptive.reset(); tick() } }
    @Published var commandText=""
    @Published var commandLanguage:VoiceLanguage = .en { didSet { voice.cancel() } }
    @Published private(set) var commandNotice="Type a command or explicitly start on-device speech."
    @Published private(set) var mapNotice="One local map can be saved explicitly. No map loads automatically."
    @Published private(set) var restoreState:WorldMapRestoreState = .idle
    @Published private(set) var restoredMapSession=false
    @Published private(set) var mapBusy=false
    let voice=VoiceControl()
    let perception=ARPerception()
    let puck=BluetoothPuck()
    let peer=NearbyPeerService(role:.seeker)
    private var frame:PerceptionFrame?
    private var timer:Timer?
    private var sequence:UInt8=0
    private var simulatedAt:TimeInterval=0
    private var startGeneration=0
    private var finderEpoch=0
    private var adaptive=AdaptiveTactileController()
    private var restoreGate=WorldMapRestoreGate()
    private let mapStore=WorldMapStore()
    private let mapQueue=DispatchQueue(label:"feel.saved-map",qos:.userInitiated)
    private var mapOperation=0
    var restoringMap:Bool { restoreState == .awaitingRelocalization || restoreState == .failed }
    var speechLocale:String { commandLanguage == .en ? "en-US" : "es-ES" }
    var memoryControlsVisible:Bool { mode == .live || (mode == .simulation && simulationScene == .memory) }
    var selectedPlace:SpatialBookmark? { spatialMemory.bookmarks.first { $0.id==spatialMemory.selectedID } }
    init() {
        voice.onFinalTranscript={ [weak self] text in self?.executeCommand(text) }
        peer.arSession=perception.session
        perception.onWorldSession={ [weak self] epoch,id in
            guard let self,self.mode == .live,epoch==self.startGeneration else { return }
            self.mapOperation += 1; self.mapBusy=false
            self.frame=nil; self.calibrated=false; self.memoryGuidance=nil
            // NI world coordinates belong to this same AR world and must be discarded too.
            self.peer.stop()
            self.voice.cancel(); self.adaptive.reset()
            if let id {
                if self.restoreGate.session != id { self.restoreGate.cancel(); self.restoreState = .idle; self.restoredMapSession=false }
                do { try self.spatialMemory.begin(session:id); self.memoryNotice=self.restoringMap ? "Waiting for saved-map relocalization. Places are inactive." : "New session. Remember places or set a return point." }
                catch { self.spatialMemory.end(); self.memoryNotice=String(describing:error) }
            } else {
                self.restoreGate.cancel(); self.restoreState = .idle; self.restoredMapSession=false
                self.spatialMemory.end(); self.memoryNotice="Session interrupted. Saved places and return point cleared."
            }
            self.tick()
        }
        perception.onFrame={ [weak self] frame in
            guard let self,self.mode == .live,frame.epoch==self.startGeneration,frame.finderEpoch==self.finderEpoch,
                  frame.worldSession==self.spatialMemory.session else { return }
            self.frame=frame; self.calibrated=frame.floorY != nil
            self.observeRestoration(frame)
        }
        perception.onInvalidated={ [weak self] epoch in guard let self,epoch==self.startGeneration else { return }; self.frame=nil; self.calibrated=false; self.tick() }
        perception.onStatus={ [weak self] text in guard let self,self.mode == .live else { return }; self.status=text }
        perception.onModelStatus={ [weak self] text,available in self?.detectorStatus=text; self?.detectorAvailable=available }
    }
    func startLive() {
        guard !isStarting, mode != .live else { return }
        stop(); isStarting=true; status="Requesting camera access"
        startGeneration += 1; let generation=startGeneration
        func begin() {
            guard self.startGeneration==generation else { return }
            self.isStarting=false
            self.mode = .live
            guard self.perception.start(epoch:generation) else { self.mode = .stopped; self.status="Live sensing requires a LiDAR device. Simulation is available."; return }
            self.perception.setFinder(self.finder,epoch:self.finderEpoch); self.status="Starting live perception"; self.beginTimer()
        }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { granted in DispatchQueue.main.async {
                guard self.startGeneration==generation else { return }
                if granted { begin() } else { self.isStarting=false; self.status="Camera permission denied. Enable it in Settings to use Live." }
            } }
        default: isStarting=false; status="Camera permission denied. Enable it in Settings to use Live."
        }
    }
    func startSimulation(memory:Bool=false) {
        stop(); mode = .simulation; simulationScene=memory ? .memory : .obstacles; simulatedAt=ProcessInfo.processInfo.systemUptime
        status="SIMULATION: synthetic scene, no simulated BLE movement"; calibrated=false
        if memory { resetSimulatedSession() }; beginTimer()
    }
    func calibrate() { guard mode == .live else { return }; perception.calibrate(cameraHeight:cameraHeight) }
    func stop() {
        isStarting=false; startGeneration += 1; timer?.invalidate(); timer=nil; frame=nil; calibrated=false
        mapOperation += 1; mapBusy=false; restoreGate.cancel(); restoreState = .idle; restoredMapSession=false
        voice.cancel(); adaptive.reset()
        perception.stop(); peer.stop(); mode = .stopped; guidanceState = .stopped
        spatialMemory.end(); memoryGuidance=nil; memoryNotice="Session ended. Saved places and return point cleared."
        sequence &+= 1; packet = .neutral(sequence:sequence); puck.send(packet)
        status="Stopped. Neutral command sent if connected"; targetDescription="No guidance"
        UIApplication.shared.isIdleTimerDisabled=false
    }
    func remember() {
        performMemoryAction {
            let now=ProcessInfo.processInfo.systemUptime
            guard let sample=currentMemoryPose(now:now) else { throw SpatialMemoryError.invalidContext(.stalePose) }
            let saved=try spatialMemory.remember(name:placeName,sample:sample,now:now)
            finder = .none; placeName=saved.name; return "Remembered \(saved.name)."
        }
    }
    func selectPlace(_ id:String) {
        performMemoryAction { try spatialMemory.select(id:id); placeName=selectedPlace?.name ?? ""; return "Selected \(placeName). Choose Recall to start guidance." }
    }
    func renameSelectedPlace() {
        performMemoryAction {
            guard let id=spatialMemory.selectedID else { throw SpatialMemoryError.noSelection }
            try spatialMemory.rename(id:id,name:placeName); return "Renamed to \(selectedPlace?.name ?? placeName)."
        }
    }
    func deleteSelectedPlace() {
        performMemoryAction {
            guard let id=spatialMemory.selectedID else { throw SpatialMemoryError.noSelection }
            try spatialMemory.delete(id:id); placeName=""; return "Place deleted."
        }
    }
    func recall() {
        performMemoryAction { finder = .none; try spatialMemory.recall(); return "Recall selected. Fresh tracking is required for guidance." }
    }
    func setReturnPoint() {
        performMemoryAction {
            let now=ProcessInfo.processInfo.systemUptime
            guard let sample=currentMemoryPose(now:now) else { throw SpatialMemoryError.invalidContext(.stalePose) }
            try spatialMemory.setReturnPoint(sample:sample,now:now); return "Return point set at the current phone position."
        }
    }
    func returnToPoint() {
        performMemoryAction { finder = .none; try spatialMemory.returnToStart(); return "Returning to your explicit return point." }
    }
    func stopMemoryGuidance() {
        spatialMemory.stopGuidance(); memoryGuidance=nil; memoryNotice="Place guidance stopped. Obstacle sensing continues."; tick()
    }
    private func performMemoryAction(_ action:() throws -> String) {
        // Kept synchronous on main so selection changes cannot race a packet tick.
        guard !restoringMap else { memoryNotice="Saved-map coordinates are inactive until relocalization succeeds. Start fresh Live to cancel."; return }
        adaptive.reset()
        do { memoryNotice=try action() } catch { memoryNotice=String(describing:error) }
        tick()
    }
    func resetSimulatedSession() {
        guard mode == .simulation,simulationScene == .memory else { return }
        adaptive.reset(); simulatedPosition = .zero; simulatedYaw=0; simulatedTracking=true
        do { try spatialMemory.begin(session:UUID().uuidString); memoryNotice="SIMULATION: New session. Name and Remember this position, then Move back twice and Recall." }
        catch { spatialMemory.end(); memoryNotice=String(describing:error) }
        memoryGuidance=nil; tick()
    }
    func simulateMove(metres:Double) {
        guard mode == .simulation,simulationScene == .memory else { return }
        let a=simulatedYaw * .pi / 180
        simulatedPosition=simulatedPosition+Vector3(-sin(a)*metres,0,-cos(a)*metres); tick()
    }
    func simulateTurn(degrees:Double) {
        guard mode == .simulation,simulationScene == .memory else { return }
        simulatedYaw=(simulatedYaw+degrees).truncatingRemainder(dividingBy:360); tick()
    }
    private func currentMemoryPose(now:Double) -> MemoryPose? {
        guard let session=spatialMemory.session else { return nil }
        if mode == .simulation,simulationScene == .memory {
            let a=simulatedYaw * .pi / 180
            return MemoryPose(session:session,pose:CameraPose(position:simulatedPosition,right:Vector3(cos(a),0,-sin(a)),up:Vector3(0,1,0),back:Vector3(sin(a),0,cos(a))),timestamp:now,tracking:simulatedTracking)
        }
        guard mode == .live,let frame,frame.worldSession==session,frame.epoch==startGeneration,frame.finderEpoch==finderEpoch else { return nil }
        return MemoryPose(session:session,pose:frame.pose,timestamp:frame.timestamp,tracking:frame.tracking)
    }
    private func beginTimer() {
        UIApplication.shared.isIdleTimerDisabled=true
        let timer=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in self?.tick() }
        self.timer=timer; RunLoop.main.add(timer,forMode:.common); tick()
    }
    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime; sequence &+= 1
        if restoreGate.state == .awaitingRelocalization,restoreGate.checkDeadline(now:now) == .failed {
            restoreState = .failed; spatialMemory.end(); mapNotice="Map restoration timed out. Start fresh Live or explicitly Load again."
        }
        if mode == .simulation {
            if simulationScene == .memory,let sample=currentMemoryPose(now:now) {
                let result=spatialMemory.encode(sequence:sequence,sample:sample,now:now,distances:[nil,nil,0.7,nil,nil,nil,nil])
                packet=adapt(result.output.packet,now:now); guidanceState=result.output.state == .live ? .simulation : result.output.state
                memoryGuidance=result.guidance; targetDescription="SIMULATION · " + memoryDescription(result.guidance)
                return
            }
            let phase=(now-simulatedAt).truncatingRemainder(dividingBy:12)
            let tracking=phase<8 || phase>=10
            let target=TargetObservation(bearingDegrees:sin(phase/2)*40,distance:1.3,timestamp:now,label:"SIMULATED target")
            let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:now,tracking:tracking,distances:[0.7,1.1,nil,2,3.5,nil,nil],target:target)
            packet=adapt(output.packet,now:now); guidanceState=output.state == .live ? .simulation : output.state
            targetDescription=tracking ? "SIMULATED target sweeping left to right" : "SIMULATED tracking loss. All pins neutral"
            return
        }
        guard mode == .live,let frame,!restoringMap else {
            packet = .neutral(sequence:sequence); guidanceState = mode == .live ? .staleDepth : .stopped
            memoryGuidance=nil
            if mode == .live { targetDescription=restoringMap ? "Saved-map guidance inactive: \(restoreState.rawValue)" : "Waiting for fresh tracking and depth — guidance neutral"; puck.send(packet) }; return
        }
        if spatialMemory.activeID != nil,let sample=currentMemoryPose(now:now) {
            let result=spatialMemory.encode(sequence:sequence,sample:sample,now:now,distances:frame.distances,floorCalibrated:frame.floorY != nil)
            packet=adapt(result.output.packet,now:now); guidanceState=result.output.state; memoryGuidance=result.guidance
            targetDescription=result.output.state == .live ? memoryDescription(result.guidance) : "Guidance neutral: \(result.output.state.rawValue)"
            puck.send(packet); return
        }
        memoryGuidance=nil
        let target=finder == .teammate ? (restoredMapSession ? nil : peer.currentTarget(pose:frame.pose,now:now)) : frame.target
        let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        packet=adapt(output.packet,now:now); guidanceState=output.state; puck.send(packet)
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@, %.1f m, %.0f°",target.label,target.distance,target.bearingDegrees)
        } else { targetDescription=finder == .none ? "Obstacle sensing" : "Target unavailable. No directional highlight" }
    }
    private func adapt(_ packet:FeelPacket,now:Double)->FeelPacket {
        adaptive.apply(packet:packet,profile:adaptiveProfile,session:spatialMemory.session ?? "run-\(startGeneration)",now:now)
    }
    func submitTypedCommand() { voice.cancel(); executeCommand(commandText) }
    func startVoiceCommand() { voice.start(localeIdentifier:speechLocale) }
    func readCommandResult() { voice.speak(commandNotice,localeIdentifier:speechLocale) }
    private func executeCommand(_ text:String) {
        do {
            let intent=try VoiceIntentParser.parse(text:text,language:commandLanguage,isFinal:true)
            switch intent {
            case .remember(let name): placeName=name; remember(); commandNotice=memoryNotice
            case .recall(let name):
                let key=name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
                guard let place=spatialMemory.bookmarks.first(where: { $0.name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))==key }) else { throw SpatialMemoryError.unknownBookmark }
                selectPlace(place.id); recall(); commandNotice=memoryNotice
            case .returnToPoint: returnToPoint(); commandNotice=memoryNotice
            case .stop: stop(); commandNotice="Stopped. Guidance is neutral."
            case .listPlaces: commandNotice=spatialMemory.bookmarks.isEmpty ? "No places in this session." : "Places: " + spatialMemory.bookmarks.map(\.name).joined(separator:", ")
            case .find(let mode):
                if mode == .teammate,restoredMapSession { commandNotice="Teammate ranging requires a fresh Live session. Saved-map sessions cannot share camera assistance."; return }
                let modes:[VoiceFindMode:FinderMode]=[.obstacles:.none,.door:.door,.exit:.exit,.chair:.chair,.person:.person,.teammate:.teammate,.barcode:.barcode]
                finder=modes[mode] ?? .none; commandNotice="Finder selected: \(finder.rawValue). " + (self.mode == .live ? "" : "Start Live for camera perception.")
            }
        } catch { commandNotice=String(describing:error) }
    }
    func saveMap() {
        guard mode == .live,!restoringMap,!mapBusy,let session=spatialMemory.session else { mapNotice="Save requires an active live session after relocalization, if any."; return }
        let now=ProcessInfo.processInfo.systemUptime
        guard let pose=currentMemoryPose(now:now),pose.tracking,now-pose.timestamp>=0,now-pose.timestamp<=0.25 else { mapNotice="Save needs fresh normal tracking."; return }
        let snapshot=spatialMemory.snapshot; mapOperation += 1; let operation=mapOperation
        mapBusy=true; mapNotice="Capturing local AR map…"
        perception.captureWorldMap(sessionID:session) { [weak self] result in
            guard let self,self.mapOperation==operation,self.spatialMemory.session==session else { return }
            do {
                let (bytes,mapID,anchorID)=try result.get()
                let archive=try PersistentMemoryArchive(mapID:mapID,anchorID:anchorID,mapData:bytes,snapshot:snapshot)
                self.mapQueue.async {
                    let saved=Result { try self.mapStore.save(archive) }
                    DispatchQueue.main.async {
                        guard self.mapOperation==operation else { return }; self.mapBusy=false
                        switch saved { case .success: self.mapNotice="Saved one local map with \(snapshot.bookmarks.count) places. Load requires relocalization in the same area."
                        case .failure(let error): self.mapNotice=String(describing:error) }
                    }
                }
            } catch { self.mapBusy=false; self.mapNotice=String(describing:error) }
        }
    }
    func loadMap() {
        guard mode == .live,!mapBusy else { mapNotice="Start Live, then explicitly Load the saved map."; return }
        mapOperation += 1; let operation=mapOperation; mapBusy=true; mapNotice="Reading saved local map…"
        mapQueue.async {
            let result=Result { try self.mapStore.load() }
            DispatchQueue.main.async {
                guard self.mapOperation==operation,self.mode == .live else { return }; self.mapBusy=false
                switch result {
                case .failure(let error): self.mapNotice=String(describing:error)
                case .success(let loaded): self.beginMapRestore(archive:loaded.archive,map:loaded.map)
                }
            }
        }
    }
    private func beginMapRestore(archive:PersistentMemoryArchive,map:ARWorldMap) {
        stop(); startGeneration += 1
        let session=UUID().uuidString
        do { try restoreGate.begin(archive:archive,session:session,now:ProcessInfo.processInfo.systemUptime) }
        catch { mapNotice=String(describing:error); return }
        restoreState=restoreGate.state; restoredMapSession=true; mode = .live
        if finder == .teammate { finder = .none }
        guard perception.start(epoch:startGeneration,restoredMap:map,mapID:archive.mapID,sessionID:session) else { stop(); mapNotice="This device cannot restore a LiDAR session."; return }
        perception.setFinder(finder,epoch:finderEpoch)
        mapNotice="Move slowly in the saved area. Waiting for relocalization, matching marker and 0.5 s fresh normal tracking. Places remain inactive."
        beginTimer()
    }
    private func observeRestoration(_ frame:PerceptionFrame) {
        guard restoreGate.state == .awaitingRelocalization,let mapID=frame.mapID else { return }
        restoreState=restoreGate.observe(session:frame.worldSession,mapID:mapID,anchorID:frame.mapAnchorID,now:ProcessInfo.processInfo.systemUptime,sample:MemoryPose(session:frame.worldSession,pose:frame.pose,timestamp:frame.timestamp,tracking:frame.tracking),relocalizing:frame.relocalizing)
        if restoreState == .ready,let archive=restoreGate.archive {
            do {
                try spatialMemory.restore(archive:archive,session:frame.worldSession)
                memoryNotice="Restored \(archive.bookmarks.count) places. Select a place and explicitly Recall."
                mapNotice="Map relocalized. Recalibrate floor before tactile guidance. Teammate ranging requires a fresh Live session."
            } catch { restoreState = .failed; spatialMemory.end(); mapNotice=String(describing:error) }
        } else if restoreState == .failed {
            spatialMemory.end(); mapNotice="Map restoration failed or timed out. Start a fresh Live session, or explicitly Load again."
        }
    }
    func deleteSavedMap() {
        mapOperation += 1; let operation=mapOperation; mapBusy=true
        mapQueue.async {
            let result=Result { try self.mapStore.delete() }
            DispatchQueue.main.async {
                guard self.mapOperation==operation else { return }; self.mapBusy=false
                switch result { case .success: self.mapNotice="Local saved map deleted. Current session places remain until Stop."
                case .failure(let error): self.mapNotice=String(describing:error) }
            }
        }
    }
    private func memoryDescription(_ guidance:MemoryGuidance) -> String {
        let name=guidance.targetName ?? "Place"
        let range=guidance.distance.map { String(format:"%.1f m tactile range",$0) } ?? ""
        let ground=guidance.horizontalDistance.map { String(format:"%.1f m horizontal",$0) } ?? ""
        switch guidance.state {
        case .idle: return "Remember a place, then move and Recall. Obstacle sensing continues."
        case .guiding: return "\(name) · \(range) · \(ground) · bearing \(Int((guidance.bearingDegrees ?? 0).rounded()))°"
        case .arrived: return "Arrived near \(name) (within 0.35 m horizontally). No target highlight."
        case .outsideFieldOfView: return "\(name) is outside the ±45° tactile field · \(ground). Turn to face the place; no target highlight."
        case .behind: return "\(name) is behind or beside the phone · \(ground). No target highlight."
        case .beyondRange: return "\(name) · \(range) · \(ground). Beyond the 4 m tactile range; no target highlight."
        case .differentLevel: return "\(name) is at a different saved height. No target highlight."
        case .trackingLost: return "Tracking uncertain — all pins neutral. Saved places retained in this session."
        case .stalePose,.invalidPose: return "Current pose unavailable — all pins neutral."
        case .sessionMismatch,.sessionUnavailable: return "Session unavailable. Remember places again after tracking restarts."
        }
    }
}
