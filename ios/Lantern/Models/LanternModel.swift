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
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none { didSet { voice.invalidateSceneSpeech(); finderEpoch += 1; perception.setFinder(finder,epoch:finderEpoch); frame=nil; resetDirections(); targetDescription="Searching: \(finder.rawValue)" } }
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
        speakPointing(pointing.update(observation) { cell,scene in PointingDescriber.describe(cell,in:scene,targetName:name) })
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
            case .expired: text="Scene expired. Lower the puck and try again."
            case .released: continue
            }
            speakLocal(text)
        }
    }

    private func speakLocal(_ text:String) {
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification:.announcement,argument:text) }
        else { pointingSpeech.stopSpeaking(at:.immediate); pointingSpeech.speak(AVSpeechUtterance(string:text)) }
    }

    static func pointingReadout(_ o:PointingObservation,phase:PointingController.Phase)->String {
        guard o.codesSeen>0 else { return "Pointing: no codes in view" }
        var parts=["codes \(o.codesSeen)/\(PuckBackLayout.codes.count)",o.gate?.reason ?? "fit failed"]
        if let tip=o.fingertip {
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

    /// Simulation stand-in for the hand sign.
    func simulateSign() { guard mode == .simulation else { return }; pendingSign=true }

    private func resetDirections() {
        guide.reset(); cuePlayer.reset(); signTrigger.reset(); pendingSign=false
        if guidanceCue != nil { guidanceCue=nil }
        if guiding { guiding=false }
    }

    private func handleHandSign(_ observation:HandSignObservation,epoch:Int) {
        guard mode == .live,epoch==startGeneration,arrowsEnabled,!pointing.isActive else { return }
        if signTrigger.update(observation) { pendingSign=true }
        let range=observation.distance.map { String(format:"%.2f m",$0) } ?? "no hand"
        directionReadout="Arrows: "+(observation.counts ? "V sign \(range)" : observation.vSign ? "V sign too far (\(range))" : observation.distance == nil ? "no hand" : "hand, no V (\(range))")+(guiding ? " · guiding" : "")
    }

    /// Runs the arrow scheduler and draws its cue over the encoder output.
    private func withDirections(_ output:EncoderOutput,hint:RouteHint?,now:TimeInterval)->EncoderOutput {
        guard arrowsEnabled else { return output }
        let result=guide.update(now:now,sign:pendingSign,hint:hint); pendingSign=false
        if let cue=result.play { cuePlayer.play(cue,now:now) }
        speakDirections(result.events,label:hint?.label)
        let shown=cuePlayer.apply(to:output,now:now)
        let cue=guide.active ? guide.lastPlayed : nil
        if guidanceCue != cue { guidanceCue=cue }
        if guiding != guide.active { guiding=guide.active }
        return shown
    }

    private func speakDirections(_ events:[GuideEvent],label:String?) {
        let target=label ?? Self.spokenTargetName(finder) ?? "target"
        for event in events {
            let text: String
            switch event {
            case .started(let cue):
                // Success: chime first, then the first arrow is spoken once the chime has finished.
                chime.play()
                DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in self?.speakLocal("\(cue.spoken). Guiding to \(target).") }
                continue
            case .changed(let cue),.repeated(let cue): text=cue.spoken
            case .arrived: text="You're at the \(target). Arrows off."
            case .noTarget: text=finder == .none ? "Choose a target first." : "No \(target) in view."
            case .noRoute: text="No way through the mapped area. Look around slowly."
            case .lost: text="Lost sight of the \(target). Arrows off."
            }
            speakLocal(text)
        }
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
            _=withDirections(.init(packet:packet,state:guidanceState),hint:nil,now:now)
            if mode == .live { puck.send(packet) }; updateVoiceAwareness(targetAvailable: false); return
        }
        let target=finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target
        let encoded=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:frame.distances,target:target,floorCalibrated:frame.floorY != nil)
        pointing.record(CachedScene(timestamp:frame.timestamp,pose:frame.pose,tracking:encoded.state == .live,distances:frame.distances,target:target?.valid(at:frame.timestamp) == true ? target : nil))
        speakPointing(pointing.tick(now:now))
        // While pointing, the pins hold the scene from before the hand came up; arrows pause.
        let frozen=pointing.frozenOutput(sequence:sequence)
        if frozen != nil { cuePlayer.reset(); pendingSign=false }
        let output=frozen.map { EncoderOutput(packet:$0.packet,state:encoded.state,targetColumns:$0.targetColumns) } ?? withDirections(encoded,hint:frame.routeHint,now:now)
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
