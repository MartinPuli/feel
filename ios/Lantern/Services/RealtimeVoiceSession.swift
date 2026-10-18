import Foundation
import Combine
import AVFoundation
import UIKit

protocol VoiceTransport: AnyObject {
    var onEvent: (([String: Any]) -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }
    func open(token: String)
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void)
    func close()
}

final class OpenAIVoiceWebSocket: VoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .ephemeral)
    func open(token: String) {
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 1_048_576
        self.socket = socket
        socket.resume()
        receive(socket)
    }
    private func receive(_ connection: URLSessionWebSocketTask) {
        connection.receive { [weak self, weak connection] result in
            DispatchQueue.main.async {
                guard let self, let connection, self.socket === connection else { return }
                switch result {
                case .failure(let error):
                    let failure = error as NSError
                    VoiceDiagnostics.record("transport_failure", detail: "code=\(failure.code), close=\(connection.closeCode.rawValue)")
                    self.onFailure?()
                case .success(let message):
                    let data: Data?
                    switch message {
                    case .string(let text): data = text.data(using: .utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: data = nil
                    }
                    if let data, let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.onEvent?(event)
                        if self.socket === connection { self.receive(connection) }
                    } else { self.onFailure?() }
                }
            }
        }
    }
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { completion(false); return }
        socket.send(.string(text)) { error in DispatchQueue.main.async { completion(error == nil) } }
    }
    func close() { socket?.cancel(with: .normalClosure, reason: nil); socket = nil }
}

/// All session state and callbacks run on the main queue. Generations invalidate
/// permission, token, socket, audio and tool callbacks after every Stop.
final class RealtimeVoiceSession: ObservableObject {
    enum Phase: String { case idle, connecting, listening, thinking, speaking, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var caption = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var needsMicrophoneSettings = false
    @Published private(set) var configuration: VoiceConfiguration?
    @Published private(set) var spokenOutputEnabled = true
    @Published var proactiveEnabled = UserDefaults.standard.object(forKey: "voice.proactive") as? Bool ?? true {
        didSet { UserDefaults.standard.set(proactiveEnabled, forKey: "voice.proactive") }
    }
    @Published private(set) var isPausedByUser = false
    /// Sound output could not play (no running audio engine, as on simulators). The
    /// conversation continues through captions and tool calls.
    @Published private(set) var audioUnavailable = false
    private var automaticListening = false
    private var foreground = true
    private var waitingForHeadphones = false
    private var retryWork: DispatchWorkItem?
    private var retryCount = 0
    private var announcedMissingSetup = false
    private var userSpeaking = false
    var onCommand: ((VoiceCommand) -> [String: Any])?
    var onEnded: (() -> Void)?
    private let tokenClient: VoiceTokenFetching
    private let audio: VoiceAudioIO
    private let transportFactory: () -> VoiceTransport
    private let requestPermission: (@escaping (Bool) -> Void) -> Void
    private var speaker: AVSpeechSynthesizer?
    private let store = VoiceConfigurationStore()
    private var transport: VoiceTransport?
    private var generation = UUID()
    private var connectionTimeout: DispatchWorkItem?
    private var sessionLimit: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var configured = false
    private var receivedConfiguration = false
    private var sending = false
    private var outgoing: [[String: Any]] = []
    private var handledCalls = Set<String>()
    private var interruptedResponses = Set<String>()
    private var responseID: String?
    private var responseRunning = false
    private var responseIsAnnouncement = false
    private var continuationPending = false
    private var assistantItemID: String?
    private var lastAnnouncement = Date.distantPast
    private var sceneExpiry: DispatchWorkItem?
    private var sceneBound = false
    private var pendingRequestID: String?
    private var invalidatedRequestIDs = Set<String>()
    private struct AnnouncementDelivery {
        let requestID: String
        let callback: () -> Void
        var responseID: String?
        var receivedAudio = false
        var drained = false
        var completed = false
    }
    private var announcementDelivery: AnnouncementDelivery?
    var hasPendingAnnouncementDelivery: Bool { announcementDelivery != nil }
    private let speaksLocally: Bool
    private let silentPlaybackFallback: Bool
    /// While another listener borrows the microphone, nothing is sent to OpenAI.
    private var uplinkMuted = false

