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

final class GrokWebSocket: VoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .ephemeral)
    func open(token: String) {
        var request = URLRequest(url: URL(string: "wss://api.x.ai/v1/realtime?model=grok-voice-latest")!)
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
                case .failure: self.onFailure?()
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
final class GrokVoiceSession: ObservableObject {
    enum Phase: String { case idle, connecting, listening, thinking, speaking, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var caption = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var needsMicrophoneSettings = false
    @Published private(set) var configuration: VoiceConfiguration?
    @Published var proactiveEnabled = UserDefaults.standard.object(forKey: "voice.proactive") as? Bool ?? true {
        didSet { UserDefaults.standard.set(proactiveEnabled, forKey: "voice.proactive") }
    }
    @Published private(set) var isPausedByUser = false
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
    private var continuationPending = false
    private var assistantItemID: String?
    private var lastAnnouncement = Date.distantPast
    private var sceneExpiry: DispatchWorkItem?
    private var sceneBound = false
    private var awaitingResponse = false
    private var discardNextResponse = false
    private let speaksLocally: Bool
    /// While another listener borrows the microphone, nothing is sent to Grok.
    private var uplinkMuted = false

    var isActive: Bool { phase != .idle && phase != .failed }
    var isConfigured: Bool { configuration?.isValid == true }
    var label: String {
        switch phase {
        case .idle: return isPausedByUser ? "Assistant paused" : "Assistant unavailable"
        case .connecting: return "Connecting"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "FEEL is speaking"
        case .failed: return "Assistant unavailable"
        }
    }

    init(tokenClient: VoiceTokenFetching = VoiceTokenClient(), audio: VoiceAudioIO = DeviceVoiceAudio(),
         transportFactory: @escaping () -> VoiceTransport = { GrokWebSocket() },
         configuration: VoiceConfiguration? = nil, speaksLocally: Bool = true,
         requestPermission: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
             AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                 DispatchQueue.main.async { completion(allowed) }
             }
         }) {
        self.tokenClient = tokenClient; self.audio = audio; self.transportFactory = transportFactory
        self.configuration = configuration ?? store.loadForLaunch(); self.requestPermission = requestPermission
        self.speaksLocally = speaksLocally
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

    func start() {
        guard !isActive else { return }
        disconnect()
        guard let configuration, configuration.isValid else {
            errorMessage = "Set up Grok Voice in Settings first."; phase = .failed; return
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
            self.caption = "Connecting to Grok"
            self.armTimeout(id)
            self.tokenClient.fetch(configuration) { [weak self] result in
                guard let self, self.generation == id, self.isActive else { return }
                switch result {
                case .failure: self.fail("Voice couldn't connect. Check your connection and voice setup, then retry.")
                case .success(let token):
                    let connection = self.transportFactory()
                    self.transport = connection
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
            }
        }
    }

    func disconnect() {
        generation = UUID()
        retryWork?.cancel(); retryWork = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
        sessionLimit?.cancel(); sessionLimit = nil
        tokenClient.cancel(); transport?.close(); transport = nil
        audio.stop(); speaker?.stopSpeaking(at: .immediate)
        sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
        awaitingResponse = false; discardNextResponse = false
        outgoing = []; sending = false; configured = false; receivedConfiguration = false
        handledCalls = []; interruptedResponses = []; responseID = nil; responseRunning = false
        continuationPending = false; assistantItemID = nil
        userSpeaking = false; uplinkMuted = false
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

    /// Asks the wearer a question that the app needs answered through a tool call
    /// (which of several targets to guide to). Not throttled like scene announcements.
    @discardableResult func ask(_ text: String) -> Bool {
        guard phase == .listening, receivedConfiguration, !userSpeaking, !responseRunning, !awaitingResponse,
              !discardNextResponse, !audio.pendingPlayback else { return false }
        lastAnnouncement = Date()
        awaitingResponse = true
        phase = .thinking
        enqueue(["type": "conversation.item.create", "item": ["type": "force_message", "role": "assistant",
                 "content": [["type": "output_text", "text": String(text.prefix(240))]]]])
        return isActive
    }

    /// Only exact, freshly produced app text may be announced without a user turn.
    @discardableResult func announce(_ text: String, automatic: Bool = true, sceneBound: Bool = false) -> Bool {
        guard (!automatic || proactiveEnabled), !userSpeaking, phase == .listening, !responseRunning, !awaitingResponse, !discardNextResponse, !audio.pendingPlayback,
              Date().timeIntervalSince(lastAnnouncement) > 5 else { return false }
        lastAnnouncement = Date()
        awaitingResponse = true
        if sceneBound { bindSceneSpeech() }
        phase = .thinking
        enqueue(["type": "conversation.item.create", "item": ["type": "force_message", "role": "assistant",
                 "content": [["type": "output_text", "text": String(text.prefix(240))]]]])
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
        let generationBeforeCancel = generation
        sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
        if awaitingResponse { discardNextResponse = true }
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

    private func rejectResponse(_ id: String, cancel: Bool) {
        interruptedResponses.insert(id)
        guard interruptedResponses.count <= 128 else { fail("Voice session ended. Tap to reconnect."); return }
        if cancel { enqueue(["type": "response.cancel", "response_id": id]) }
    }

    private func fail(_ message: String, speak shouldSpeak: Bool = true) {
        disconnect(); errorMessage = message; phase = .failed
        if shouldSpeak { speak("Voice disconnected. The camera still works.") }
        guard shouldSpeak, automaticListening, foreground, !isPausedByUser, !waitingForHeadphones, retryCount < 3 else { return }
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
        guard speaksLocally, !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
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
            if self.userSpeaking || self.responseRunning || self.audio.pendingPlayback || self.awaitingResponse {
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
        guard outgoing.count < 8 else { fail("Voice connection is too slow. Tap to retry."); return }
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
                "voice": "sal", "instructions": VoiceCommand.instructions,
                "turn_detection": ["type": "server_vad"], "tools": VoiceCommand.tools,
                "audio": ["input": ["format": ["type": "audio/pcm", "rate": 24000]],
                          "output": ["format": ["type": "audio/pcm", "rate": 24000]]]]])
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
                    self.finishTurnIfReady()
                })
                phase = .listening; caption = "Ask me to find something"
                scheduleSessionRenewal(id, after: 900)
                announce("I'm here.", automatic: false)
            } catch { fail("The microphone couldn't start. Check your audio device and retry.") }
        case "input_audio_buffer.speech_started":
            let generationBeforeInterrupt = generation
            userSpeaking = true
            sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
            if awaitingResponse { discardNextResponse = true }
            if let responseID {
                interruptedResponses.insert(responseID)
                if interruptedResponses.count > 128 { fail("Voice session ended. Tap to reconnect."); return }
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
            awaitingResponse = false
            if userSpeaking || discardNextResponse {
                discardNextResponse = false
                rejectResponse(id, cancel: true)
                return
            }
            audio.interruptPlayback()
            responseID = id; responseRunning = true; assistantItemID = nil; caption = ""
            phase = .thinking
        case "response.output_audio.delta", "response.audio.delta":
            guard accepts(event), let delta = event["delta"] as? String, delta.count < 1_000_000,
                  let data = Data(base64Encoded: delta) else { return }
            assistantItemID = event["item_id"] as? String
            do { try audio.play(data); phase = .speaking }
            catch { fail("Voice playback stopped. Tap to retry.") }
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            guard accepts(event), let delta = event["delta"] as? String else { return }
            caption = String((caption + delta).prefix(400))
        case "response.function_call_arguments.done":
            guard accepts(event), let callID = event["call_id"] as? String, callID.count < 256,
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
            responseRunning = false
            finishTurnIfReady()
        case "error": fail("Grok couldn't complete the voice session. Check setup and retry.")
        default: break
        }
    }
    private func accepts(_ event: [String: Any]) -> Bool {
        guard receivedConfiguration, !userSpeaking, responseRunning, let id = event["response_id"] as? String,
              id == responseID, !interruptedResponses.contains(id) else { return false }
        return true
    }
    private func finishTurnIfReady() {
        guard !responseRunning, !awaitingResponse, !discardNextResponse, !audio.pendingPlayback, isActive, receivedConfiguration else { return }
        if continuationPending {
            continuationPending = false; phase = .thinking; awaitingResponse = true
            enqueue(["type": "response.create"])
        } else {
            sceneExpiry?.cancel(); sceneExpiry = nil; sceneBound = false
            phase = .listening
        }
    }
}
