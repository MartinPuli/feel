import Foundation
import Combine
import AVFoundation
import UIKit
import FeelCore
import MultipeerConnectivity

/// UI and 10Hz transmission coordinator. All state is confined to the main queue.
final class LanternModel:ObservableObject {
    enum RunMode:String { case stopped="STOPPED",live="LIVE",simulation="SIMULATION" }
    @Published private(set) var isStarting=false
    @Published private(set) var mode:RunMode = .stopped
    @Published private(set) var packet=FeelPacket.neutral(sequence:0)
    @Published private(set) var guidanceState:GuidanceState = .stopped
    @Published private(set) var status="Open the camera to begin"
    @Published private(set) var detectorStatus="Loading detector"
    @Published private(set) var detectorAvailable=false
    @Published private(set) var targetDescription="No target selected"
    @Published private(set) var calibrated=false
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none { didSet { voice.invalidateSceneSpeech(); proactiveVoice.reset(); voiceNotice = nil; voiceSawTarget = false; heldTarget = nil; finderEpoch += 1; perception.setFinder(finder,epoch:finderEpoch); frame=nil; targetDescription="Searching: \(finder.rawValue)" } }
    enum VoicePanel: String { case settings, connection, assistant, closed }
    @Published var voicePanel: VoicePanel?
    @Published var voiceControlsExpanded: Bool?
    private var voiceTeammates: [String: MCPeerID] = [:]
    let voice: RealtimeVoiceSession
    @Published private(set) var chalkConfiguration: ChalkConfiguration?
    @Published private(set) var heldTarget: HeldTarget?
    @Published private(set) var whereIsNotice: String?
    @Published private(set) var whereIsSelfTest = "Not run yet."
    @Published private(set) var whereIsSelfTestRunning = false
    private let chalkStore: ChalkConfigurationStoring
    private let gatewayFactory: (ChalkConfiguration) -> ChatGateway
    private var whereIsService: WhereIsService?
    private var selfTestService: WhereIsService?
    private var lastDirectionSpokenAt: TimeInterval = -.infinity
    /// Each ask gets a number; a photo or answer from an earlier ask is dropped.
    private var whereIsRequest = 0
    /// A result line the assistant could not speak at once (it was mid-reply); retried from the tick for ten seconds.
    private var unspokenLine: (line: String, sceneBound: Bool, expires: TimeInterval)?
    private lazy var localFinder: LocalWhereIsFinding = LocalWhereIs(detect: perception.detectLocal)
    /// Where a Where-is photo comes from; tests hand snapshots in by hand.
    lazy var snapshotProvider: (@escaping (FrameSnapshot?) -> Void) -> Void = { [perception] completion in perception.snapshot(completion: completion) }
    var whereIsAvailable: Bool { mode == .live && guidanceState == .live }
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
    init(voice: RealtimeVoiceSession = RealtimeVoiceSession(), chalkStore: ChalkConfigurationStoring = ChalkConfigurationStore(),
         gatewayFactory: @escaping (ChalkConfiguration) -> ChatGateway = { ChalkGateway(configuration: $0) },
         localFinder: LocalWhereIsFinding? = nil) {
        self.voice = voice; self.chalkStore = chalkStore; self.gatewayFactory = gatewayFactory
        if let localFinder { self.localFinder = localFinder }
        chalkConfiguration = chalkStore.loadForLaunch()
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
        perception.onFrame={ [weak self] frame in guard let self,self.mode == .live,frame.epoch==self.startGeneration,frame.finderEpoch==self.finderEpoch else { return }; self.frame=frame; self.calibrated=frame.floorY != nil }
        perception.onInvalidated={ [weak self] epoch in guard let self,epoch==self.startGeneration else { return }; self.frame=nil; self.calibrated=false; self.clearHeldTarget(spokenLine: "Lost tracking. Say it again."); self.tick() }
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
    func startSimulation() {
        stop(stopVoice: false); mode = .simulation; simulatedAt=ProcessInfo.processInfo.systemUptime
        status="SIMULATION: synthetic scene, no simulated BLE movement"; calibrated=false; beginTimer()
    }
    func calibrate() { guard mode == .live else { return }; perception.calibrate(cameraHeight:cameraHeight) }
    func stop(stopVoice: Bool = false) {
        voice.invalidateSceneSpeech()
        if stopVoice { voice.disconnect() }
        isStarting=false; startGeneration += 1; timer?.invalidate(); timer=nil; frame=nil; calibrated=false
        heldTarget = nil; whereIsService?.cancel(); whereIsNotice = nil; unspokenLine = nil
        perception.stop(); peer.stop(); mode = .stopped; guidanceState = .stopped
        sequence &+= 1; packet = .neutral(sequence:sequence); puck.send(packet)
        status="Stopped. Neutral command sent if connected"; targetDescription="No guidance"
        UIApplication.shared.isIdleTimerDisabled=voice.isActive
        voiceSawTarget = false; voiceTargetLostAt = nil; voiceLastGuidance = nil
        proactiveVoice.reset(); voiceNotice = nil
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
        case .whereIs(let thing):
            if let refusal = Self.whereIsRefusal(mode: mode, guidance: guidanceState) { return ["error": refusal] }
            beginWhereIs(thing)
            return ["status": "Looking for the \(thing) with one camera photo. The result arrives as an observation in a few seconds; call get_status to check.",
                    "pending": true]
        case .find(let target):
            heldTarget = nil
            guard mode == .live else { return ["error": "Camera is not live. Ask the user whether to start it."] }
            guard target != .chair || detectorAvailable else { return ["error": detectorStatus] }
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

    // MARK: Where-is

    func saveChalkConfiguration(_ configuration: ChalkConfiguration) throws {
        guard configuration.isValid else { throw KeychainStoreError.invalid }
        try chalkStore.save(configuration)
        chalkConfiguration = configuration; whereIsService?.cancel(); whereIsService = nil   // a lookup in flight must not answer through the old settings
    }
    func forgetChalkConfiguration() {
        chalkStore.clear(); chalkConfiguration = nil; whereIsService?.cancel(); whereIsService = nil
    }
    /// Sends the bundled sample photo through the real request path (gateway, parser, placement)
    /// with a synthetic depth grid. It never touches the live camera or the held target.
    func runWhereIsSelfTest() {
        guard let configuration = chalkConfiguration, !whereIsSelfTestRunning else { return }
        guard let url = Bundle.main.url(forResource: "WhereIsSample", withExtension: "jpg"), let data = try? Data(contentsOf: url) else {
            whereIsSelfTest = "The sample photo is missing from the app."; return
        }
        whereIsSelfTestRunning = true; whereIsSelfTest = "Asking \(configuration.model) about the sample photo…"
        let grid = DepthGrid(width: 20, height: 10, depths: Array(repeating: 2, count: 200), confidence: Array(repeating: 2, count: 200))
        let snapshot = FrameSnapshot(timestamp: 0, worldEpoch: -1, pose: .identity, intrinsics: CameraIntrinsics(fx: 10, fy: 10, cx: 10, cy: 5), depth: grid, jpegBase64: data.base64EncodedString())
        let service = WhereIsService(gateway: gatewayFactory(configuration), model: configuration.model, local: nil)   // Chalk only: the test is about the setup
        selfTestService = service
        let started = Date()
        service.find("3D puck model", snapshot: snapshot) { [weak self] outcome in
            guard let self else { return }
            self.whereIsSelfTestRunning = false; self.selfTestService = nil
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            switch outcome {
            case .placed(let target): self.whereIsSelfTest = "Found “\(target.label)” in the sample photo and placed it, in \(seconds) s. The live camera path is tested separately."
            case .notVisible: self.whereIsSelfTest = "The model answered “not visible” for the sample photo, in \(seconds) s."
            case .noDepth: self.whereIsSelfTest = "Found it but could not place it, in \(seconds) s."
            case .unsupported: self.whereIsSelfTest = "The on-device detector doesn't know that object."
            case .failed: self.whereIsSelfTest = "Failed after \(seconds) s. Check the key, environment ID, model name and network."
            }
        }
    }
    static func whereIsRefusal(mode: RunMode, guidance: GuidanceState) -> String? {
        if mode != .live { return "Camera is not live. Ask the user whether to start it." }
        if guidance != .live { return "Sensing isn't ready. Calibrate or wait for tracking, then try again." }
        return nil
    }
    /// A new ask replaces everything from the previous one: the held target, a lookup in flight, a finder target.
    func beginWhereIs(_ thing: String) {
        whereIsNotice = nil; unspokenLine = nil
        if finder != .none { finder = .none }
        clearHeldTarget(spokenLine: nil)
        whereIsService?.cancel()
        whereIsRequest += 1
        startWhereIs(thing)
    }
    private func startWhereIs(_ thing: String) {
        let service = whereIsService ?? WhereIsService(gateway: chalkConfiguration.map(gatewayFactory), model: chalkConfiguration?.model ?? "", local: localFinder)
        whereIsService = service
        let generation = startGeneration, request = whereIsRequest
        snapshotProvider { [weak self] snapshot in
            // The photo belongs to this ask only: a later ask or a stopped camera drops it.
            guard let self, self.startGeneration == generation, self.whereIsRequest == request else { return }
            guard let snapshot else { self.handleWhereIs(.failed, thing: thing); return }
            service.find(thing, snapshot: snapshot) { [weak self] outcome in
                guard let self, self.startGeneration == generation, self.whereIsRequest == request else { return }
                self.handleWhereIs(outcome, thing: thing, frame: self.frame)
            }
        }
    }
    /// Main queue. The spoken line is kept in `whereIsNotice` so get_status can relay it.
    func handleWhereIs(_ outcome: WhereIsOutcome, thing: String, frame: PerceptionFrame? = nil) {
        switch outcome {
        case .placed(let target):
            // The photo's world must still be the current one; after a tracking reset the point means nothing.
            if let frame, frame.worldEpoch != target.worldEpoch { say("Lost tracking. Say it again."); return }
            heldTarget = target; voiceSawTarget = false; lastDirectionSpokenAt = -.infinity
            let now = ProcessInfo.processInfo.systemUptime
            if let pose = frame?.pose, let observation = target.observation(pose: pose, now: now, worldEpoch: target.worldEpoch),
               let phrase = VoicePhrasing.observation(observation, named: target.label, now: now) {
                say(phrase, sceneBound: true)
            } else if let pose = frame?.pose, let direction = target.spokenDirection(pose: pose) {
                lastDirectionSpokenAt = now; say(direction)   // outside the pins' field: say where it is now, then every five seconds
            } else {
                say("I found the \(thing). The pins will point to it.", sceneBound: true)
            }
        case .notVisible: say("I couldn't see a \(thing) in the photo.")
        case .noDepth: say("I see the \(thing), but it's too far to point at.")
        case .unsupported: say("I can only look for the exit, a door, a person, a chair or common objects right now.")
        case .failed: say("I couldn't look just now. Try again.")
        }
    }
    func clearHeldTarget(spokenLine: String?) {
        guard heldTarget != nil else { return }
        heldTarget = nil; voiceSawTarget = false
        if let spokenLine { say(spokenLine) }
    }
    private func say(_ line: String, sceneBound: Bool = false) {
        whereIsNotice = line
        if voice.announce(line, automatic: false, sceneBound: sceneBound) { unspokenLine = nil }
        else { unspokenLine = (line, sceneBound, ProcessInfo.processInfo.systemUptime + 10) }
    }
    private func retryUnspokenLine(now: TimeInterval) {
        guard let pending = unspokenLine else { return }
        guard now < pending.expires, whereIsNotice == pending.line else { unspokenLine = nil; return }
        if voice.announce(pending.line, automatic: false, sceneBound: pending.sceneBound) { unspokenLine = nil }
    }

    func voiceSnapshot() -> [String: Any] {
        // Recompute age/tracking before sharing any scene-derived description.
        tick()
        let valid = mode == .live && guidanceState == .live
        return ["mode": mode.rawValue, "camera_starting": isStarting,
                "guidance": String(describing: guidanceState), "calibrated": calibrated,
                "status": status, "target": valid ? targetDescription : "No current live target observation",
                "scene_observation": valid && voiceTargetAvailable,
                "spoken_observation": valid && voiceTargetAvailable ? voiceTargetPhrase ?? "No current target" : "No current target",
                "selected_target": finder.rawValue, "puck_connected": puck.isConnected,
                "where_is_available": whereIsAvailable, "held_target": heldTarget?.label ?? "none", "where_is": whereIsNotice ?? "none",
                "connection": puck.status, "simulation": mode == .simulation,
                "spoken_replies": voice.spokenOutputEnabled, "useful_updates": voice.proactiveEnabled,
                "notice": "Neutral pins do not mean a clear path. No safe-route claim is available."]
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
            if HeldTargetGuidance.announcesTargetLost(sawTarget: voiceSawTarget, holding: heldTarget != nil) {
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
        retryUnspokenLine(now: now)
        if mode == .simulation {
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
            if mode == .live { puck.send(packet) }; updateVoiceAwareness(targetAvailable: false); return
        }
        // A held Where-is target owns the pins: finder and teammate targets never shadow it, even while it is out of the field.
        let held=heldTarget?.observation(pose:frame.pose,now:now,worldEpoch:frame.worldEpoch)
        let target=HeldTargetGuidance.pins(held:held,holding:heldTarget != nil,finder:finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target)
        let output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        packet=output.packet; guidanceState=output.state; puck.send(packet)
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@, %.1f m, %.0f°",target.label,target.distance,target.bearingDegrees)
            voiceTargetPhrase = held != nil ? VoicePhrasing.observation(target, named: target.label, now: now) : VoicePhrasing.observation(target, finder: finder, now: now)
        } else {
            voiceTargetPhrase = nil
            targetDescription=heldTarget != nil ? "Where-is target outside the pins' field" : finder == .none ? "Obstacle sensing" : "Target unavailable. No directional highlight"
        }
        updateVoiceAwareness(targetAvailable: target?.valid(at: now) == true && output.state == .live,
                             target: target, distances: frame.distances, now: now)
        if let heldTarget {
            switch HeldTargetGuidance.event(target: heldTarget, pose: frame.pose, worldEpoch: frame.worldEpoch, now: now, live: output.state == .live, inField: held != nil, lastSpokenAt: lastDirectionSpokenAt) {
            case .lostTracking: clearHeldTarget(spokenLine: "Lost tracking. Say it again.")
            case .reached: clearHeldTarget(spokenLine: "You're at the \(heldTarget.label).")
            case .speak(let direction): if voice.announce(direction, automatic: false) { lastDirectionSpokenAt = now; whereIsNotice = direction }
            case .keep: break
            }
        }
    }
}