    var isActive: Bool { phase != .idle && phase != .failed }
    var isConfigured: Bool { configuration?.isValid == true }
    var label: String {
        switch phase {
        case .idle: return isPausedByUser ? "Assistant paused" : "Assistant unavailable"
        case .connecting: return "Connecting"
        case .listening: return spokenOutputEnabled ? "Listening" : "Listening quietly"
        case .thinking: return "Thinking"
        case .speaking: return "FEEL is speaking"
        case .failed: return "Assistant unavailable"
        }
    }

    init(tokenClient: VoiceTokenFetching = VoiceTokenClient(), audio: VoiceAudioIO = DeviceVoiceAudio(),
         transportFactory: @escaping () -> VoiceTransport = { OpenAIVoiceWebSocket() },
         configuration: VoiceConfiguration? = nil, speaksLocally: Bool = true, silentPlaybackFallback: Bool? = nil,
         requestPermission: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
             AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                 DispatchQueue.main.async { completion(allowed) }
             }
         }) {
        self.tokenClient = tokenClient; self.audio = audio; self.transportFactory = transportFactory
        self.configuration = configuration ?? store.loadForLaunch(); self.requestPermission = requestPermission
        self.speaksLocally = speaksLocally
        self.silentPlaybackFallback = silentPlaybackFallback ?? Self.runsInSimulator
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if name == UIApplication.didEnterBackgroundNotification {
                    self.enterBackground()
                    return
                }
                if name == AVAudioSession.routeChangeNotification {
                    let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                    if reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                        self.waitingForHeadphones = false
                        if self.automaticListening && self.foreground && !self.isPausedByUser {
                            self.disconnect(); self.start()
                        }
                    } else if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, self.isActive {
                        self.waitingForHeadphones = true
                        self.disconnect(); self.caption = "Headphones disconnected. Assistant paused."
                        self.speak("Headphones disconnected. Reconnect them to resume.")
                    }
                    return
                }
                if name == AVAudioSession.interruptionNotification {
                    let kind = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                    if kind == AVAudioSession.InterruptionType.ended.rawValue {
                        let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
                        if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0 {
                            self.resumeAutomaticallyIfPossible()
                        }
                        return
                    }
                }
                guard self.isActive else { return }
                self.disconnect()
                self.caption = "Assistant paused by an audio interruption."
                if name == AVAudioSession.mediaServicesWereResetNotification {
                    self.resumeAutomaticallyIfPossible()
                }

            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func saveConfiguration(endpoint: String, accessToken: String) throws {
        let config = VoiceConfiguration(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                                        accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines))
        try store.save(config)
        disconnect(); configuration = config; errorMessage = ""
    }
    func forgetConfiguration() { disconnect(); store.clear(); configuration = nil }

    /// The assistant is the primary control surface, active whenever FEEL is open.
    func enterForeground() {
        foreground = true; automaticListening = true
        resumeAutomaticallyIfPossible()
    }
    func enterBackground() {
        foreground = false
        disconnect()
    }
    private func resumeAutomaticallyIfPossible() {
        guard automaticListening, foreground, !isPausedByUser, !waitingForHeadphones, !isActive else { return }
        guard isConfigured else {
            errorMessage = "Voice setup is needed once before the assistant can listen."
            if !announcedMissingSetup {
                announcedMissingSetup = true
                speak("Voice needs setup. Open Assistant settings.")
            }
            return
        }
        retryCount = 0
        start()
    }
    func pauseAssistant() {
        isPausedByUser = true
        disconnect(); caption = "Assistant paused"
        speak("Assistant paused.")
    }
    func resumeAssistant() {
        isPausedByUser = false; waitingForHeadphones = false
        automaticListening = true; foreground = true; retryCount = 0
        start()
    }

    /// Silence output without disconnecting the microphone, tools or transport.
    func setSpokenOutput(_ enabled: Bool) {
        guard spokenOutputEnabled != enabled else { return }
        spokenOutputEnabled = enabled
        if !enabled {
            announcementDelivery = nil
            audio.interruptPlayback()
            speaker?.stopSpeaking(at: .immediate)
            if phase == .speaking { phase = responseRunning ? .thinking : .listening }
            finishTurnIfReady()
        }
    }

    func start() {
        guard !isActive else { return }
        disconnect()
        guard let configuration, configuration.isValid else {
            errorMessage = "Set up voice in Settings first."; phase = .failed; return
        }
        lastAnnouncement = .distantPast
        phase = .connecting; caption = "Opening voice"; errorMessage = ""; needsMicrophoneSettings = false
        let id = generation
        requestPermission { [weak self] allowed in
            guard let self, self.generation == id, self.isActive else { return }
            guard allowed else {
                self.fail("Allow Microphone in iPhone Settings so the assistant can listen.", speak: false)
                self.needsMicrophoneSettings = true
                self.speak("Microphone access is off. Enable it in iPhone Settings.")
                return
            }
            self.caption = "Connecting to OpenAI"
            self.armTimeout(id)
            self.tokenClient.fetch(configuration) { [weak self] result in
                guard let self, self.generation == id, self.isActive else { return }
                switch result {
                case .failure: self.fail("Voice couldn't connect. Check your connection and voice setup, then retry.")
                case .success(let token): self.openTransport(token: token, generation: id)
                }
            }
        }
    }
    private func openTransport(token: String, generation id: UUID) {
        let connection = transportFactory()
        transport = connection
        connection.onEvent = { [weak self] event in
            guard let self, self.generation == id, self.isActive else { return }
            self.receive(event)
        }
        connection.onFailure = { [weak self] in
            guard let self, self.generation == id, self.isActive else { return }
            self.fail("Voice disconnected. Tap to reconnect.")
        }
        connection.open(token: token)
    }

    /// A typed request takes the same path as speech: a user item, then a response.
    /// Also the fallback for a loud room or a Bluetooth keyboard with VoiceOver.
    private static let runsInSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()
    @discardableResult func sendText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, receivedConfiguration, !userSpeaking, !responseRunning, pendingRequestID == nil, (1...160).contains(trimmed.unicodeScalars.count) else { return false }
        phase = .thinking; caption = String(trimmed.prefix(400))
        enqueue(["type": "conversation.item.create", "item": ["type": "message", "role": "user",
                 "content": [["type": "input_text", "text": trimmed]]]])
        requestResponse([:])
        return true
    }

    func disconnect() {
        announcementDelivery = nil
        generation = UUID()
        retryWork?.cancel(); retryWork = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
        sessionLimit?.cancel(); sessionLimit = nil
        tokenClient.cancel(); transport?.close(); transport = nil
        audio.stop(); speaker?.stopSpeaking(at: .immediate)
        sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
        pendingRequestID = nil; invalidatedRequestIDs = []
        outgoing = []; sending = false; configured = false; receivedConfiguration = false
        handledCalls = []; interruptedResponses = []; responseID = nil; responseRunning = false; responseIsAnnouncement = false
        continuationPending = false; assistantItemID = nil
        userSpeaking = false; audioUnavailable = false; uplinkMuted = false
        phase = .idle; caption = ""; onEnded?()
    }

    /// Lends the running microphone to `handler` and mutes the uplink, so the assistant neither
    /// hears nor answers the target word said after a V sign. Pass nil to give it back.
    /// Returns false when the assistant's microphone is not running.
    @discardableResult func borrowMicrophone(_ handler: ((AVAudioPCMBuffer) -> Void)?) -> Bool {
        guard let handler else { audio.setAuxiliaryInput(nil); uplinkMuted = false; return true }
        guard isActive, receivedConfiguration else { return false }
        uplinkMuted = true; audio.setAuxiliaryInput(handler)
        return true
    }

    /// Asks the wearer a question the app needs answered through a tool call (which of several
    /// targets to guide to). In the conversation, not out-of-band, so the answer can be matched to
    /// `choose_target`; not throttled like scene announcements.
    @discardableResult func ask(_ text: String) -> Bool {
        guard spokenOutputEnabled, isActive, receivedConfiguration, phase == .listening, !userSpeaking, !responseRunning,
              pendingRequestID == nil, !audio.pendingPlayback else { return false }
        lastAnnouncement = Date()
        phase = .thinking
        requestResponse(["instructions": "Say exactly this, then wait for the answer: \(String(text.prefix(240)))"])
        return true
    }

    /// Only exact, freshly produced app text may be announced without a user turn.
    /// Delivery is reported once only after successful completion and audible playback drain.
    /// Muting, interruption, expiry or replacement discards the delivery callback.
    @discardableResult func announce(_ text: String, automatic: Bool = true, sceneBound: Bool = false,
                                    onDelivered: (() -> Void)? = nil) -> Bool {
        guard spokenOutputEnabled, (!automatic || proactiveEnabled), !userSpeaking, phase == .listening, !responseRunning, pendingRequestID == nil, !audio.pendingPlayback,
              Date().timeIntervalSince(lastAnnouncement) > 5 else { return false }
        lastAnnouncement = Date()
        if sceneBound { bindSceneSpeech() }
        phase = .thinking
        // OpenAI has no force_message event. Request a tool-free, isolated spoken
        // announcement without adding a synthetic user request to conversation history.
        requestResponse(["conversation": "none", "input": [],
                 "tools": [], "output_modalities": ["audio"], "max_output_tokens": 160,
                 "metadata": ["feel_announcement": "true"],
                 "instructions": "Speak only the following app status, naturally and briefly. Do not add advice or call tools: " + String(text.prefix(240))], onDelivered: onDelivered)
        return isActive
    }

    /// Scene observations expire even if the network has not produced audio yet.
    private func bindSceneSpeech() {
        sceneBound = true
        sceneExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.invalidateSceneSpeech() }
        sceneExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func invalidateSceneSpeech() {
        guard sceneBound else { return }
        announcementDelivery = nil
        let generationBeforeCancel = generation
        sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
        guard invalidatePendingRequest() else { return }
        if let responseID {
            rejectResponse(responseID, cancel: responseRunning)
            if let assistantItemID {
                enqueue(["type": "conversation.item.truncate", "item_id": assistantItemID,
                         "content_index": 0, "audio_end_ms": audio.playedMilliseconds])
            }
        }
        guard generation == generationBeforeCancel, isActive else { return }
        audio.interruptPlayback()
        responseID = nil; responseRunning = false; continuationPending = false; assistantItemID = nil
        caption = "Scene changed. Ask for a fresh update."
        phase = .listening
    }

    private func requestResponse(_ parameters: [String: Any], onDelivered: (() -> Void)? = nil) {
        let requestID = UUID().uuidString
        pendingRequestID = requestID
        announcementDelivery = onDelivered.map { AnnouncementDelivery(requestID: requestID, callback: $0) }
        var parameters = parameters
        var metadata = parameters["metadata"] as? [String: String] ?? [:]
        metadata["feel_request_id"] = requestID
        parameters["metadata"] = metadata
        enqueue(["type": "response.create", "response": parameters])
    }

    @discardableResult private func invalidatePendingRequest() -> Bool {
        guard let requestID = pendingRequestID else { return true }
        if announcementDelivery?.requestID == requestID { announcementDelivery = nil }
        pendingRequestID = nil
        invalidatedRequestIDs.insert(requestID)
        guard invalidatedRequestIDs.count <= 128 else {
            fail("Voice session ended. Tap to reconnect.")
            return false
        }
        return true
    }

    private func rejectResponse(_ id: String, cancel: Bool) {
        interruptedResponses.insert(id)
        guard interruptedResponses.count <= 128 else { fail("Voice session ended. Tap to reconnect."); return }
        if cancel { enqueue(["type": "response.cancel", "response_id": id]) }
    }

    private func fail(_ message: String, speak shouldSpeak: Bool = true) {
        VoiceDiagnostics.record("failure", detail: message)
        disconnect(); errorMessage = message; phase = .failed
        let willRetry = shouldSpeak && automaticListening && foreground && !isPausedByUser && !waitingForHeadphones && retryCount < 3
        if shouldSpeak && (retryCount == 0 || !willRetry) {
            speak(willRetry ? "Voice paused. Reconnecting." : "Voice paused. Open Assistant to retry.")
        }
        guard willRetry else { return }
        retryCount += 1
        let id = generation
        let retry = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id, self.foreground, !self.isPausedByUser else { return }
            self.start()
        }
        retryWork = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(retryCount * 2), execute: retry)
    }
    private func speak(_ text: String) {
        guard spokenOutputEnabled, speaksLocally, !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        // Local fallback feedback remains audible when the voice network fails.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let utterance = AVSpeechUtterance(string: text)
        // Prefer a higher-quality installed voice without requiring a download.
        utterance.voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        if speaker == nil { speaker = AVSpeechSynthesizer() }
        speaker?.speak(utterance)
    }
    private func armTimeout(_ id: UUID) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id, self.phase == .connecting else { return }
            self.fail("Voice took too long to connect. Tap to retry.")
        }
        connectionTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: work)
    }

    private func scheduleSessionRenewal(_ id: UUID, after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id else { return }
            if self.userSpeaking || self.responseRunning || self.audio.pendingPlayback || self.pendingRequestID != nil {
                self.scheduleSessionRenewal(id, after: 30)
            } else if self.automaticListening && self.foreground && !self.isPausedByUser {
                self.disconnect(); self.start()
            } else {
                self.disconnect(); self.caption = "Assistant paused"
            }
        }
        sessionLimit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func enqueue(_ event: [String: Any]) {
        guard isActive else { return }
        if event["type"] as? String == "input_audio_buffer.append",
           let encoded = event["audio"] as? String, let input = Data(base64Encoded: encoded) {
            // Native taps arrive every ~20 ms. A brief send delay must not exhaust
            // a message-count limit; retain at most one second of queued PCM.
            let queuedBytes = outgoing.reduce(0) { total, pending in
                total + ((pending["audio"] as? String).flatMap { Data(base64Encoded: $0)?.count } ?? 0)
            }
            guard input.count <= 48_000 - queuedBytes else {
                fail("Voice connection is too slow. Tap to retry."); return
            }
            if let last = outgoing.last, last["type"] as? String == "input_audio_buffer.append",
               let previous = last["audio"] as? String, var combined = Data(base64Encoded: previous) {
                combined.append(input)
                outgoing[outgoing.count - 1]["audio"] = combined.base64EncodedString()
                return
            }
        } else {
            let controls = outgoing.filter { $0["type"] as? String != "input_audio_buffer.append" }.count
            guard controls < 8 else { fail("Voice connection is too slow. Tap to retry."); return }
        }
        outgoing.append(event); sendNext()
    }
    private func sendNext() {
        guard !sending, !outgoing.isEmpty, let transport, isActive else { return }
        sending = true
        let event = outgoing.removeFirst(), id = generation
        transport.send(event) { [weak self] success in
            guard let self, self.generation == id, self.isActive else { return }
            self.sending = false
            if success { self.sendNext() } else { self.fail("Voice disconnected. Tap to reconnect.") }
        }
    }

    private func receive(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        switch type {
        case "session.created":
            guard !configured else { return }; configured = true
            enqueue(["type": "session.update", "session": [
                "type": "realtime", "instructions": VoiceCommand.instructions,
                "output_modalities": ["audio"], "max_output_tokens": 160, "tools": VoiceCommand.tools,
                "audio": ["input": ["format": ["type": "audio/pcm", "rate": 24000],
                                    "turn_detection": ["type": "server_vad", "create_response": true, "interrupt_response": true]],
                          "output": ["voice": "cedar", "speed": 1.2, "format": ["type": "audio/pcm", "rate": 24000]]]]])
        case "session.updated":
            guard configured, !receivedConfiguration else { return }
            receivedConfiguration = true
            connectionTimeout?.cancel(); connectionTimeout = nil
            let id = generation
            do {
                try audio.start(onInput: { [weak self] data in
                    guard let self, self.generation == id, self.isActive, !self.uplinkMuted else { return }
                    self.enqueue(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()])
                }, onPlaybackDrained: { [weak self] in
                    guard let self, self.generation == id, self.isActive else { return }
                    if !self.audio.pendingPlayback, let delivery = self.announcementDelivery,
                       delivery.responseID == self.responseID, delivery.receivedAudio {
                        self.announcementDelivery?.drained = true
                    }
                    self.finishTurnIfReady()
                })
                phase = .listening; caption = "Ask me to find something"
                VoiceDiagnostics.record("session_ready")
                scheduleSessionRenewal(id, after: 900)
                announce("I'm here.", automatic: false)
            } catch { fail("The microphone couldn't start. Check your audio device and retry.") }
        case "input_audio_buffer.speech_started":
            announcementDelivery = nil
            let generationBeforeInterrupt = generation
            userSpeaking = true
            sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
            guard invalidatePendingRequest() else { return }
            if let responseID {
                interruptedResponses.insert(responseID)
                if interruptedResponses.count > 128 { fail("Voice session ended. Tap to reconnect."); return }
                if responseIsAnnouncement && responseRunning {
                    enqueue(["type": "response.cancel", "response_id": responseID])
                }
            }
            if let assistantItemID {
                enqueue(["type": "conversation.item.truncate", "item_id": assistantItemID,
                         "content_index": 0, "audio_end_ms": audio.playedMilliseconds])
            }
            guard generation == generationBeforeInterrupt, isActive else { return }
            audio.interruptPlayback()
            responseID = nil; responseRunning = false; continuationPending = false; assistantItemID = nil
            phase = .listening; caption = "Listening to you"
        case "input_audio_buffer.speech_stopped": userSpeaking = false; phase = .thinking
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = event["transcript"] as? String { caption = String(transcript.prefix(400)) }
        case "response.created":
            guard let response = event["response"] as? [String: Any], let id = response["id"] as? String,
                  !interruptedResponses.contains(id) else { return }
            guard id != responseID else { return }
            let metadata = response["metadata"] as? [String: String] ?? [:]
            let requestID = metadata["feel_request_id"]
            let isAnnouncement = metadata["feel_announcement"] == "true"
            // Manual responses may arrive after the user's newer VAD response.
            // Reject by request identity without touching that newer response.
            if let requestID, invalidatedRequestIDs.contains(requestID) || requestID != pendingRequestID {
                rejectResponse(id, cancel: true)
                return
            }
            if isAnnouncement && requestID == nil {
                rejectResponse(id, cancel: true)
                return
            }
            if userSpeaking || (isAnnouncement && (responseID != nil || audio.pendingPlayback)) {
                if requestID == pendingRequestID { guard invalidatePendingRequest() else { return } }
                rejectResponse(id, cancel: true)
                return
            }
            let generationBeforeReplacement = generation
            if requestID != nil {
                pendingRequestID = nil
            } else {
                // A user response takes priority over any pending app request.
                guard invalidatePendingRequest() else { return }
                sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
            }
            if let previousID = responseID { rejectResponse(previousID, cancel: responseRunning) }
            guard generation == generationBeforeReplacement, isActive else { return }
            if announcementDelivery?.requestID != requestID { announcementDelivery = nil }
            audio.interruptPlayback()
            responseID = id; responseRunning = true; assistantItemID = nil; caption = ""
            announcementDelivery?.responseID = id
            responseIsAnnouncement = isAnnouncement
            phase = .thinking
        case "response.output_audio.delta", "response.audio.delta":
            guard accepts(event), let delta = event["delta"] as? String, delta.count < 1_000_000,
                  let data = Data(base64Encoded: delta) else { return }
            guard spokenOutputEnabled else { return }
            // Out-of-band announcements do not have a default-history item to truncate.
            assistantItemID = responseIsAnnouncement ? nil : event["item_id"] as? String
            do {
                if !data.isEmpty, announcementDelivery?.responseID == responseID {
                    announcementDelivery?.receivedAudio = true
                    announcementDelivery?.drained = false
                }
                try audio.play(data); phase = .speaking
            }
            catch VoiceAudioError.notRunning where silentPlaybackFallback {
                announcementDelivery = nil
                // The simulator has no audio engine: keep the conversation going through captions and tools.
                // On a phone a stopped engine is a real failure and takes the recovery path below.
                VoiceDiagnostics.record("playback_failure", detail: "engine_not_running")
                audioUnavailable = true; phase = .speaking
            }
            catch {
                let code: String
                switch error {
                case VoiceAudioError.notRunning: code = "engine_not_running"
                case VoiceAudioError.invalidPCM: code = "invalid_pcm"
                case VoiceAudioError.playbackOverflow: code = "playback_overflow"
                default: code = "audio_error"
                }
                VoiceDiagnostics.record("playback_failure", detail: code)
                fail("Voice playback stopped. Tap to retry.")
            }
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            guard accepts(event), let delta = event["delta"] as? String else { return }
            caption = String((caption + delta).prefix(400))
        case "response.function_call_arguments.done":
            guard !responseIsAnnouncement, accepts(event), let callID = event["call_id"] as? String, callID.count < 256,
                  !handledCalls.contains(callID), let name = event["name"] as? String,
                  let arguments = event["arguments"] as? String else { return }
            guard handledCalls.count < 256 else { fail("Voice session ended. Tap to reconnect."); return }
            handledCalls.insert(callID)
            let id = generation
            let result: [String: Any]
            do {
                let command = try VoiceCommand.decode(name: name, arguments: arguments)
                result = onCommand?(command) ?? ["error": "App controls are unavailable"]
                if result["scene_observation"] as? Bool == true { bindSceneSpeech() }
            } catch { result = ["error": "Unsupported command or invalid arguments. No action was taken."] }
            // Stop can synchronously end the session while executing a command.
            guard generation == id, isActive else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let output = String(data: data, encoding: .utf8) else { return }
            enqueue(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callID, "output": output]])
            guard generation == id, isActive else { return }
            continuationPending = true
            finishTurnIfReady()
        case "response.done":
            guard let response = event["response"] as? [String: Any], let id = response["id"] as? String, id == responseID else { return }
            if response["status"] as? String == "failed" {
                fail("OpenAI couldn't complete the response. Check voice service access and retry."); return
            }
            if announcementDelivery?.responseID == id {
                if response["status"] as? String == "completed" { announcementDelivery?.completed = true }
                else { announcementDelivery = nil }
            }
            responseRunning = false
            finishTurnIfReady()
        case "error":
            let code = VoiceDiagnostics.providerCode(event)
            VoiceDiagnostics.record("provider_error", detail: code)
            // Cancellation can race server VAD or completion; the socket remains usable.
            if code == "response_cancel_not_active" { return }
            fail("OpenAI couldn't complete the voice session. Check setup and retry.")
        default: break
        }
    }
    private func accepts(_ event: [String: Any]) -> Bool {
        guard receivedConfiguration, !userSpeaking, responseRunning, let id = event["response_id"] as? String,
              id == responseID, !interruptedResponses.contains(id) else { return false }
        return true
    }
    private func finishTurnIfReady() {
        guard !userSpeaking, !responseRunning, pendingRequestID == nil, !audio.pendingPlayback, isActive, receivedConfiguration else { return }
        if continuationPending {
            continuationPending = false; phase = .thinking
            requestResponse([:])
        } else {
            let delivery = announcementDelivery
            announcementDelivery = nil
            let delivered = delivery?.responseID == responseID && delivery?.completed == true &&
                delivery?.receivedAudio == true && delivery?.drained == true && spokenOutputEnabled
            sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
            // Completed audio no longer needs a truncation when the user next speaks.
            assistantItemID = nil; responseID = nil
            phase = .listening
            if delivered { delivery?.callback() }
        }
    }
}
