import Foundation
import Combine
import AVFoundation
import UIKit
import FeelCore
import MultipeerConnectivity

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
            invalidateVoiceScene()
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
    enum VoicePanel: String { case settings, connection, assistant, closed }
    @Published var voicePanel: VoicePanel?
    @Published var voiceControlsExpanded: Bool?
    private var voiceTeammates: [String: MCPeerID] = [:]
    let voice: RealtimeVoiceSession
    private var proactiveVoice = ProactiveVoicePolicy()
    private var voiceNotice: ProactiveVoicePolicy.Notice?
    private var voiceSawTarget = false
    private var voiceTargetAvailable = false
    private var voiceTargetPhrase: String?
    private var voiceLastGuidance: GuidanceState?
    private var voiceHadConnection = false
    private var voiceOwnsScan = false
    private var voiceStateSubscription: AnyCancellable?
    private var voiceTargetLostAt: TimeInterval?
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
    init(voice: RealtimeVoiceSession = RealtimeVoiceSession()) {
        self.voice = voice
        voice.onCommand = { [weak self] command in self?.performVoiceCommand(command) ?? ["error": "App unavailable"] }
        voice.onEnded = { [weak self] in
            guard let self else { return }
            if self.voiceOwnsScan { self.puck.stopScanning(); self.voiceOwnsScan = false }
        }
        voiceStateSubscription = voice.$phase.sink { [weak self] phase in
            guard let self else { return }
            UIApplication.shared.isIdleTimerDisabled = self.mode != .stopped || self.isStarting || (phase != .idle && phase != .failed)
        }
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
        guard !isStarting, mode != .live else { return }
        stop(stopVoice: false); isStarting=true; status="Requesting camera access"
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
        stop(stopVoice: false); mode = .simulation; simulationScene=memory ? .memory : .obstacles; simulatedAt=ProcessInfo.processInfo.systemUptime
        status="SIMULATION: synthetic scene, no simulated BLE movement"; calibrated=false
        if memory { resetSimulatedSession() }; beginTimer()
    }
    func calibrate() { guard mode == .live else { return }; perception.calibrate(cameraHeight:cameraHeight) }
    func stop(stopVoice: Bool = false) {
        voice.invalidateSceneSpeech()
        if stopVoice { voice.disconnect() }
        isStarting=false; startGeneration += 1; timer?.invalidate(); timer=nil; frame=nil; calibrated=false
        perception.stop(); peer.stop(); mode = .stopped; guidanceState = .stopped
        spatialMemory.end(); memoryGuidance=nil; memoryNotice="Session ended. Saved places and return point cleared."
        sequence &+= 1; packet = .neutral(sequence:sequence); puck.send(packet)
        status="Stopped. Neutral command sent if connected"; targetDescription="No guidance"
        UIApplication.shared.isIdleTimerDisabled=voice.isActive
        invalidateVoiceScene(); voiceLastGuidance = nil
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
        invalidateVoiceScene()
        spatialMemory.stopGuidance(); memoryGuidance=nil; memoryNotice="Place guidance stopped. Obstacle sensing continues."; tick()
    }
    private func performMemoryAction(_ action:() throws -> String) {
        // Kept synchronous on main so selection changes cannot race a packet tick.
        invalidateVoiceScene()
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
    func performVoiceCommand(_ command: VoiceCommand) -> [String: Any] {
        voiceNotice = nil
        switch command {
        case .stop:
            stop()
            return ["status": "Camera stopped. Neutral command sent if connected. Assistant remains listening."]
        case .pauseAssistant:
            voice.pauseAssistant()
            return ["status": "Assistant paused. Microphone is off."]
        case .startCamera:
            startLive()
            return voiceSnapshot()
        case .status: return voiceSnapshot()
        case .find(let target):
            guard mode == .live else { return ["error": "Camera is not live. Ask the user whether to start it."] }
            guard target != .chair || detectorAvailable else { return ["error": detectorStatus] }
            if spatialMemory.activeID != nil { stopMemoryGuidance() }
            finder = target; voiceSawTarget = false
            if target == .teammate { voicePanel = .settings }
            return ["status": "Target selection changed. This does not mean the target was found.",
                    "target": target.rawValue,
                    "note": target == .teammate ? "Teammate sharing still requires explicit consent in Settings." : "Call get_status for current results."]
        case .calibrate(let height):
            guard mode == .live, height.isFinite, (0.6...2.1).contains(height) else { return ["error": "Start the live camera and provide a measured height between 0.6 and 2.1 meters."] }
            cameraHeight = height; calibrate()
            return ["status": "Calibration requested using the supplied measured height. Call get_status to check the result."]
        case .scanPucks:
            puck.scan(); voiceOwnsScan = true
            return ["status": "Discovery requested. Wait briefly, then call list_pucks. Ask which device to connect."]
        case .listPucks:
            return ["status": puck.status, "devices": puck.devices.map { ["device_id": $0.identifier.uuidString, "name": $0.name ?? "FEEL puck"] }]
        case .connectPuck(let id):
            guard let device = puck.devices.first(where: { $0.identifier == id }) else { return ["error": "That device is not in the current discovery results. Scan again."] }
            puck.connect(device); voiceOwnsScan = false
            return ["status": "Connection requested. Call get_status to confirm; it is not connected yet."]
        case .setSpokenOutput(let enabled):
            voice.setSpokenOutput(enabled)
            return ["status": enabled ? "Spoken replies enabled." : "Spoken replies muted. Microphone remains on; say speak again to unmute."]
        case .setProactiveUpdates(let enabled):
            voice.proactiveEnabled = enabled
            return ["status": enabled ? "Useful updates enabled." : "Useful updates paused. Replies to your questions remain available."]
        case .startSimulation:
            startSimulation()
            return ["status": "Simulation started. Synthetic scene only; no simulated movement sent to hardware.", "simulation": true]
        case .disconnectPuck:
            puck.disconnect(); voiceHadConnection = false
            return ["status": "Puck disconnect requested. Tactile feedback is unavailable."]
        case .setCameraHeight(let height):
            guard height.isFinite, (0.6...2.1).contains(height) else { return ["error": "Measured camera height must be between 0.6 and 2.1 meters."] }
            cameraHeight = height
            return ["status": "Measured height saved. Floor calibration has not been performed."]
        case .openPanel(let panel):
            guard let selected = VoicePanel(rawValue: panel), selected != .closed else { return ["error": "Unknown panel."] }
            voicePanel = selected
            return ["status": "Panel opening requested."]
        case .closePanel:
            voicePanel = .closed
            return ["status": "Panel closing requested."]
        case .setControlsExpanded(let expanded):
            voicePanel = .closed; voiceControlsExpanded = expanded
            return ["status": expanded ? "Camera controls opening requested." : "Camera controls closing requested."]
        case .scanTeammates:
            guard mode == .live else { return ["error": "Start the live camera before finding a teammate."] }
            voiceTeammates = [:]; peer.start()
            return ["status": peer.status, "note": "Ask which Beacon phone to invite after listing results. The teammate must accept."]
        case .listTeammates:
            voiceTeammates = voiceTeammates.filter { peer.peers.contains($0.value) }
            for person in peer.peers where !voiceTeammates.values.contains(person) {
                voiceTeammates[UUID().uuidString] = person
            }
            return ["status": peer.status, "devices": voiceTeammates.keys.sorted().map {
                ["device_id": $0, "name": voiceTeammates[$0]!.displayName]
            }]
        case .findTeammate(let id):
            guard mode == .live, peer.running, let selected = voiceTeammates[id], peer.peers.contains(selected) else {
                return ["error": "That Beacon phone is unavailable. Scan and list phones again."]
            }
            finder = .teammate; peer.invite(selected)
            return ["status": peer.status, "note": "Invitation is pending until the teammate accepts. This does not confirm ranging."]
        case .stopFindingTeammate:
            peer.stop(); voiceTeammates = [:]
            if finder == .teammate { finder = .none }
            return ["status": "Teammate finding stopped."]
        case .openSystemSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return ["error": "iPhone Settings is unavailable."] }
            UIApplication.shared.open(url)
            return ["status": "Opening iPhone Settings. Permissions still require your approval there."]
        case .forgetVoiceConnection:
            voice.forgetConfiguration()
            return ["status": "Voice connection removed. Setup is required to listen again."]
        case .openSettings:
            voicePanel = .settings
            return ["status": "Settings opened."]
        }
    }

    func voiceSnapshot() -> [String: Any] {
        // Recompute age/tracking before sharing any scene-derived description.
        tick()
        let valid = mode == .live && guidanceState == .live
        return ["mode": mode.rawValue, "camera_starting": isStarting,
                "guidance": String(describing: guidanceState), "calibrated": calibrated,
                "status": status, "target": valid && spatialMemory.activeID == nil ? targetDescription : "No current live target observation",
                "scene_observation": valid && voiceTargetAvailable,
                "spoken_observation": valid && voiceTargetAvailable ? voiceTargetPhrase ?? "No current target" : "No current target",
                "selected_target": finder.rawValue, "puck_connected": puck.isConnected,
                "connection": puck.status, "simulation": mode == .simulation,
                "spoken_replies": voice.spokenOutputEnabled, "useful_updates": voice.proactiveEnabled,
                "notice": "Neutral pins do not mean a clear path. No safe-route claim is available."]
    }

    private func invalidateVoiceScene() {
        voice.invalidateSceneSpeech(); proactiveVoice.reset(); voiceNotice = nil
        voiceSawTarget = false; voiceTargetLostAt = nil
        voiceTargetAvailable = false; voiceTargetPhrase = nil
    }

    private func updateVoiceAwareness(targetAvailable: Bool, target: TargetObservation? = nil,
                                      distances: [Double?] = [], now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        voiceTargetAvailable = targetAvailable
        guard voice.isActive else {
            voiceSawTarget = false; voiceLastGuidance = nil; voiceHadConnection = puck.isConnected
            proactiveVoice.reset(); voiceNotice = nil
            return
        }
        if guidanceState != .live || (voiceNotice.map {
            !$0.isSupported(target: target, finder: finder, distances: distances, now: now)
        } ?? !targetAvailable) {
            voice.invalidateSceneSpeech(); voiceNotice = nil
        }
        if voiceHadConnection && !puck.isConnected {
            if voice.announce("The puck disconnected. Tactile feedback is unavailable.") { voiceHadConnection = false }
            return
        }
        voiceHadConnection = puck.isConnected
        guard mode == .live else {
            voiceSawTarget = false; voiceLastGuidance = nil; proactiveVoice.reset(); voiceNotice = nil
            return
        }
        if guidanceState != .live {
            voiceSawTarget = false; voiceTargetLostAt = nil; proactiveVoice.reset()
            if voiceLastGuidance != guidanceState {
                let message: String
                switch guidanceState {
                case .uncalibrated: message = "What's the measured camera height? I need it to calibrate."
                case .trackingLost: message = "Tracking lost. Sensing is unavailable."
                default: message = "Sensing is unavailable. Pins are neutral."
                }
                if voice.announce(message) { voiceLastGuidance = guidanceState }
            }
            return
        }
        // A successful recovery is worth hearing without asking for status again.
        if let previous = voiceLastGuidance, previous != .live {
            if voice.announce("Sensing is back.") { voiceLastGuidance = .live }
            return
        }
        voiceLastGuidance = .live
        let notice = proactiveVoice.propose(target: target, finder: finder, distances: distances, now: now)
        if let notice, notice.kind == .obstacle,
           voice.announce(notice.text, sceneBound: true) {
            proactiveVoice.acknowledge(notice, now: now); voiceNotice = notice
            return
        }
        if !targetAvailable {
            if voiceSawTarget {
                if voiceTargetLostAt == nil { voiceTargetLostAt = now }
                if now - (voiceTargetLostAt ?? now) >= 0.6,
                   voice.announce("I no longer see your target.") { voiceSawTarget = false }
            }
        } else { voiceTargetLostAt = nil }
        if let notice, voice.announce(notice.text, sceneBound: true) {
            proactiveVoice.acknowledge(notice, now: now)
            voiceNotice = notice
            if notice.kind == .target { voiceSawTarget = true }
        }
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
            memoryGuidance=nil; voiceTargetPhrase=nil
            if mode == .live { targetDescription="Waiting for fresh tracking and depth. Guidance neutral"; puck.send(packet) }
            updateVoiceAwareness(targetAvailable: false, now: now); return
        }
        if spatialMemory.activeID != nil {
            guard let sample=currentMemoryPose(now:now) else {
                packet = .neutral(sequence:sequence); guidanceState = .staleDepth; memoryGuidance=nil
                targetDescription="Current pose unavailable. Guidance neutral"; voiceTargetPhrase=nil
                puck.send(packet); updateVoiceAwareness(targetAvailable: false, now: now); return
            }
            let result=spatialMemory.encode(sequence:sequence,sample:sample,now:now,distances:frame.distances,floorCalibrated:frame.floorY != nil)
            packet=result.output.packet; guidanceState=result.output.state; memoryGuidance=result.guidance
            targetDescription=result.output.state == .live ? memoryDescription(result.guidance) : "Guidance neutral: \(result.output.state.rawValue)"
            // A saved phone position is not a current visual target observation.
            voiceTargetPhrase=nil
            puck.send(packet)
            updateVoiceAwareness(targetAvailable: false, distances: frame.distances, now: now)
            return
        }
        memoryGuidance=nil
        let target:TargetObservation? = finder == .none ? nil : (finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target)
        let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        packet=output.packet; guidanceState=output.state; puck.send(packet)
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@, %.1f m, %.0f°",target.label,target.distance,target.bearingDegrees)
            voiceTargetPhrase = VoicePhrasing.observation(target, finder: finder, now: now)
        } else {
            voiceTargetPhrase = nil
            targetDescription=finder == .none ? "Obstacle sensing" : "Target unavailable. No directional highlight"
        }
        updateVoiceAwareness(targetAvailable: target?.valid(at: now) == true && output.state == .live,
                             target: target, distances: frame.distances, now: now)
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
