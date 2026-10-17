import Foundation
import Combine
import AVFoundation
import UIKit
import FeelCore

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
    /// Depth-only session recording for offline replay (simulation/run.py). Stops with sensing.
    @Published var recordingDepth=false {
        didSet {
            guard recordingDepth != oldValue else { return }
            if recordingDepth { perception.recorder.start(cameraHeight:cameraHeight,video:recordingVideo) } else { perception.recorder.stop() }
        }
    }
    /// Also save the camera as video beside the depth recording, for the /replay viewer. Local until shared.
    @Published var recordingVideo = UserDefaults.standard.object(forKey: "recordingVideo") as? Bool ?? true {
        didSet { UserDefaults.standard.set(recordingVideo, forKey: "recordingVideo") }
    }
    @Published private(set) var recordingStatus: String?
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none { didSet { voice.invalidateSceneSpeech(); finderEpoch += 1; perception.setFinder(finder,epoch:finderEpoch); frame=nil; resetGuidance(); targetDescription="Searching: \(finder.rawValue)" } }
    /// Direction arrows on request: a V sign plays one arrow along the route to the visible target,
    /// then only noticeable route changes play again. Obstacles within 0.9 m always override it.
    @Published var arrowsEnabled = UserDefaults.standard.object(forKey: "directionArrowsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(arrowsEnabled, forKey: "directionArrowsEnabled"); resetDirections() }
    }
    /// The last arrow played while guidance is on, for the on-screen title.
    @Published private(set) var guidanceCue: DirectionCue?
    @Published private(set) var guiding = false
    @Published private(set) var directionReadout = "Arrows: make a V sign close to the camera"
    /// Columns showing the target; several columns tap together.
    @Published private(set) var targetColumns: ClosedRange<Int>?
    /// Point-to-describe status, for the accuracy test and sighted helpers.
    @Published private(set) var pointingReadout = "Pointing: hold the puck's back to the camera, thumb up"
    enum VoicePanel: String { case settings, connection }
    @Published var voicePanel: VoicePanel?
    let voice: GrokVoiceSession
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
    private var signTrigger=HandSignTrigger()
    private var guide=DirectionGuide()
    private var cuePlayer=CuePlayer()
    private var pendingSign=false
    /// Two-finger route: when the goal was handed to perception, waiting for its first route hint.
    private var pointingRouteSetAt: TimeInterval?
    private var pointingRouteActive=false
    /// Two fingers on a column too close to route to: tap that column for a few seconds instead.
    private var pointingHighlight: (column: Int, band: UInt8, until: TimeInterval)?
    private let pointingHighlightSeconds=3.0
    private var request=DirectionRequest()
    private lazy var listener: KeywordListener = {
        let listener=KeywordListener(voice:voice)
        listener.onWord={ [weak self] word in self?.heard(word) }
        return listener
    }()
    /// Visible candidates from the latest tick, and the ones offered in the last question.
    private var lastChoices: [VisibleCandidate]=[]
    private var askedChoices: [VisibleCandidate]=[]
    private var targetLocked=false
    private var pointing=PointingController()
    private let pointingSpeech=AVSpeechSynthesizer()
    private let chime=Chime()
    init(voice: GrokVoiceSession = GrokVoiceSession()) {
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
        perception.recorder.onStatus={ [weak self] status in
            guard let self else { return }
            self.recordingStatus=status
            // Size limit or a write error ends recording on its own.
            if let status, status.hasPrefix("Recording stopped") || status.hasPrefix("Recording failed") { self.recordingDepth=false }
        }
        perception.onFrame={ [weak self] frame in guard let self,self.mode == .live,frame.epoch==self.startGeneration,frame.finderEpoch==self.finderEpoch else { return }; self.frame=frame; self.calibrated=frame.floorY != nil }
        perception.onInvalidated={ [weak self] epoch in guard let self,epoch==self.startGeneration else { return }; self.frame=nil; self.calibrated=false; self.tick() }
        perception.onStatus={ [weak self] text in guard let self,self.mode == .live else { return }; self.status=text }
        perception.onModelStatus={ [weak self] text,available in self?.detectorStatus=text; self?.detectorAvailable=available }
        perception.onPointing={ [weak self] epoch,observation in self?.handlePointing(observation,epoch:epoch) }
        perception.onHandSign={ [weak self] epoch,observation in self?.handleHandSign(observation,epoch:epoch) }
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
            if self.arrowsEnabled { self.listener.prepare() }
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
        resetDirections()
        pointing.reset(); targetColumns=nil; pointingSpeech.stopSpeaking(at:.immediate)
        recordingDepth=false
        pointingHighlight=nil
        perception.stop(); peer.stop(); mode = .stopped; guidanceState = .stopped
        sequence &+= 1; packet = .neutral(sequence:sequence); puck.send(packet)
        status="Stopped. Neutral command sent if connected"; targetDescription="No guidance"
        UIApplication.shared.isIdleTimerDisabled=voice.isActive
        voiceSawTarget = false; voiceTargetLostAt = nil; voiceLastGuidance = nil
    }
    private func beginTimer() {
        UIApplication.shared.isIdleTimerDisabled=true
        let timer=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in self?.tick() }
        self.timer=timer; RunLoop.main.add(timer,forMode:.common); tick()
    }
    func performVoiceCommand(_ command: VoiceCommand) -> [String: Any] {
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
        case .openSettings:
            voicePanel = .settings
            return ["status": "Settings opened."]
        case .chooseTarget(let option):
            let actions=request.chose(option-1,now:ProcessInfo.processInfo.systemUptime)
            guard !actions.isEmpty else { return ["error": "No choice is pending, or that option doesn't exist."] }
            perform(actions)
            return ["status": "Choice received. The app confirms with a sound. Say nothing more."]
        }
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
                "selected_target": finder.rawValue, "direction_arrows": arrowsEnabled ? (guiding ? "guiding" : "waiting for V sign") : "off", "puck_connected": puck.isConnected,
                "connection": puck.status, "simulation": mode == .simulation,
                "notice": "Neutral pins do not mean a clear path. No safe-route claim is available."]
    }

    private func updateVoiceAwareness(targetAvailable: Bool) {
        voiceTargetAvailable = targetAvailable
        guard voice.isActive else {
            voiceSawTarget = false; voiceLastGuidance = nil; voiceHadConnection = puck.isConnected
            return
        }
        if !targetAvailable || guidanceState != .live { voice.invalidateSceneSpeech() }
        if voiceHadConnection && !puck.isConnected {
            if voice.announce("The puck disconnected. Tactile feedback is unavailable.") { voiceHadConnection = false }
            return
        }
        voiceHadConnection = puck.isConnected
        guard mode == .live else { voiceSawTarget = false; voiceLastGuidance = nil; return }
        if guidanceState != .live {
            voiceSawTarget = false
            if voiceLastGuidance != guidanceState {
                let message = calibrated ? "Sensing stopped. Pins are neutral." : "What's the measured camera height? I need it to calibrate."
                if voice.announce(message) { voiceLastGuidance = guidanceState }
            }
            return
        }
        voiceLastGuidance = .live
        if !targetAvailable {
            if voiceSawTarget {
                let now = ProcessInfo.processInfo.systemUptime
                if voiceTargetLostAt == nil { voiceTargetLostAt = now }
                if now - (voiceTargetLostAt ?? now) >= 0.6,
                   voice.announce("I no longer see your target.") {
                    voiceSawTarget = false
                }
            }
        } else {
            voiceTargetLostAt = nil
            if !voiceSawTarget, let voiceTargetPhrase,
               voice.announce(voiceTargetPhrase, sceneBound: true) {
                voiceSawTarget = true
            }
        }
    }

    private func handlePointing(_ observation:PointingObservation,epoch:Int) {
        guard mode == .live,epoch==startGeneration else { return }
        let name=Self.spokenTargetName(finder)
        speakPointing(pointing.update(observation,targetName:name) { cell,scene in PointingDescriber.describe(cell,in:scene,targetName:name) })
        pointingReadout=Self.pointingReadout(observation,phase:pointing.phase)
    }

    private static func spokenTargetName(_ finder:FinderMode)->String? {
        switch finder {
        case .none: return nil
        case .door: return "Possible door"
        case .exit: return "Exit sign"
        case .chair: return "Chair"
        case .person: return "Person"
        case .teammate: return "Your teammate"
        }
    }

    /// Local speech: immediate, no network, and not throttled like assistant announcements.
    private func speakPointing(_ events:[PointingEvent]) {
        for event in events {
            let text: String
            switch event {
            case .armed: text="Pointing"
            case .described(_,let description): text=description
            case .refused(let reason): text=reason
            case .routeSet(let route,let spoken):
                // Too close to route: confirm with a chime only (direction feedback is sounds and pins).
                if route.highlightOnly || spoken.isEmpty { chime.play(.success); continue }
                text=spoken
            case .expired: text="Scene expired. Lower the puck and try again."
            case .released(let route):
                guard let route else { continue }
                if route.highlightOnly {
                    pointingHighlight=(route.column,route.band,ProcessInfo.processInfo.systemUptime+pointingHighlightSeconds)
                } else { startPointingRoute(route) }
                continue
            }
            speakLocal(text)
        }
    }

    /// Firmware tap on the two-finger column for a few seconds. Raises the cached band if the live
    /// pin there is down (a tap needs a raised pin). Steps aside for arrows and for a band-1
    /// obstacle in another column.
    private func withPointingHighlight(_ output:EncoderOutput,now:TimeInterval)->EncoderOutput {
        guard let h=pointingHighlight else { return output }
        guard now<h.until else { pointingHighlight=nil; return output }
        var bands=output.packet.bands
        guard output.state == .live, !cuePlayer.isAnimating, (0..<7).contains(h.column),
              !bands.indices.contains(where: { $0 != h.column && bands[$0] == 1 }) else { return output }
        if bands[h.column] == 0 { bands[h.column]=h.band }
        guard bands[h.column]>0,let packet=try? FeelPacket(sequence:output.packet.sequence,bands:bands,highlight:UInt8(h.column)) else { return output }
        return EncoderOutput(packet:packet,state:output.state,targetColumns:h.column...h.column)
    }

    /// Hand a two-finger goal to the route planner; arrows start once a route to it exists.
    private func startPointingRoute(_ route:PointingRoute) {
        guard arrowsEnabled else { speakLocal("Direction arrows are turned off in settings."); return }
        perception.setRouteGoal(route.goal,label:route.label)
        pointingRouteSetAt=ProcessInfo.processInfo.systemUptime; pointingRouteActive=true
    }

    private func clearPointingRoute() {
        guard pointingRouteActive else { return }
        perception.setRouteGoal(nil); pointingRouteSetAt=nil; pointingRouteActive=false
    }

    /// Starts the arrow guide when the planner has a route for the pointing goal (or reports failure
    /// if none comes within 2 s).
    private func tickPointingRoute(now:TimeInterval,hint:RouteHint?) {
        guard let setAt=pointingRouteSetAt else { return }
        if let hint,hint.timestamp>setAt { pendingSign=true; pointingRouteSetAt=nil }
        else if now-setAt>2 { pendingSign=true; pointingRouteSetAt=nil }
    }

    private func speakLocal(_ text:String) {
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification:.announcement,argument:text) }
        else { pointingSpeech.stopSpeaking(at:.immediate); pointingSpeech.speak(AVSpeechUtterance(string:text)) }
    }

    static func pointingReadout(_ o:PointingObservation,phase:PointingController.Phase)->String {
        guard o.codesSeen>0 else { return "Pointing: no codes in view" }
        var parts=["codes \(o.codesSeen)/\(PuckBackLayout.codes.count)",o.gate?.reason ?? "fit failed"]
        if o.fingers == 2 {
            parts.append(o.routeColumn.map { "two fingers → C\($0) route" } ?? "two fingers: lay them along one column")
            parts.append(o.method == .handPose ? "hand" : "tape")
        } else if let tip=o.fingertip {
            parts.append(String(format:"tip %.0f, %.0f mm",tip.x,tip.y))
            parts.append(o.cell.map { "\($0)" } ?? "off grid")
            parts.append(o.method == .handPose ? "hand" : "tape")
        } else if o.gate?.ok == true { parts.append("no fingertip") }
        switch phase {
        case .idle: break
        case .armed: parts.append("pins frozen")
        case .expired: parts.append("expired")
        case .refused: parts.append("refused")
        }
        return "Pointing: "+parts.joined(separator:" · ")
    }

    /// Simulation stand-in for the hand sign: no word, guide to the synthetic target.
    func simulateSign() { guard mode == .simulation else { return }; pendingSign=true }

    /// Ends guidance (finder change); a request in flight keeps going.
    private func resetGuidance() {
        guide.reset(); cuePlayer.reset(); pendingSign=false; targetLocked=false; askedChoices=[]
        if pointingRouteActive { perception.setRouteGoal(nil) }; pointingRouteSetAt=nil; pointingRouteActive=false
        if guidanceCue != nil { guidanceCue=nil }
        if guiding { guiding=false }
    }

    private func resetDirections() {
        resetGuidance(); signTrigger.reset(); request.reset(); listener.stop()
    }

    private static func word(_ finder:FinderMode)->TargetWord? {
        switch finder {
        case .none: return nil
        case .door: return .door
        case .exit: return .exit
        case .chair: return .chair
        case .person: return .person
        case .teammate: return .teammate
        }
    }
    private static func finder(_ word:TargetWord)->FinderMode {
        switch word { case .door: return .door; case .exit: return .exit; case .chair: return .chair; case .person: return .person; case .teammate: return .teammate }
    }

    private func handleHandSign(_ observation:HandSignObservation,epoch:Int) {
        guard mode == .live,epoch==startGeneration,arrowsEnabled,!pointing.isActive else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let wasHolding=signTrigger.holding
        let fired=signTrigger.update(observation)
        // Start listening as soon as the sign appears, so "[V] exit" said together is heard.
        if !wasHolding && signTrigger.holding { perform(request.handBegan(now:now)) }
        if fired {
            request.listenSeconds=listener.isAvailable ? 2.5 : 0
            perform(request.signFired(now:now,selected:Self.word(finder)))
        }
        let range=observation.distance.map { String(format:"%.2f m",$0) } ?? "no hand"
        directionReadout="Arrows: "+(observation.counts ? "V sign \(range)" : observation.vSign ? "V sign too far (\(range))" : observation.distance == nil ? "no hand" : "hand, no V (\(range))")+(listener.isListening ? " · listening" : "")+(guiding ? " · guiding" : "")
    }

    private func heard(_ word:TargetWord) {
        guard mode == .live else { return }
        perform(request.heardWord(word,now:ProcessInfo.processInfo.systemUptime,selected:Self.word(finder)))
    }

    private func perform(_ actions:[RequestAction]) {
        for action in actions {
            switch action {
            case .startListening: listener.start()
            case .stopListening: listener.stop()
            case .sound(let sound):
                if sound == .listening && !listener.isListening { continue }
                chime.play(sound)
            case .select(let word):
                let mode=Self.finder(word)
                if mode == .chair && !detectorAvailable { request.reset(); chime.play(.failure); return }
                if finder != mode { finder=mode }
            case .ask(let choices):
                askedChoices=lastChoices
                if !voice.ask(TargetChoice.question(choices,word:request.heard)) {
                    // No assistant to ask: take the one most straight ahead.
                    let ahead=choices.indices.min { abs(choices[$0].bearingDegrees)<abs(choices[$1].bearingDegrees) } ?? 0
                    perform(request.chose(ahead,now:ProcessInfo.processInfo.systemUptime))
                }
            case .lock(let index):
                let list=askedChoices.isEmpty ? lastChoices : askedChoices
                askedChoices=[]
                guard list.indices.contains(index) else { continue }
                perception.lockTarget(at:list[index].position); targetLocked=true
            case .startGuidance:
                clearPointingRoute(); pendingSign=true
            }
        }
    }

    /// Runs the arrow scheduler and draws its cue over the encoder output. Sounds only, no speech:
    /// success when guidance starts, repeats or arrives; failure when it can't start or is lost.
    private func withDirections(_ output:EncoderOutput,hint:RouteHint?,now:TimeInterval)->EncoderOutput {
        guard arrowsEnabled else { return output }
        let result=guide.update(now:now,sign:pendingSign,hint:hint); pendingSign=false
        if let cue=result.play { cuePlayer.play(cue,now:now) }
        for event in result.events {
            switch event {
            case .started,.repeated: chime.play(.success)
            case .arrived: chime.play(.success); clearPointingRoute()
            case .noTarget,.noRoute,.lost: chime.play(.failure); clearPointingRoute()
            case .changed: break
            }
        }
        let shown=cuePlayer.apply(to:output,now:now)
        let cue=guide.active ? guide.lastPlayed : nil
        if guidanceCue != cue { guidanceCue=cue }
        if guiding != guide.active { guiding=guide.active }
        return shown
    }

    /// Advances a V-sign request with what perception currently sees.
    private func tickRequest(now:TimeInterval,candidates:[VisibleCandidate],hint:RouteHint?) {
        guard request.isBusy else { return }
        lastChoices=candidates
        perform(request.tick(now:now,selected:Self.word(finder),
                             choices:candidates.map { TargetChoice(bearingDegrees:$0.observation.bearingDegrees,distance:$0.observation.distance) },
                             hintTime:hint?.timestamp,lockedTarget:targetLocked,agentAvailable:voice.phase == .listening))
    }

    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime; sequence &+= 1
        if mode == .simulation {
            let phase=(now-simulatedAt).truncatingRemainder(dividingBy:12)
            let tracking=phase<8 || phase>=10
            let target=TargetObservation(bearingDegrees:sin(phase/2)*40,distance:1.3,timestamp:now,label:"SIMULATED target")
            let near=phase>=4 && phase<6
            let encoded=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:now,tracking:tracking,distances:[near ? 0.7 : nil,1.1,nil,2,3.5,nil,nil],target:target)
            // Simulated route: straight to the synthetic target, no floor map.
            let hint=tracking ? RouteHint(timestamp:now,status:.route,bearingDegrees:target.bearingDegrees,targetDistance:target.distance,routeLength:target.distance,label:"simulated target") : nil
            let output=withDirections(EncoderOutput(packet:encoded.packet,state:encoded.state == .live ? .simulation : encoded.state),hint:hint,now:now)
            packet=output.packet; guidanceState=output.state
            targetDescription=tracking ? "SIMULATED target sweeping left to right" : "SIMULATED tracking loss. All pins neutral"
            return
        }
        guard mode == .live,let frame else {
            packet = .neutral(sequence:sequence); guidanceState = mode == .live ? .staleDepth : .stopped
            cuePlayer.reset(); targetColumns=nil
            tickRequest(now:now,candidates:[],hint:nil)
            _=withDirections(.init(packet:packet,state:guidanceState),hint:nil,now:now)
            if mode == .live { puck.send(packet) }; updateVoiceAwareness(targetAvailable: false); return
        }
        let target=finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target
        let encoded=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        pointing.record(CachedScene(timestamp:frame.timestamp,pose:frame.pose,tracking:encoded.state == .live,distances:frame.distances,target:target?.valid(at:frame.timestamp) == true ? target : nil))
        speakPointing(pointing.tick(now:now))
        // While pointing, the pins hold the scene from before the hand came up; arrows pause.
        let frozen=pointing.frozenOutput(sequence:sequence)
        if frozen != nil { cuePlayer.reset(); pendingSign=false } else { tickRequest(now:now,candidates:frame.candidates,hint:frame.routeHint); tickPointingRoute(now:now,hint:frame.routeHint) }
        let output=frozen.map { EncoderOutput(packet:$0.packet,state:encoded.state,targetColumns:$0.targetColumns) } ?? withPointingHighlight(withDirections(encoded,hint:frame.routeHint,now:now),now:now)
        packet=output.packet; guidanceState=output.state; targetColumns=output.targetColumns; puck.send(packet)
        if pointing.isActive {
            // The arm in front of the camera must not trigger target-lost or sensing announcements.
            targetDescription="Pointing · pins hold the scene from before your hand came up"; voiceTargetPhrase=nil; return
        }
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@, %.1f m, %.0f°",target.label,target.distance,target.bearingDegrees)+(guidanceCue.map { " · guiding: "+$0.spoken } ?? "")
            voiceTargetPhrase = VoicePhrasing.observation(target, finder: finder, now: now)
        } else {
            voiceTargetPhrase = nil
            targetDescription=finder == .none ? "Obstacle sensing" : "Target unavailable. No directional highlight"
        }
        updateVoiceAwareness(targetAvailable: target?.valid(at: now) == true && output.state == .live)
    }
}
