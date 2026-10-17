import Foundation
import Combine
import AVFoundation
import UIKit
import FeelCore

/// UI and 10Hz transmission coordinator. All state is confined to the main queue.
final class LanternModel:ObservableObject {
    enum RunMode:String { case stopped="STOPPED",live="LIVE",simulation="SIMULATION" }
    enum SimulationScene:Equatable { case obstacles, memory }
    @Published private(set) var mode:RunMode = .stopped
    @Published private(set) var simulationScene:SimulationScene = .obstacles
    @Published private(set) var packet=FeelPacket.neutral(sequence:0)
    @Published private(set) var guidanceState:GuidanceState = .stopped
    @Published private(set) var status="Choose Live sensing or Simulation"
    @Published private(set) var detectorStatus="Loading detector"
    @Published private(set) var detectorAvailable=false
    @Published private(set) var targetDescription="No target selected"
    @Published private(set) var calibrated=false
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none {
        didSet {
            guard oldValue != finder else { return }
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
    let perception=ARPerception()
    let puck=BluetoothPuck()
    let peer=NearbyPeerService(role:.seeker)
    private var frame:PerceptionFrame?
    private var timer:Timer?
    private var sequence:UInt8=0
    private var simulatedAt:TimeInterval=0
    private var startGeneration=0
    private var finderEpoch=0
    var memoryControlsVisible:Bool { mode == .live || (mode == .simulation && simulationScene == .memory) }
    var selectedPlace:SpatialBookmark? { spatialMemory.bookmarks.first { $0.id==spatialMemory.selectedID } }
    init() {
        peer.arSession=perception.session
        perception.onWorldSession={ [weak self] epoch,id in
            guard let self,self.mode == .live,epoch==self.startGeneration else { return }
            self.frame=nil; self.calibrated=false; self.memoryGuidance=nil
            // NI world coordinates belong to this same AR world and must be discarded too.
            self.peer.stop()
            if let id {
                do { try self.spatialMemory.begin(session:id); self.memoryNotice="New session. Remember places or set a return point." }
                catch { self.spatialMemory.end(); self.memoryNotice=String(describing:error) }
            } else {
                self.spatialMemory.end(); self.memoryNotice="Session interrupted. Saved places and return point cleared."
            }
            self.tick()
        }
        perception.onFrame={ [weak self] frame in
            guard let self,self.mode == .live,frame.epoch==self.startGeneration,frame.finderEpoch==self.finderEpoch,
                  frame.worldSession==self.spatialMemory.session else { return }
            self.frame=frame; self.calibrated=frame.floorY != nil
        }
        perception.onInvalidated={ [weak self] epoch in guard let self,epoch==self.startGeneration else { return }; self.frame=nil; self.calibrated=false; self.tick() }
        perception.onStatus={ [weak self] text in guard let self,self.mode == .live else { return }; self.status=text }
        perception.onModelStatus={ [weak self] text,available in self?.detectorStatus=text; self?.detectorAvailable=available }
    }
    func startLive() {
        stop(); startGeneration += 1; let generation=startGeneration
        func begin() {
            guard self.startGeneration==generation else { return }
            self.mode = .live
            guard self.perception.start(epoch:generation) else { self.mode = .stopped; self.status="Live sensing requires a LiDAR device. Simulation is available."; return }
            self.perception.setFinder(self.finder,epoch:self.finderEpoch); self.status="Starting live perception"; self.beginTimer()
        }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { granted in DispatchQueue.main.async {
                guard self.startGeneration==generation else { return }
                if granted { begin() } else { self.status="Camera permission denied. Enable it in Settings to use Live." }
            } }
        default: status="Camera permission denied. Enable it in Settings to use Live."
        }
    }
    func startSimulation(memory:Bool=false) {
        stop(); mode = .simulation; simulationScene=memory ? .memory : .obstacles; simulatedAt=ProcessInfo.processInfo.systemUptime
        status="SIMULATION: synthetic scene, no simulated BLE movement"; calibrated=false
        if memory { resetSimulatedSession() }; beginTimer()
    }
    func calibrate() { guard mode == .live else { return }; perception.calibrate(cameraHeight:cameraHeight) }
    func stop() {
        startGeneration += 1; timer?.invalidate(); timer=nil; frame=nil; calibrated=false
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
        do { memoryNotice=try action() } catch { memoryNotice=String(describing:error) }
        tick()
    }
    func resetSimulatedSession() {
        guard mode == .simulation,simulationScene == .memory else { return }
        simulatedPosition = .zero; simulatedYaw=0; simulatedTracking=true
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
        if mode == .simulation {
            if simulationScene == .memory,let sample=currentMemoryPose(now:now) {
                let result=spatialMemory.encode(sequence:sequence,sample:sample,now:now,distances:[nil,nil,0.7,nil,nil,nil,nil])
                packet=result.output.packet; guidanceState=result.output.state == .live ? .simulation : result.output.state
                memoryGuidance=result.guidance; targetDescription="SIMULATION · " + memoryDescription(result.guidance)
                return
            }
            let phase=(now-simulatedAt).truncatingRemainder(dividingBy:12)
            let tracking=phase<8 || phase>=10
            let target=TargetObservation(bearingDegrees:sin(phase/2)*40,distance:1.3,timestamp:now,label:"SIMULATED target")
            let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:now,tracking:tracking,distances:[0.7,1.1,nil,2,3.5,nil,nil],target:target)
            packet=output.packet; guidanceState=output.state == .live ? .simulation : output.state
            targetDescription=tracking ? "SIMULATED target sweeping left to right" : "SIMULATED tracking loss. All pins neutral"
            return
        }
        guard mode == .live,let frame else {
            packet = .neutral(sequence:sequence); guidanceState = mode == .live ? .staleDepth : .stopped
            memoryGuidance=nil
            if mode == .live { targetDescription="Waiting for fresh tracking and depth — guidance neutral"; puck.send(packet) }; return
        }
        if spatialMemory.activeID != nil,let sample=currentMemoryPose(now:now) {
            let result=spatialMemory.encode(sequence:sequence,sample:sample,now:now,distances:frame.distances,floorCalibrated:frame.floorY != nil)
            packet=result.output.packet; guidanceState=result.output.state; memoryGuidance=result.guidance
            targetDescription=result.output.state == .live ? memoryDescription(result.guidance) : "Guidance neutral: \(result.output.state.rawValue)"
            puck.send(packet); return
        }
        memoryGuidance=nil
        let target=finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target
        let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        packet=output.packet; guidanceState=output.state; puck.send(packet)
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@, %.1f m, %.0f°",target.label,target.distance,target.bearingDegrees)
        } else { targetDescription=finder == .none ? "Obstacle sensing" : "Target unavailable. No directional highlight" }
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
