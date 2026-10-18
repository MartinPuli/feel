import Foundation
import Combine
import AVFoundation
import ARKit
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
    var automaticFloorCalibrationSupported: Bool { ARPlaneAnchor.isClassificationSupported }
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
    /// Grid-walk trial: a timed, recorded walk with marked events (ARKit clock, same as the recording).
    struct TrialEvent: Equatable { let t: TimeInterval; let kind: String }
    @Published private(set) var trialStart: Date?
    @Published private(set) var trialEvents: [TrialEvent] = []
    @Published private(set) var lastTrialSummary: String?
    @Published var cameraHeight=1.2
    @Published var finder:FinderMode = .none { didSet { places.stop(); voice.invalidateSceneSpeech(); proactiveVoice.reset(); voiceNotice = nil; voiceSawTarget = false; cancelWhereIs(); finderEpoch += 1; perception.setFinder(finder,epoch:finderEpoch); frame=nil; resetGuidance(); targetDescription="Searching: \(finder.rawValue)" } }
    /// Direction arrows on request: a V sign plays one arrow along the route to the visible target,
    /// then only noticeable route changes play again. Obstacles within 0.9 m always override it.
    @Published var arrowsEnabled = UserDefaults.standard.object(forKey: "directionArrowsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(arrowsEnabled, forKey: "directionArrowsEnabled"); resetDirections() }
    }
    /// The last arrow played while guidance is on, for the on-screen title.
    @Published private(set) var guidanceCue: DirectionCue?
    /// Which side has more room while something is within 1.6 m ahead; relative room, never a safe path.
    @Published private(set) var openSide: OpenSide?
    private var openSideFinder=OpenSideFinder()
    private var lastOpenSideCue: (column: Int, at: TimeInterval)?
    @Published private(set) var guiding = false
    @Published private(set) var directionReadout = "Arrows: make a V sign close to the camera"
    /// Columns showing the target; several columns tap together.
    @Published private(set) var targetColumns: ClosedRange<Int>?
    /// Point-to-describe status, for the accuracy test and sighted helpers.
    @Published private(set) var pointingReadout = "Pointing: hold the puck's back to the camera, thumb up"
    enum VoicePanel: String { case settings, connection, assistant, closed }
    @Published var voicePanel: VoicePanel?
    @Published var voiceControlsExpanded: Bool?
    private var voiceTeammates: [String: MCPeerID] = [:]
    let voice: RealtimeVoiceSession
    let venueInfo: VenueInfo
    let places = SessionPlaces()
    let savedMaps = SavedWorldMaps()
    private var restoredMapSession = false
    var canFindTeammates: Bool { mode == .live && !restoredMapSession && !savedMaps.isRestoring }
    @Published private(set) var memorySimulation = false
    @Published private(set) var simulatedMemoryTracking = true
    private var simulatedMemoryPosition = Vector3(0, 1.2, 0)
    private var simulatedMemoryYaw = 0.0
    let localVoice = LocalVoiceControl()
    let chalkCommands = ChalkCommandCoordinator()
    @Published var localCommandLanguage: VoiceLanguage = .en
    @Published var localCommandStatus = "Local commands stay on this iPhone."
    @Published var tactileProfile: AdaptiveProfile = .standard
    private var adaptiveTactile = AdaptiveTactileController()
    /// Targets confirmed on earlier visits, in the frame of the printed room tag; answers Where-is before any photo.
    let roomMemory: RoomMemory
    @Published private(set) var chalkConfiguration: ChalkConfiguration?
    @Published private(set) var heldTarget: HeldTarget?
    /// The next progress point on the way to the held target, once its route was split (WaypointFollower): the
    /// pins point here instead of at the target itself. Nil while a target has no route, so the straight bearing shows.
    @Published private(set) var waypoint: HeldTarget?
    private var follower: WaypointFollower?
    /// The floor frame the progress points are in: the tag's levelled frame when a tag was seen in this world, else the world floor.
    private var followFrame: RoomFrame?
    /// Every walk toward a chosen target, recorded in the tag frame for Chalk.
    let journeyLog: JourneyLog
    /// Where finds, anchors, room maps and journeys leave the phone (SupabaseWriter); nil keeps everything on the phone.
    private let uploader: MemoryUploading?
    private let chalkQuery: ChalkQuerying?
    @Published private(set) var lastSeenNotice: String?
    private var lastSeenRequest = 0
    private var contextIdentity: UUID?
    private var contextVenue: String?
    private var sharedPriorWorld: Int?
    var contextReadsEnabled: Bool { chalkQuery?.isEnabled ?? false }
    var contextReadsAvailable: Bool { chalkQuery != nil }
    lazy var floorPriorClearer: (Int) -> Void = { [perception] world in perception.clearFloorPrior(worldEpoch: world) }

    var memoryUploadsEnabled: Bool { (uploader as? SupabaseWriter)?.uploadsEnabled ?? false }
    var sharedRoomMemoryEnabled: Bool { (uploader as? SupabaseWriter)?.sharesRoomMemory ?? false }
    var memoryUploadStatus: String {
        guard let report = uploader?.statusReport else { return "Cloud memory unavailable." }
        return "Sent: \(report["sent"] ?? 0). Failed: \(report["failed"] ?? 0). \(report["last_error"] as? String ?? "")"
    }
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
    /// How a remembered room map reaches the route planner (map, tag frame, world epoch); tests record the calls instead.
    lazy var floorGridSeeder: (RoomMap, RoomFrame, Int) -> Void = { [perception] map, frame, worldEpoch in perception.seedFloorGrid(map, frame: frame, worldEpoch: worldEpoch) }
    var whereIsAvailable: Bool { mode == .live && guidanceState == .live }
    private var proactiveVoice = ProactiveVoicePolicy()
    private var voiceNotice: ProactiveVoicePolicy.Notice?
    private enum VoiceStateNotice: Equatable { case guidance(GuidanceState), targetLost, puckDisconnected }
    private var voiceStateNotice: VoiceStateNotice?
    private var voiceSawTarget = false
    private var voiceTargetAvailable = false
    private var voiceTargetPhrase: String?
    private var voiceLastGuidance: GuidanceState?
    private var voiceHadConnection = false
    private var voiceOwnsScan = false
    private var voiceStateSubscription: AnyCancellable?
    private var voiceOutputSubscription: AnyCancellable?
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
    /// Steadies the sector ranges per depth frame so the pins do not flutter (shared with replay).
    private var sectorFilter=SectorFilter()
    /// Passive wave from the centre toward the route while the wearer turns; no sign needed.
    private var pathWave=PathWave()
    /// Steady obstacle pins drop for one frame once a second (FeelCore TapRhythm): what keeps them felt. Target columns keep their own taps.
    private var tapRhythm=TapRhythm()
    private var pendingSign=false
    /// Two-finger route: when the goal was handed to perception, waiting for its first route hint.
    private var pointingRouteSetAt: TimeInterval?
    private var pointingRouteActive=false
    /// The route goal is a Where-is target: no failure tone while the planner has no route yet.
    private var heldRoute=false
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
    init(voice: RealtimeVoiceSession = RealtimeVoiceSession(), chalkStore: ChalkConfigurationStoring = ChalkConfigurationStore(),
         gatewayFactory: @escaping (ChalkConfiguration) -> ChatGateway = { ChalkGateway(configuration: $0) },
         localFinder: LocalWhereIsFinding? = nil, roomMemory: RoomMemory = RoomMemory(), journeyLog: JourneyLog = JourneyLog(),
         uploader: MemoryUploading? = SupabaseWriter.forLaunch(), venueInfo: VenueInfo = VenueInfo(),
         chalkQuery: ChalkQuerying? = ChalkQueryClient.forLaunch()) {
        self.voice = voice; self.chalkStore = chalkStore; self.gatewayFactory = gatewayFactory; self.roomMemory = roomMemory; self.journeyLog = journeyLog; self.uploader = uploader; self.venueInfo = venueInfo
        self.chalkQuery = chalkQuery
        contextIdentity = chalkQuery?.sessionIdentity; contextVenue = venueInfo.pack?.venueId
        if roomMemory.reader == nil, let chalkQuery { roomMemory.reader = ChalkSharedMemory(client: chalkQuery) }
        roomMemory.venue = { [venueInfo] in venueInfo.pack?.venueId }
        roomMemory.isLive = { [weak self] in
            guard let self, self.mode == .live, let frame = self.frame, frame.tracking,
                  frame.epoch == self.startGeneration, !self.savedMaps.isRestoring else { return false }
            let age = ProcessInfo.processInfo.systemUptime - frame.timestamp
            return age >= 0 && age <= 0.5
        }
        roomMemory.onSharedStructure = { [weak self] sighting in
            guard let self, self.mode == .live, let frame = self.frame, frame.tracking,
                  frame.worldEpoch == sighting.worldEpoch, !self.savedMaps.isRestoring,
                  let map = self.roomMemory.structureToSeed(for: sighting) else { return }
            self.sharedPriorWorld = sighting.worldEpoch
            self.floorGridSeeder(map, sighting.frame, sighting.worldEpoch)
        }
        roomMemory.onSharedInvalidated = { [weak self] in
            guard let self, let world = self.sharedPriorWorld else { return }
            self.sharedPriorWorld = nil; self.floorPriorClearer(world)
        }
        if roomMemory.uploader == nil { roomMemory.uploader = uploader }
        if journeyLog.uploader == nil { journeyLog.uploader = uploader }
        (uploader as? SupabaseWriter)?.venue = { [venueInfo] in venueInfo.pack.map { VenueRef(id: $0.venueId, name: $0.venueName) } }
        if let localFinder { self.localFinder = localFinder }
        chalkConfiguration = chalkStore.loadForLaunch()
        chalkCommands.captureContext = { [weak self] in
            guard let self, let session = self.places.memory.session else { return nil }
            return ChalkCommandSnapshot(sessionId: session, context: ChalkContext(
                places: self.places.memory.bookmarks.map { ChalkPlace(id: $0.id, name: $0.name) },
                trackingValid: self.places.hasFreshContext, restoring: self.savedMaps.isRestoring,
                mode: self.mode.rawValue.lowercased(), hasReturnPoint: self.places.memory.returnPoint != nil))
        }
        chalkCommands.applyDecision = { [weak self] decision in
            guard let self else { return "App unavailable." }
            let result: [String: Any]
            switch decision.action {
            case .remember: result = self.performVoiceCommand(.rememberPlace(decision.name ?? ""))
            case .recall: result = self.performVoiceCommand(.recallPlace(decision.placeId ?? ""))
            case .returnToPoint: result = self.performVoiceCommand(.returnToPoint)
            case .stop: result = self.performVoiceCommand(.stop)
            case .listPlaces:
                let names = self.places.memory.bookmarks.map(\.name)
                result = ["status": names.isEmpty ? "No places saved." : names.joined(separator: ", ")]
            case .clarify, .reject: result = ["status": decision.message]
            }
            let line = result["error"] as? String ?? result["status"] as? String ?? "Request completed."
            if self.voice.isActive { self.say(line) }
            else if self.voice.spokenOutputEnabled, !self.localVoice.hasPendingAttempt { self.localVoice.speak(String(line.prefix(160)), localeIdentifier: "en-US") }
            return line
        }
        localVoice.onCaptureWillStart = { [weak self] in
            guard let self else { return }
            self.cancelLastSeen()
            self.chalkCommands.cancel(reason: "Local voice command started.")
            self.resetDirections(); self.pointingSpeech.stopSpeaking(at: .immediate)
            self.voice.pauseForLocalCommand()
        }
        localVoice.onFinalTranscript = { [weak self] text in _ = self?.performLocalCommand(text) }
        voice.onCommand = { [weak self] command in self?.performVoiceCommand(command) ?? ["error": "App unavailable"] }
        voice.onEnded = { [weak self] in
            guard let self else { return }
            if self.voiceOwnsScan { self.puck.stopScanning(); self.voiceOwnsScan = false }
        }
        voiceStateSubscription = voice.$phase.sink { [weak self] phase in
            guard let self else { return }
            if phase == .connecting { self.localVoice.cancel() }
            UIApplication.shared.isIdleTimerDisabled = self.mode != .stopped || self.isStarting || (phase != .idle && phase != .failed)
        }
        voiceOutputSubscription = voice.$spokenOutputEnabled.sink { [weak self] enabled in
            if !enabled { self?.pointingSpeech.stopSpeaking(at: .immediate); self?.localVoice.stopReadback() }
        }
        savedMaps.capture = { [weak self] world, completion in
            self?.perception.captureWorldMap(worldEpoch: world, completion: completion)
        }
        savedMaps.onRestoreRequested = { [weak self] map, mapID in
            guard let self else { return false }
            self.startLive(restoredMap: map, mapID: mapID)
            return self.mode == .live || self.isStarting
        }
        savedMaps.onRestored = { [weak self] archive, world in
            guard let self else { return }
            do { try self.places.restore(archive, worldEpoch: world); self.featureNotice("Room matched. Choose a place to recall.") }
            catch { self.places.end(); self.featureNotice("Saved places could not be restored.") }
        }
        perception.onSavedMapWorldStarted = { [weak self] epoch, world, mapID in self?.savedMaps.worldStarted(epoch: epoch, worldEpoch: world, mapID: mapID) }
        perception.onSavedMapWorldEnded = { [weak self] epoch, world in self?.savedMaps.worldEnded(epoch: epoch, worldEpoch: world) }
        perception.onSavedMapObservation = { [weak self] observation in self?.savedMaps.observe(observation) }
        peer.arSession=perception.session
        perception.recorder.onStatus={ [weak self] status in
            guard let self else { return }
            self.recordingStatus=status
            // Size limit or a write error ends recording on its own.
            if let status, status.hasPrefix("Recording stopped") || status.hasPrefix("Recording failed") { self.recordingDepth=false }
        }
        perception.onFrame={ [weak self] frame in guard let self,self.mode == .live,frame.epoch==self.startGeneration,frame.finderEpoch==self.finderEpoch else { return }; self.frame=frame; self.calibrated=frame.floorY != nil; if !frame.tracking && self.chalkCommands.isBusy { self.chalkCommands.cancel(reason: "Tracking lost.") }; self.places.observe(pose: frame.pose, worldEpoch: frame.worldEpoch, timestamp: frame.timestamp, tracking: frame.tracking) }
        perception.onInvalidated={ [weak self] epoch in guard let self,epoch==self.startGeneration else { return }; self.frame=nil; self.calibrated=false; self.places.invalidate(); self.chalkCommands.cancel(reason: "Tracking reset."); self.roomMemory.forgetTag(); self.clearHeldTarget(spokenLine: "Lost tracking. Say it again."); self.resetDirections(); self.pointing.reset(); self.pointingHighlight=nil; self.tick() }
        perception.onTag={ [weak self] epoch,sighting in guard let self,self.mode == .live,epoch==self.startGeneration else { return }; self.sawTag(sighting) }
        // A map is a visit in the tag's own frame: it stays valid however the session that produced it ended.
        perception.onRoomMap={ [weak self] tagId,map in self?.roomMemory.keepStructure(map,tagId:tagId) }
        perception.onStatus={ [weak self] text in guard let self,self.mode == .live else { return }; self.status=text }
        perception.onModelStatus={ [weak self] text,available in self?.detectorStatus=text; self?.detectorAvailable=available }
        perception.onPointing={ [weak self] epoch,observation in self?.handlePointing(observation,epoch:epoch) }
        perception.onHandSign={ [weak self] epoch,observation in self?.handleHandSign(observation,epoch:epoch) }
    }
    @discardableResult func performLocalCommand(_ text: String) -> [String: Any] {
        cancelLastSeen()
        localVoice.cancel()
        chalkCommands.cancel(reason: "A local command replaced the request.")
        let response: [String: Any]
        do {
            let intent = try LocalCommandInterpreter.parse(text, language: localCommandLanguage)
            switch intent {
            case .remember(let name): response = performVoiceCommand(.rememberPlace(name))
            case .recall(let name):
                let matches = places.memory.bookmarks.filter { LocalCommandInterpreter.normalized($0.name) == LocalCommandInterpreter.normalized(name) }
                if matches.count == 1 { response = performVoiceCommand(.recallPlace(matches[0].id)) }
                else { response = ["error": "No unique saved place has that name."] }
            case .returnToPoint: response = performVoiceCommand(.returnToPoint)
            case .stop: response = performVoiceCommand(.stop)
            case .setSpokenOutput(let enabled): response = performVoiceCommand(.setSpokenOutput(enabled))
            case .listPlaces:
                let names = places.memory.bookmarks.map(\.name)
                response = ["status": names.isEmpty ? "No places saved in this session." : names.joined(separator: ", ")]
            case .find(let target):
                let mode: FinderMode
                switch target {
                case .obstacles: mode = .none
                case .door: mode = .door
                case .exit: mode = .exit
                case .chair: mode = .chair
                case .person: mode = .person
                case .teammate: mode = .teammate
                case .barcode: mode = .barcode
                }
                response = performVoiceCommand(.find(mode))
            }
        } catch { response = ["error": String(describing: error)] }
        localCommandStatus = response["error"] as? String ?? response["status"] as? String ?? "Command completed."
        if voice.spokenOutputEnabled && !voice.isActive {
            // Local speech is finite; never send transcript or response to the network.
            localVoice.speak(String(localCommandStatus.prefix(160)), localeIdentifier: "en-US")
        }
        return response
    }
    func startLocalCommand() { localVoice.start(localeIdentifier: localCommandLanguage == .en ? "en-US" : "es-AR") }
    func resumeCloudAssistant() { localVoice.cancel(); voice.resumeAssistant() }
    func startLive(restoredMap: ARWorldMap? = nil, mapID: String? = nil) {
        guard !isStarting, mode != .live || restoredMap != nil else { return }
        stop(stopVoice: false, preservingMapRestore: restoredMap != nil);
        restoredMapSession = restoredMap != nil; isStarting=true; status="Requesting camera access"
        startGeneration += 1; let generation=startGeneration
        func begin() {
            guard self.startGeneration==generation else { return }
            self.isStarting=false
            self.mode = .live
            guard self.perception.start(epoch:generation, restoredMap: restoredMap, mapID: mapID) else { self.mode = .stopped; self.status="Live sensing requires a LiDAR device. Simulation is available."; return }
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
    func startMemorySimulation() {
        startSimulation()
        memorySimulation = true
        simulatedMemoryPosition = Vector3(0, 1.2, 0); simulatedMemoryYaw = 0; simulatedMemoryTracking = true
        tick()
    }
    func moveMemorySimulation(_ metres: Double) {
        guard mode == .simulation, memorySimulation, metres.isFinite, abs(metres) <= 5 else { return }
        let a = simulatedMemoryYaw * .pi / 180
        simulatedMemoryPosition = simulatedMemoryPosition + Vector3(-sin(a) * metres, 0, -cos(a) * metres)
        tick()
    }
    func turnMemorySimulation(_ degrees: Double) {
        guard mode == .simulation, memorySimulation, degrees.isFinite, abs(degrees) <= 360 else { return }
        simulatedMemoryYaw = (simulatedMemoryYaw + degrees).truncatingRemainder(dividingBy: 360); tick()
    }
    func toggleMemorySimulationTracking() {
        guard mode == .simulation, memorySimulation else { return }
        simulatedMemoryTracking.toggle(); tick()
    }
    func calibrate() { guard mode == .live else { return }; perception.calibrate(cameraHeight:cameraHeight) }
    /// A printed tag is in view: load what is remembered there and, the first time in this world, seed the route planner
    /// with the room's remembered structure, so the arrows can route to a remembered place before the camera has seen the room.
    func sawTag(_ sighting: TagSighting) {
        syncContextScope()
        roomMemory.sawTag(sighting)
        if let map = roomMemory.structureToSeed(for: sighting) { floorGridSeeder(map, sighting.frame, sighting.worldEpoch) }
        roomMemory.fetchSharedStructure(venueId: nil, tagId: sighting.tagId)
    }
    /// Starts a timed grid-walk trial and records it (depth, plus camera video if enabled).
    func startTrial() {
        guard mode == .live, trialStart == nil else { return }
        recordingDepth=true
        trialStart=Date(); trialEvents=[]
        markTrial("start")
    }
    /// Marks an event (bump, hesitated, arrived…) on the ARKit clock, so it lines up with the recording.
    func markTrial(_ kind: String) {
        guard trialStart != nil else { return }
        let event=TrialEvent(t:ProcessInfo.processInfo.systemUptime,kind:kind)
        trialEvents.append(event)
        perception.recorder.mark(kind,at:event.t)
    }
    func endTrial(_ outcome: String) {
        guard let start=trialStart else { return }
        markTrial(outcome)
        let bumps=trialEvents.filter { $0.kind == "bump" }.count
        lastTrialSummary=String(format:"Last: %@ in %.1f s, %d bump%@",outcome,Date().timeIntervalSince(start),bumps,bumps == 1 ? "" : "s")
        trialStart=nil
        recordingDepth=false
    }
    /// Leaving grid walk ends any running trial.
    func stopGridWalk() { if trialStart != nil { endTrial("ended") } }
    func stop(stopVoice: Bool = false, preservingMapRestore: Bool = false) {
        cancelLastSeen(); lastSeenNotice = nil; chalkQuery?.cancelAll()
        if !preservingMapRestore { savedMaps.cancel() }
        restoredMapSession=false
        chalkCommands.cancel(reason: "Stopped.")
        voice.invalidateSceneSpeech()
        if stopVoice { localVoice.cancel(); voice.disconnect() }
        isStarting=false; startGeneration += 1; timer?.invalidate(); timer=nil; frame=nil; calibrated=false
        cancelWhereIs()
        resetDirections()
        pointing.reset(); targetColumns=nil; pointingSpeech.stopSpeaking(at:.immediate)
        if trialStart != nil { endTrial("stopped") }
        recordingDepth=false
        pointingHighlight=nil; sectorFilter.reset()
        roomMemory.forgetTag()
        places.end(); memorySimulation=false
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
        cancelLastSeen(); syncContextScope()
        if chalkCommands.isBusy { chalkCommands.cancel(reason: "A new command replaced the request.") }
        voiceNotice = nil
        if savedMaps.isRestoring {
            switch command {
            case .rememberPlace, .recallPlace, .setReturnPoint, .returnToPoint:
                return ["error": "Wait for the saved room to match before using places."]
            default: break
            }
        }
        switch command {
        case .setContextReads(let enabled):
            guard let chalkQuery else { return ["error": "Cloud memory reading is not configured on this phone."] }
            chalkQuery.setEnabled(enabled); syncContextScope(); objectWillChange.send()
            return ["status": enabled ? "Cloud memory reads enabled. Signed-in history and approved shared rooms may be retrieved. No recording is sent." : "Cloud memory reads off. Shared guidance and pending history replies cleared."]
        case .lastSeen(let object):
            guard let chalkQuery, chalkQuery.isEnabled, let identity = chalkQuery.sessionIdentity else {
                return ["error": "Enable cloud memory reads and sign in before checking past finds."]
            }
            let request = lastSeenRequest, session = startGeneration
            ChalkMemory.lastSeen(chalkQuery, object: object) { [weak self] result in
                guard let self, self.lastSeenRequest == request, self.startGeneration == session,
                      self.chalkQuery?.sessionIdentity == identity, self.contextReadsEnabled,
                      !self.localVoice.hasPendingAttempt else { return }
                let line: String
                switch result {
                case .success(let value): line = value
                case .failure: line = "The find history is unavailable right now."
                }
                self.lastSeenNotice = line
                if self.voice.spokenOutputEnabled { self.say(line, sceneBound: true) }
            }
            return ["status": "Checking past finds.", "pending": true,
                    "note": "This is a past confirmed location, never a current detection. Wait for the result; do not invent a place."]
        case .setMemoryUploads(let enabled):
            guard let writer = uploader as? SupabaseWriter else { return ["error": "Cloud memory unavailable."] }
            writer.setUploadsEnabled(enabled); objectWillChange.send()
            return ["status": enabled ? "Future memories can upload for the selected venue when signed in. Earlier local records are not uploaded." : "Memory uploads off. Existing cloud records have not been deleted."]
        case .setSharedRoomMemory(let enabled):
            guard let writer = uploader as? SupabaseWriter else { return ["error": "Cloud memory unavailable."] }
            writer.setSharingEnabled(enabled); objectWillChange.send()
            return ["status": enabled ? "Future uploaded room records can be shared with other FEEL users." : "Future room uploads will be private. Earlier shared records have not been changed."]
        case .saveWorldMap:
            guard mode == .live, let frame, places.hasFreshContext else { return ["error": "Start the camera and wait for fresh tracking first."] }
            savedMaps.save(snapshot: places.memory.snapshot, worldEpoch: frame.worldEpoch)
            return ["status": savedMaps.message]
        case .restoreWorldMap:
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return ["error": "Open the live camera and grant access before restoring a room."] }
            savedMaps.restore(); return ["status": savedMaps.message]
        case .deleteWorldMap: savedMaps.delete(); return ["status": savedMaps.message]
        case .setTactileProfile(let profile): tactileProfile=profile; return ["status": "Tactile highlights set to " + profile.rawValue + "."]
        case .startMemorySimulation: startMemorySimulation(); return ["status": "Memory simulation started. No movement is sent to hardware."]
        case .moveMemorySimulation(let meters):
            guard memorySimulation, mode == .simulation, meters.isFinite, abs(meters) <= 5 else { return ["error": "Start memory simulation first and use a distance within 5 meters."] }
            moveMemorySimulation(meters); return ["status": "Synthetic position updated.", "simulation": true]
        case .turnMemorySimulation(let degrees):
            guard memorySimulation, mode == .simulation, degrees.isFinite, abs(degrees) <= 360 else { return ["error": "Start memory simulation first and use an angle within 360 degrees."] }
            turnMemorySimulation(degrees); return ["status": "Synthetic orientation updated.", "simulation": true]
        case .setMemorySimulationTracking(let enabled):
            guard memorySimulation, mode == .simulation else { return ["error": "Start memory simulation first."] }
            if simulatedMemoryTracking != enabled { toggleMemorySimulationTracking() }
            return ["status": enabled ? "Simulated tracking recovered." : "Simulated tracking lost.", "simulation": true]
        case .exportJourneys:
            do {
                _ = try journeyLog.export()
                return ["status": "Journeys exported to Files, On My iPhone, FEEL, journeys.json. Nothing was uploaded."]
            } catch { return ["error": "Could not export journeys on this iPhone."] }
        case .stop:
            stop()
            return ["status": "Camera stopped. Neutral command sent if connected. Assistant remains listening."]
        case .pauseAssistant:
            voice.pauseAssistant()
            return ["status": "Assistant paused. Microphone is off."]
        case .startCamera:
            startLive()
            return voiceSnapshot()
        case .rememberPlace(let name): return places.remember(name)
        case .listPlaces: return places.status
        case .recallPlace(let id):
            cancelWhereIs(); resetDirections(); pointing.reset(); pointingHighlight=nil
            return places.recall(id)
        case .renamePlace(let id, let name): return places.rename(id, to: name)
        case .deletePlace(let id): return places.delete(id)
        case .setReturnPoint: return places.setReturnPoint()
        case .returnToPoint:
            cancelWhereIs(); resetDirections(); pointing.reset(); pointingHighlight=nil
            return places.returnToPoint()
        case .stopPlaceGuidance: places.stop(); return ["status": "Place guidance stopped."]
        case .status: return voiceSnapshot()
        case .whereIs(let thing, let photo):
            places.stop()
            if let refusal = Self.whereIsRefusal(mode: mode, guidance: guidanceState) { return ["error": refusal] }
            if let remembered = beginWhereIs(thing, photo: photo, frame: frame) {
                return ["status": remembered, "remembered": true,
                        "note": "Say this as given: a place confirmed on an earlier visit, not a camera reading. The pins already point there; photo=true checks with the camera."]
            }
            return ["status": "Looking for the \(thing) with one camera photo. The result arrives as an observation in a few seconds; call get_status to check.",
                    "pending": true]
        case .leadMe(let label):
            places.stop()
            if let refusal = Self.whereIsRefusal(mode: mode, guidance: guidanceState) { return ["error": refusal] }
            guard let line = beginLeading(label, frame: frame) else {
                return ["error": "The \(label) is not remembered in this room, or the room's tag has not been seen yet. Say where is \(label) to look with the camera."]
            }
            return ["status": line, "remembered": true,
                    "note": "Say this as given: a place confirmed on an earlier visit. The pins point to the next point of the way, about every 6 meters; the route is a suggested direction, never a clear path."]
        case .foundIt:
            guard let target = heldTarget else { return ["error": "No Where-is target is held right now."] }
            let kept = roomMemory.confirm(target, confidence: 0.9) != nil
            let saved = recordFind(target, confidence: 0.9)
            clearHeldTarget(spokenLine: nil)
            return ["status": kept ? "Noted. The \(target.label) is remembered for this room." : "Noted. This room has no tag in view, so the place is not remembered.",
                    "remembered": kept,
                    "history": saved ? "The find is being saved to the user's history, for where did I last see it." : "Cloud history was not updated. Upload consent, sign-in and a selected venue are required."]
        case .describeAhead:
            if let refusal = Self.whereIsRefusal(mode: mode, guidance: guidanceState) { return ["error": refusal] }
            guard let configuration = chalkConfiguration else {
                return ["error": "The camera description needs the Chalk gateway setup, which is missing on this phone."]
            }
            describeRetry?.cancel(); describeRetry = nil; describeNotice = nil; startDescribeAhead(configuration)
            return ["status": "Taking a new photo now; the description is spoken within a few seconds. Say only Looking.", "pending": true]
        case .venueInfo(let question): return venueInfo.answer(question)
        case .find(let target):
            places.stop()
            cancelWhereIs()
            guard mode == .live else { return ["error": "Camera is not live. Ask the user whether to start it."] }
            guard target != .teammate || !restoredMapSession else { return ["error": "Restart the camera without the saved room before finding a teammate."] }
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
            return ["status": enabled ? "Spoken replies enabled." : "Spoken replies muted."]
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
            guard canFindTeammates else { return ["error": "Start a live camera session without a saved room before finding a teammate."] }
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
            guard canFindTeammates, peer.running, let selected = voiceTeammates[id], peer.peers.contains(selected) else {
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
        case .setDirectionArrows(let enabled):
            arrowsEnabled = enabled
            return ["status": enabled ? "Direction arrows enabled." : "Direction arrows disabled. Camera sensing continues."]
        case .startDirections:
            return startRequestedDirections()
        case .stopDirections:
            resetDirections(); pointingHighlight = nil
            tick()
            return ["status": "Direction arrows stopped. Camera sensing continues."]
        case .startRecording(let includeVideo):
            guard mode == .live else { return ["error": "Start the live camera before recording."] }
            guard !recordingDepth else { return ["status": "Recording is already running. Stop it before changing video inclusion."] }
            recordingVideo = includeVideo
            recordingDepth = true
            return ["status": "Recording startup requested. Check recording status before confirming it started.", "pending": true]
        case .stopRecording:
            recordingDepth = false
            return ["status": "Recording stop requested. Camera sensing remains active."]
        case .setRecordingVideo(let enabled):
            guard !recordingDepth else { return ["error": "Stop recording before changing video inclusion."] }
            recordingVideo = enabled
            return ["status": enabled ? "The next recording will include camera video." : "The next recording will contain depth without camera video."]
        case .simulateDirectionSign:
            guard mode == .simulation else { return ["error": "Start simulation before simulating a V sign."] }
            guard arrowsEnabled else { return ["error": "Enable direction arrows first."] }
            simulateSign(); tick()
            return ["status": "Simulated direction sign requested. Synthetic scene only.", "simulation": true]
        case .chooseTarget(let option):
            let actions=request.chose(option-1,now:ProcessInfo.processInfo.systemUptime)
            guard !actions.isEmpty else { return ["error": "No choice is pending, or that option doesn't exist."] }
            perform(actions)
            return ["status": "Choice received. The app confirms with a sound. Say nothing more."]
        }
    }

    // MARK: Where-is

    func saveChalkConfiguration(_ configuration: ChalkConfiguration) throws {
        guard configuration.isValid else { throw KeychainStoreError.invalid }
        try chalkStore.save(configuration)
        cancelWhereIs()
        chalkConfiguration = configuration; whereIsService = nil   // a lookup in flight must not answer through the old settings
    }
    func forgetChalkConfiguration() {
        cancelWhereIs()
        chalkStore.clear(); chalkConfiguration = nil; whereIsService = nil
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
    /// Returns the remembered-place line when room memory answered (the pins already point there and no photo is
    /// taken); nil when the camera is looking instead, because a photo was asked for or memory had nothing.
    @discardableResult
    func beginWhereIs(_ thing: String, photo: Bool = false, frame: PerceptionFrame? = nil) -> String? {
        places.stop()
        cancelWhereIs()
        resetDirections()
        pointing.reset(); pointingHighlight = nil
        if finder != .none { finder = .none }
        if !photo, let line = recallWhereIs(thing, frame: frame) { return line }
        startWhereIs(thing)
        return nil
    }
    /// Memory answers only with a live frame, a tag frame from that same world and a remembered place for the label.
    /// The line goes back through the tool result for the assistant to say, and stays in `whereIsNotice` for get_status.
    func recallWhereIs(_ thing: String, frame: PerceptionFrame?, phrase: (String, Double, Double) -> String = VoicePhrasing.remembered) -> String? {
        let now = ProcessInfo.processInfo.systemUptime
        guard let target = roomMemory.recall(thing, worldEpoch: frame?.worldEpoch, now: now), let frame,
              let relative = target.relative(pose: frame.pose) else { return nil }
        hold(target)
        lastDirectionSpokenAt = now   // the line says where it was; out-of-field direction repeats start five seconds later
        let line = phrase(target.label, relative.bearingDegrees, relative.horizontalDistance)
        whereIsNotice = line
        return line
    }
    /// lead_me: a remembered place becomes the held target and its route is followed one progress point at a time
    /// (followWaypoints). Nothing changes when the label is not remembered at a tag seen in this world. The line is
    /// for the assistant to say as given.
    @discardableResult
    func beginLeading(_ thing: String, frame: PerceptionFrame?) -> String? {
        guard let frame, roomMemory.remembers(thing, worldEpoch: frame.worldEpoch) else { return nil }
        cancelWhereIs()
        resetDirections()
        pointing.reset(); pointingHighlight = nil
        if finder != .none { finder = .none }
        return recallWhereIs(thing, frame: frame, phrase: VoicePhrasing.leading)
    }
    /// The one way a target starts driving the pins, whether it came from a photo or from memory. With the room's tag
    /// seen in the target's world the walk is recorded as a journey.
    private func hold(_ target: HeldTarget) {
        heldTarget = target; voiceSawTarget = false; lastDirectionSpokenAt = -.infinity
        startHeldRoute(target)
        let now = ProcessInfo.processInfo.systemUptime
        journeyLog.end(arrived: false, pose: frame?.pose, now: now)   // a new target is a new walk
        if let sighting = roomMemory.sighting, sighting.worldEpoch == target.worldEpoch {
            journeyLog.begin(targetLabel: target.label, target: target.position, sighting: sighting, startUptime: now)
        }
        journeyLog.targetChanged(now: now)
    }
    private var describeTask: URLSessionTask?
    /// The last camera description, for get_status, and the retry that speaks it once the assistant is free.
    @Published private(set) var describeNotice: String?
    private var describeRetry: DispatchWorkItem?
    private func deliverDescription(_ text: String, attempts: Int = 24) {
        describeRetry?.cancel()
        describeNotice = text
        guard !voice.announce(text, automatic: false), attempts > 0 else { return }
        let retry = DispatchWorkItem { [weak self] in self?.deliverDescription(text, attempts: attempts - 1) }
        describeRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: retry)
    }
    /// One photo through the gateway, spoken as one sentence. A stopped camera or a newer ask drops the answer.
    private func startDescribeAhead(_ configuration: ChalkConfiguration) {
        describeTask?.cancel(); describeTask = nil
        let generation = startGeneration
        let gateway = gatewayFactory(configuration)
        snapshotProvider { [weak self] snapshot in
            guard let self, self.startGeneration == generation else { return }
            guard let snapshot, let body = try? VoicePhrasing.describeBody(model: configuration.model, jpegBase64: snapshot.jpegBase64) else {
                self.deliverDescription("I couldn't take a photo just now."); return
            }
            self.describeTask = gateway.complete(body: body, timeout: WhereIs.deadline) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.startGeneration == generation else { return }
                    self.describeTask = nil
                    switch result {
                    case .success(let text):
                        self.deliverDescription(VoicePhrasing.oneSentence(text) ?? "I couldn't make out what's ahead.")
                    case .failure:
                        self.deliverDescription("I couldn't reach the camera service just now.")
                    }
                }
            }
        }
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
            hold(target)
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
    private func cancelWhereIs() {
        whereIsRequest += 1
        whereIsService?.cancel()
        // A target change, a stop or lost tracking ends the walk unarrived; an arrival ended it already.
        journeyLog.end(arrived: false, pose: frame?.pose, now: ProcessInfo.processInfo.systemUptime)
        follower = nil; followFrame = nil; if waypoint != nil { waypoint = nil }
        heldTarget = nil; whereIsNotice = nil; unspokenLine = nil
        voiceSawTarget = false; voiceTargetLostAt = nil
        voiceTargetAvailable = false; voiceTargetPhrase = nil
        clearPointingRoute()
        voice.invalidateSceneSpeech()
    }
    /// What a held target does on one frame. Arrival also feeds room memory before the target is released: the
    /// user walked to the place the pins pointed at, which is weaker evidence than their own "found it".
    func handleHeldEvent(_ event: HeldTargetGuidance.Event, target: HeldTarget, now: TimeInterval, pose: CameraPose? = nil) {
        switch event {
        case .lostTracking: clearHeldTarget(spokenLine: "Lost tracking. Say it again.")
        case .reached:
            roomMemory.confirm(target, confidence: 0.7)
            journeyLog.end(arrived: true, pose: pose ?? frame?.pose, now: now)
            clearHeldTarget(spokenLine: "You're at the \(target.label).")
        case .speak(let direction): if voice.announce(direction, sceneBound: true) { lastDirectionSpokenAt = now; whereIsNotice = direction }
        case .keep: break
        }
    }
    func clearHeldTarget(spokenLine: String?) {
        let wasHolding = heldTarget != nil
        cancelWhereIs()
        if wasHolding, let spokenLine { say(spokenLine) }
    }

    // MARK: Journey loop

    /// Leads the held target's route one progress point at a time. The first route the planner publishes for the
    /// target is split once (ProgressPoints, every 6 m) in the tag's levelled frame, or on the world floor when no
    /// tag was seen in this world; the next point is the pins' target until the user is within a metre of it, "Next
    /// point." marks each one, and the last point is the target. The arrows keep following the live route to the
    /// target itself, and the pins keep showing live depth. A target without a route keeps today's straight bearing.
    func followWaypoints(frame: PerceptionFrame, now: TimeInterval) {
        guard let heldTarget, heldTarget.worldEpoch == frame.worldEpoch else { return }
        if follower == nil {
            guard heldRoute, let path = frame.routePath, path.count >= 2 else { return }
            let floor = roomMemory.sighting.flatMap { $0.worldEpoch == frame.worldEpoch ? $0.frame.levelled : nil } ?? .worldFloor
            guard var started = WaypointFollower(points: ProgressPoints.split(polyline: path.map { FloorPoint(world: $0, in: floor) })) else { return }
            _ = started.update(position: FloorPoint(pose: frame.pose, in: floor))
            follower = started; followFrame = floor
        } else if let floor = followFrame, case .advanced = follower!.update(position: FloorPoint(pose: frame.pose, in: floor)) {
            say("Next point.")
        }
        guard let follower, let floor = followFrame else { return }
        if follower.arrived { arriveByWaypoints(pose: frame.pose, now: now); return }
        let next = follower.target(frame: floor, label: heldTarget.label, worldEpoch: frame.worldEpoch, now: now)
        if waypoint?.position != next?.position { waypoint = next; journeyLog.targetChanged(now: now) }
    }
    /// The last progress point is the target: arrival feeds room memory and ends the journey, like reaching the target itself.
    private func arriveByWaypoints(pose: CameraPose, now: TimeInterval) {
        guard let target = heldTarget else { return }
        roomMemory.confirm(target, confidence: 0.7)
        journeyLog.end(arrived: true, pose: pose, now: now)
        clearHeldTarget(spokenLine: "You're there, at the \(target.label).")
    }
    /// Feeds the journey being recorded: the live pose, the blocked cells the planner saw, and the packet that first showed a new target.
    func recordJourney(frame: PerceptionFrame, output: EncoderOutput, now: TimeInterval) {
        guard journeyLog.isRecording else { return }
        if output.state == .live { journeyLog.record(pose: frame.pose, now: now) }
        if let cells = frame.blockedCells { journeyLog.noteBlocked(worldCentres: cells, cellSize: frame.cellSize) }
        if output.state == .live, output.targetColumns != nil || cuePlayer.isAnimating { journeyLog.cueShown(now: now) }
    }
    /// "Found it" also goes to the user's find history (the confirmed_finds table, Chalk's last_seen): placed by venue
    /// and, when the room's tag frame is known for this world, by the distance from the tag. False when nothing can
    /// leave the phone (no Supabase settings, or not signed in).
    @discardableResult
    private func recordFind(_ target: HeldTarget, confidence: Double) -> Bool {
        guard let uploader, uploader.isReady, let venueName = venueInfo.pack?.venueName else { return false }
        let tag = roomMemory.sighting.flatMap { sighting -> (id: String, distance: Double)? in
            guard sighting.worldEpoch == target.worldEpoch else { return nil }
            let p = sighting.frame.tagPoint(world: target.position)
            return (sighting.tagId, (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot())
        }
        uploader.upload(find: target.label, place: Self.findPlace(venue: venueName, tag: tag),
                        confidence: confidence, foundAt: Date())
        return true
    }
    /// Where a find is filed, as Chalk reads it back ("last confirmed at the …"): the venue, and how far from which tag.
    static func findPlace(venue: String, tag: (id: String, distance: Double)?) -> String {
        guard let tag, tag.distance.isFinite else { return venue }
        return "\(venue), about \(Int(tag.distance.rounded())) m from tag \(tag.id)"
    }

    /// get_status.room_memory, with the journey being recorded, the progress point in use, and the uploads.
    private var roomMemoryStatus: [String: Any] {
        var status = roomMemory.status
        var journey = journeyLog.status
        journey["next_point"] = follower.map { $0.arrived ? "arrived" : String($0.index) } ?? "none"
        journey["points"] = follower?.points.count ?? 0
        status["journey"] = journey
        status["uploads"] = uploader?.statusReport ?? ["configured": false]
        status["reads_enabled"] = contextReadsEnabled
        status["last_seen"] = lastSeenNotice ?? "none"
        return status
    }
    private func cancelLastSeen() {
        lastSeenRequest += 1
        if lastSeenNotice != nil { voice.invalidateSceneSpeech() }
        if let lastSeenNotice, unspokenLine?.line == lastSeenNotice { unspokenLine = nil }
    }
    /// Run before guidance and callbacks. Account/venue changes revoke previously selected shared targets as well.
    private func syncContextScope() {
        let identity = chalkQuery?.sessionIdentity, venue = venueInfo.pack?.venueId
        guard identity != contextIdentity || venue != contextVenue else { return }
        contextIdentity = identity; contextVenue = venue
        cancelLastSeen(); lastSeenNotice = nil
        roomMemory.invalidateSharedMemory()
        clearHeldTarget(spokenLine: nil); resetDirections(); clearPointingRoute()
        voice.invalidateSceneSpeech(); objectWillChange.send()
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
                "selected_target": finder.rawValue, "direction_status": directionReadout, "direction_arrows": arrowsEnabled ? (guiding ? "guiding" : "ready for a voice request or V sign") : "off", "puck_connected": puck.isConnected,
                "where_is_available": whereIsAvailable, "held_target": heldTarget?.label ?? "none", "where_is": whereIsNotice ?? "none",
                "connection": puck.status, "simulation": mode == .simulation,
                "direction_arrows_enabled": arrowsEnabled, "directions_active": guiding,
                "directions_pending": request.isBusy || pointingRouteSetAt != nil || pendingSign,
                "recording_requested": recordingDepth, "recording_includes_video": recordingVideo,
                "recording_status": recordingStatus ?? "Recording is off.",
                "session_places": places.status, "spoken_replies": voice.spokenOutputEnabled, "useful_updates": voice.proactiveEnabled,
                "notice": "Neutral pins do not mean a clear path. No safe-route claim is available.",
                "open_side": openSide?.spoken ?? "Nothing within 1.6 meters ahead, or unknown.",
                "room_memory": roomMemoryStatus, "room_structure": roomMemory.structureStatus]
    }

    private func updateVoiceAwareness(targetAvailable: Bool, target: TargetObservation? = nil,
                                      distances: [Double?] = [], openSide: OpenSide? = nil, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        voiceTargetAvailable = targetAvailable
        guard voice.isActive else {
            voiceSawTarget = false; voiceLastGuidance = nil; voiceHadConnection = puck.isConnected
            proactiveVoice.reset(); voiceNotice = nil; voiceStateNotice = nil
            return
        }
        if !voice.hasPendingAnnouncementDelivery { voiceStateNotice = nil }
        if let state = voiceStateNotice {
            let supported: Bool
            switch state {
            case .guidance(let expected): supported = mode == .live && guidanceState == expected
            case .targetLost: supported = mode == .live && guidanceState == .live && !targetAvailable && heldTarget == nil
            case .puckDisconnected: supported = !puck.isConnected
            }
            if !supported { voice.invalidateSceneSpeech(); voiceStateNotice = nil }
        }
        if voiceStateNotice == nil && (guidanceState != .live || (voiceNotice.map {
            !$0.isSupported(target: target, finder: finder, distances: distances, now: now)
        } ?? !targetAvailable)) {
            voice.invalidateSceneSpeech(); voiceNotice = nil
        }
        if voiceHadConnection && !puck.isConnected {
            _ = announceState("The puck disconnected. Tactile feedback is unavailable.", state: .puckDisconnected) { [weak self] in
                self?.voiceHadConnection = false
            }
            return
        }
        voiceHadConnection = puck.isConnected
        guard mode == .live else {
            voiceSawTarget = false; voiceLastGuidance = nil; proactiveVoice.reset(); voiceNotice = nil; voiceStateNotice = nil
            return
        }
        if guidanceState != .live {
            voiceSawTarget = false; voiceTargetLostAt = nil; proactiveVoice.reset()
            if voiceLastGuidance != guidanceState {
                let message: String
                switch guidanceState {
                case .uncalibrated: message = automaticFloorCalibrationSupported
                    ? "Looking for the floor. Move slowly with some floor in view. You can also use measured height in floor setup."
                    : "Automatic floor calibration is unavailable. Enter the measured camera height in floor setup."
                case .trackingLost: message = "Tracking lost. Sensing is unavailable."
                default: message = "Sensing is unavailable. Pins are neutral."
                }
                let expected = guidanceState
                _ = announceState(message, state: .guidance(expected)) { [weak self] in self?.voiceLastGuidance = expected }
            }
            return
        }
        // A successful recovery is worth hearing without asking for status again.
        if let previous = voiceLastGuidance, previous != .live {
            _ = announceState("Sensing is back.", state: .guidance(.live)) { [weak self] in self?.voiceLastGuidance = .live }
            return
        }
        voiceLastGuidance = .live
        let notice = proactiveVoice.propose(target: target, finder: finder, distances: distances, openSide: openSide, now: now)
        if let notice, notice.kind == .obstacle, announceObservation(notice) { return }
        if !targetAvailable {
            if HeldTargetGuidance.announcesTargetLost(sawTarget: voiceSawTarget, holding: heldTarget != nil) {
                if voiceTargetLostAt == nil { voiceTargetLostAt = now }
                if now - (voiceTargetLostAt ?? now) >= 0.6 {
                    _ = announceState("I no longer see your target.", state: .targetLost) { [weak self] in self?.voiceSawTarget = false }
                }
            }
        } else { voiceTargetLostAt = nil }
        if let notice { _ = announceObservation(notice) }
    }

    private func announceObservation(_ notice: ProactiveVoicePolicy.Notice) -> Bool {
        let accepted = voice.announce(notice.text, sceneBound: true) { [weak self] in
            guard let self, self.voiceNotice?.key == notice.key else { return }
            self.proactiveVoice.acknowledge(notice, now: ProcessInfo.processInfo.systemUptime)
            if notice.kind == .target { self.voiceSawTarget = true }
        }
        if accepted { voiceNotice = notice }
        return accepted
    }

    private func announceState(_ text: String, state: VoiceStateNotice, onDelivered: @escaping () -> Void) -> Bool {
        let accepted = voice.announce(text, sceneBound: true) { [weak self] in
            guard let self, self.voiceStateNotice == state else { return }
            self.voiceStateNotice = nil
            onDelivered()
        }
        if accepted { voiceStateNotice = state }
        return accepted
    }

    private func handlePointing(_ observation:PointingObservation,epoch:Int) {
        guard mode == .live,epoch==startGeneration,!savedMaps.isRestoring,!localVoice.hasPendingAttempt else { return }
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
        case .barcode: return "Barcode"
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
        guard output.state == .live, !cuePlayer.isAnimating, PuckLayout.activeColumns.contains(h.column),
              !bands.indices.contains(where: { $0 != h.column && bands[$0] == 1 }) else { return output }
        if bands[h.column] == 0 { bands[h.column]=h.band }
        guard bands[h.column]>0,let packet=try? FeelPacket(sequence:output.packet.sequence,bands:bands,highlight:UInt8(h.column)) else { return output }
        return EncoderOutput(packet:packet,state:output.state,targetColumns:h.column...h.column)
    }

    /// Hand a two-finger goal to the route planner; arrows start once a route to it exists.
    private func startPointingRoute(_ route:PointingRoute) {
        places.stop()
        cancelWhereIs()
        guard arrowsEnabled else { speakLocal("Direction arrows are turned off in settings."); return }
        perception.setRouteGoal(route.goal,label:route.label)
        pointingRouteSetAt=ProcessInfo.processInfo.systemUptime; pointingRouteActive=true
    }

    private func clearPointingRoute() {
        guard pointingRouteActive else { return }
        perception.setRouteGoal(nil); pointingRouteSetAt=nil; pointingRouteActive=false; heldRoute=false
    }

    /// A placed Where-is target becomes the route goal, so the arrows guide to it the way they
    /// guide to a two-finger route: one arrow when the planner has a route, then on noticeable changes.
    private func startHeldRoute(_ target: HeldTarget) {
        clearPointingRoute()
        guard arrowsEnabled else { return }
        perception.setRouteGoal(target.position, label: target.label)
        pointingRouteSetAt=ProcessInfo.processInfo.systemUptime; pointingRouteActive=true; heldRoute=true
    }
    var routeGoalActive: Bool { pointingRouteActive }

    /// Starts the arrow guide when the planner has a route for the pointing goal (or reports failure
    /// if none comes within 2 s).
    private func tickPointingRoute(now:TimeInterval,hint:RouteHint?) {
        guard let setAt=pointingRouteSetAt else { return }
        if let hint,hint.timestamp>setAt { pendingSign=true; pointingRouteSetAt=nil }
        else if now-setAt>2, !heldRoute { pendingSign=true; pointingRouteSetAt=nil }
    }

    private func speakLocal(_ text:String) {
        guard voice.spokenOutputEnabled, !localVoice.hasPendingAttempt else { return }
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

    static func directionsRefusal(mode: RunMode, guidance: GuidanceState, arrowsEnabled: Bool, hasTarget: Bool) -> String? {
        guard mode == .live else { return "Start the live camera before requesting directions." }
        guard guidance == .live else { return "Fresh tracking and floor calibration are required for direction arrows." }
        guard arrowsEnabled else { return "Enable direction arrows first." }
        guard hasTarget else { return "Choose a target first, then ask for direction arrows." }
        return nil
    }

    private func startRequestedDirections() -> [String: Any] {
        places.stop()
        tick()
        let selected = Self.word(finder)
        if let refusal = Self.directionsRefusal(mode: mode, guidance: guidanceState, arrowsEnabled: arrowsEnabled,
                                              hasTarget: heldTarget != nil || selected != nil) { return ["error": refusal] }
        resetDirections(); pointing.reset(); pointingHighlight = nil
        if let heldTarget {
            startHeldRoute(heldTarget)
        } else if let selected {
            cancelWhereIs()
            let now = ProcessInfo.processInfo.systemUptime
            // Reuse the V-sign request state machine without opening its keyword microphone.
            _ = request.handBegan(now: now)
            _ = request.heardWord(selected, now: now, selected: selected)
            perform(request.signFired(now: now, selected: selected))
        }
        return ["status": "Direction arrows requested. Waiting for a current target and route.", "pending": true]
    }

    /// Simulation stand-in for the hand sign: no word, guide to the synthetic target.
    func simulateSign() { guard mode == .simulation else { return }; pendingSign=true }

    /// Ends guidance (finder change); a request in flight keeps going.
    /// One sweep toward the side with more room while something is within 1.4 m ahead and no route
    /// arrow is playing. The cue player still holds it back while any pin is within 0.9 m.
    private func playOpenSideCue(_ open: OpenSide?,now: TimeInterval) {
        guard arrowsEnabled, !guiding, let open, open.side != .ahead, open.aheadRange <= 1.4, !cuePlayer.isAnimating else { return }
        if let last=lastOpenSideCue, last.column == open.column, now-last.at < 6 { return }
        cuePlayer.play(.bear(column:open.column),now:now); lastOpenSideCue=(open.column,now)
    }

    private func resetGuidance() {
        guide.reset(); cuePlayer.reset(); pendingSign=false; targetLocked=false; askedChoices=[]
        openSideFinder.reset(); lastOpenSideCue=nil; if openSide != nil { openSide=nil }; pathWave.reset()
        if pointingRouteActive { perception.setRouteGoal(nil) }; pointingRouteSetAt=nil; pointingRouteActive=false; heldRoute=false
        if guidanceCue != nil { guidanceCue=nil }
        if guiding { guiding=false }
    }

    private func resetDirections() {
        resetGuidance(); signTrigger.reset(); request.reset(); listener.stop()
    }

    private static func word(_ finder:FinderMode)->TargetWord? {
        switch finder {
        case .none, .barcode: return nil
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
        guard mode == .live,epoch==startGeneration,!savedMaps.isRestoring,arrowsEnabled,!pointing.isActive,!localVoice.hasPendingAttempt else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let wasHolding=signTrigger.holding
        let fired=signTrigger.update(observation)
        // Start listening as soon as the sign appears, so "[V] exit" said together is heard.
        if !wasHolding && signTrigger.holding { places.stop(); cancelWhereIs(); perform(request.handBegan(now:now)) }
        if fired {
            request.listenSeconds=listener.isAvailable ? 2.5 : 0
            perform(request.signFired(now:now,selected:Self.word(finder)))
        }
        let range=observation.distance.map { String(format:"%.2f m",$0) } ?? "no hand"
        directionReadout="Arrows: "+(observation.counts ? "V sign \(range)" : observation.vSign ? "V sign too far (\(range))" : observation.distance == nil ? "no hand" : "hand, no V (\(range))")+(listener.isListening ? " · listening" : "")+(guiding ? " · guiding" : "")
    }

    /// "[V] plant": not one of the five target words, so it is a Where-is question. The request is dropped
    /// (otherwise it would re-route to the previously selected target) and the lookup runs as if spoken
    /// to the assistant: a remembered place answers at once, else one photo through the gateway.
    private func heardPhrase(_ thing:String) {
        places.stop()
        request.reset(); pendingSign=false
        guard Self.whereIsRefusal(mode:mode,guidance:guidanceState) == nil else { chime.play(.failure); return }
        chime.play(.success)
        speakLocal("Looking for the \(thing).")
        if let line=beginWhereIs(thing,photo:false,frame:frame) { speakLocal(line) }
    }

    /// The thing to look for in a spoken phrase: leading filler dropped, at most three words, letters only.
    static func whereIsThing(from phrase:String) -> String? {
        let filler: Set<String>=["find","where","is","where's","wheres","the","a","an","go","to","take","me","lead","my","please","um","uh","there","it","locate","show","look","for","i","want","need"]
        var words=phrase.lowercased().split { !$0.isLetter }.map(String.init)
        while let first=words.first, filler.contains(first) { words.removeFirst() }
        words=Array(words.prefix(3))
        guard !words.isEmpty, words.contains(where: { $0.count>=3 }), TargetWord.match(phrase) == nil else { return nil }
        return words.joined(separator:" ")
    }

    private func heard(_ word:TargetWord) {
        guard mode == .live else { return }
        perform(request.heardWord(word,now:ProcessInfo.processInfo.systemUptime,selected:Self.word(finder)))
    }

    private func perform(_ actions:[RequestAction]) {
        var diverted=false   // the spoken word was not a target word: it became a Where-is lookup instead
        for action in actions {
            if diverted { continue }
            switch action {
            case .startListening:
                guard !localVoice.hasPendingAttempt else { request.reset(); continue }
                listener.start()
            case .stopListening:
                let phrase=listener.takeUnmatchedTranscript()
                listener.stop()
                if let phrase, let thing=Self.whereIsThing(from:phrase) { diverted=true; heardPhrase(thing) }
            case .sound(let sound):
                if sound == .listening && !listener.isListening { continue }
                chime.play(sound)
            case .select(let word):
                let mode=Self.finder(word)
                if mode == .chair && !detectorAvailable { request.reset(); chime.play(.failure); return }
                if finder != mode { finder=mode }
            case .ask(let choices):
                guard voice.spokenOutputEnabled else {
                    request.reset(); askedChoices=[]; listener.stop()
                    directionReadout="Multiple targets. Say speak again, then request directions."
                    chime.play(.failure)
                    continue
                }
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

    /// The passive path wave rides on the obstacle pins while the wearer turns toward an off-centre
    /// route (a target in view or remembered, or a pointing goal). A playing arrow comes first.
    private func withPathWave(_ output:EncoderOutput,hint:RouteHint?,now:TimeInterval)->EncoderOutput {
        guard arrowsEnabled, !cuePlayer.isAnimating else { return output }
        return pathWave.apply(to:output,hint:hint,now:now)
    }
    /// Facing direction on the floor, degrees, right-positive, for turn detection.
    private static func yawDegrees(_ pose:CameraPose)->Double { atan2(-pose.back.x,pose.back.z)*180 / .pi }

    /// Advances a V-sign request with what perception currently sees.
    private func tickRequest(now:TimeInterval,candidates:[VisibleCandidate],hint:RouteHint?) {
        guard request.isBusy else { return }
        lastChoices=candidates
        perform(request.tick(now:now,selected:Self.word(finder),
                             choices:candidates.map { TargetChoice(bearingDegrees:$0.observation.bearingDegrees,distance:$0.observation.distance) },
                             hintTime:hint?.timestamp,lockedTarget:targetLocked,agentAvailable:voice.phase == .listening))
    }

    private func featureNotice(_ line: String) {
        guard voice.spokenOutputEnabled else { return }
        if voice.isActive { say(line) }
        else if !localVoice.hasPendingAttempt { localVoice.speak(line, localeIdentifier: "en-US") }
    }

    /// A target that turned out of view still has a route for a few seconds; say where it went.
    private func remembered(_ hint:RouteHint?)->String? {
        guard let hint,hint.status == .route else { return nil }
        return String(format:"%@ out of view · route %.0f°",hint.label,hint.bearingDegrees)+(pathWave.isActive ? " · wave" : "")
    }

    private func tick() {
        syncContextScope()
        let now=ProcessInfo.processInfo.systemUptime; sequence &+= 1
        retryUnspokenLine(now: now)
        savedMaps.checkDeadline()
        if savedMaps.isRestoring {
            packet = .neutral(sequence: sequence); guidanceState = .trackingLost; targetColumns=nil
            targetDescription = "Matching saved room. Guidance paused."
            if mode == .live { puck.send(packet) }
            return
        }
        if mode == .simulation, memorySimulation {
            let a = simulatedMemoryYaw * .pi / 180
            let pose = CameraPose(position: simulatedMemoryPosition, right: Vector3(cos(a),0,-sin(a)), up: Vector3(0,1,0), back: Vector3(sin(a),0,cos(a)))
            places.observe(pose: pose, worldEpoch: -1, timestamp: now, tracking: simulatedMemoryTracking)
            let distances = [Double?](repeating: nil, count: 7)
            let output = places.encode(sequence: sequence, distances: distances, calibrated: true, at: now)
                ?? TactileEncoder.encode(sequence: sequence, now: now, frameTimestamp: now, tracking: simulatedMemoryTracking, distances: distances, target: nil)
            packet = adaptiveTactile.apply(packet: tapRhythm.apply(to: output).packet, profile: tactileProfile, session: places.memory.session ?? "simulation", now: now)
            guidanceState = output.state == .live ? .simulation : output.state
            calibrated = true; targetColumns=output.targetColumns
            targetDescription = "SIMULATION: " + (places.guidance?.state.rawValue ?? "Remember a place, move, then recall.")
            return
        }
        if mode == .simulation {
            let phase=(now-simulatedAt).truncatingRemainder(dividingBy:12)
            let tracking=phase<8 || phase>=10
            let target=TargetObservation(bearingDegrees:sin(phase/2)*40,distance:1.3,timestamp:now,label:"SIMULATED target")
            let near=phase>=4 && phase<6
            let encoded=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:now,tracking:tracking,distances:[nil,near ? 0.7 : nil,1.1,2,3.5,nil,nil],target:target)
            // Simulated route: straight to the synthetic target, no floor map.
            let hint=tracking ? RouteHint(timestamp:now,status:.route,bearingDegrees:target.bearingDegrees,targetDistance:target.distance,routeLength:target.distance,label:"simulated target") : nil
            let output=tapRhythm.apply(to:withDirections(EncoderOutput(packet:encoded.packet,state:encoded.state == .live ? .simulation : encoded.state),hint:hint,now:now),animating:cuePlayer.isAnimating)
            packet=output.packet; guidanceState=output.state
            targetDescription=tracking ? "SIMULATED target sweeping left to right" : "SIMULATED tracking loss. All pins neutral"
            return
        }
        guard mode == .live,let frame else {
            packet = .neutral(sequence:sequence); guidanceState = mode == .live ? .staleDepth : .stopped
            cuePlayer.reset(); tapRhythm.reset(); targetColumns=nil; openSideFinder.reset(); if openSide != nil { openSide=nil }; sectorFilter.reset(); pathWave.reset()
            tickRequest(now:now,candidates:[],hint:nil)
            _=withDirections(.init(packet:packet,state:guidanceState),hint:nil,now:now)
            if mode == .live { puck.send(packet) }; updateVoiceAwareness(targetAvailable: false); return
        }
        if let memoryOutput = places.encode(sequence: sequence, distances: frame.distances, calibrated: frame.floorY != nil, at: now) {
            packet=adaptiveTactile.apply(packet: tapRhythm.apply(to: memoryOutput).packet, profile: tactileProfile, session: places.memory.session ?? "", now: now); guidanceState=memoryOutput.state; targetColumns=memoryOutput.targetColumns
            targetDescription=places.guidance.map { "Remembered place: \($0.state.rawValue)" } ?? "Place tracking unavailable"
            voiceTargetPhrase=nil
            if places.guidance?.state == .arrived { featureNotice("You reached the remembered place.") }
            updateVoiceAwareness(targetAvailable: false, distances: memoryOutput.state == .live ? frame.distances : [], now: now)
            puck.send(packet)
            return
        }
        // A held Where-is target owns the pins: finder and teammate targets never shadow it, even while it is out of the
        // field. On a split route the pins point to the next progress point of the way instead.
        let held=(waypoint ?? heldTarget)?.observation(pose:frame.pose,now:now,worldEpoch:frame.worldEpoch)
        let target=HeldTargetGuidance.pins(held:held,holding:heldTarget != nil,finder:finder == .teammate ? peer.currentTarget(pose:frame.pose,now:now) : frame.target)
        // Sector ranges are steadied once per depth frame so the pins do not flutter; replay runs the same step.
        let distances: [Double?]
        if frame.tracking { distances=sectorFilter.update(frame.distances,frameTimestamp:frame.timestamp) } else { sectorFilter.reset(); distances=frame.distances }
        pathWave.observe(yawDegrees:Self.yawDegrees(frame.pose),at:frame.timestamp)
        let encoded=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:frame.timestamp,tracking:frame.tracking,distances:distances,target:target,floorCalibrated:frame.floorY != nil)
        pointing.record(CachedScene(timestamp:frame.timestamp,pose:frame.pose,tracking:encoded.state == .live,distances:distances,target:target?.valid(at:frame.timestamp) == true ? target : nil))
        speakPointing(pointing.tick(now:now))
        // While pointing, the pins hold the scene from before the hand came up; arrows pause.
        let frozen=encoded.state == .live ? pointing.frozenOutput(sequence:sequence) : nil
        if frozen != nil { cuePlayer.reset(); pendingSign=false } else { tickRequest(now:now,candidates:frame.candidates,hint:frame.routeHint); tickPointingRoute(now:now,hint:frame.routeHint) }
        if encoded.state != .live || frozen != nil { openSideFinder.reset() }
        let open=encoded.state == .live && frozen == nil ? openSideFinder.update(distances:distances,now:now) : nil
        if openSide != open { openSide=open }
        playOpenSideCue(open,now:now)
        let composed=frozen.map { EncoderOutput(packet:$0.packet,state:encoded.state,targetColumns:$0.targetColumns) } ?? withPointingHighlight(withPathWave(withDirections(encoded,hint:frame.routeHint,now:now),hint:frame.routeHint,now:now),now:now)
        // The path wave is motion already, like an arrow; presence taps wait until it ends.
        let output=tapRhythm.apply(to:composed,animating:cuePlayer.isAnimating || pathWave.isActive)
        packet=adaptiveTactile.apply(packet: output.packet, profile: tactileProfile, session: String(frame.worldEpoch), now: now); guidanceState=output.state; targetColumns=output.targetColumns; puck.send(packet)
        recordJourney(frame:frame,output:output,now:now)
        if pointing.isActive {
            // The arm in front of the camera must not trigger target-lost or sensing announcements.
            targetDescription="Pointing · pins hold the scene from before your hand came up"; voiceTargetPhrase=nil; return
        }
        if let target,target.valid(at:now),output.state == .live {
            targetDescription=String(format:"%@, %.1f m, %.0f°",target.label,target.distance,target.bearingDegrees)+(guidanceCue.map { " · guiding: "+$0.spoken } ?? "")
            voiceTargetPhrase = held != nil ? VoicePhrasing.observation(target, named: target.label, now: now) : VoicePhrasing.observation(target, finder: finder, now: now)
        } else {
            voiceTargetPhrase = nil
            targetDescription=heldTarget != nil ? "Where-is target outside the pins' field" : finder == .none ? "Obstacle sensing"+(open.map { " · "+$0.spoken } ?? "") : remembered(frame.routeHint) ?? "Target unavailable. No directional highlight"
        }
        updateVoiceAwareness(targetAvailable: target?.valid(at: now) == true && output.state == .live,
                             target: target, distances: distances, openSide: open, now: now)
        if output.state == .live { followWaypoints(frame: frame, now: now) }
        if let heldTarget {
            let shown = waypoint ?? heldTarget
            let event = HeldTargetGuidance.event(target: shown, pose: frame.pose, worldEpoch: frame.worldEpoch, now: now, live: output.state == .live, inField: held != nil, lastSpokenAt: lastDirectionSpokenAt)
            // On the way to a progress point the follower decides arrival, not the half-metre radius of the point itself.
            if event != .reached || waypoint == nil { handleHeldEvent(event, target: heldTarget, now: now, pose: frame.pose) }
        }
    }
}
