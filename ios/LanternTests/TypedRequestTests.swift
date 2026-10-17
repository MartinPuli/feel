import XCTest
@testable import Lantern

private final class TypedFakeToken: VoiceTokenFetching {
    private var completion: ((Result<String, Error>) -> Void)?
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void) { self.completion = completion }
    func cancel() { completion = nil }
    func complete(_ result: Result<String, Error>) { completion?(result); completion = nil }
}

private final class TypedFakeTransport: VoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?
    var sent: [[String: Any]] = []
    func open(token: String) {}
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) { sent.append(event); completion(true) }
    func close() {}
    func emit(_ event: [String: Any]) { onEvent?(event) }
}

private final class TypedFakeAudio: VoiceAudioIO {
    var pendingPlayback = false
    var playedMilliseconds = 0
    var playError: Error?
    private(set) var running = false
    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws { running = true }
    func play(_ pcm: Data) throws { if let playError { throw playError } }
    func interruptPlayback() {}
    func stop() { running = false }
}

/// Typed requests share the voice session; audio failures follow the selected platform policy.
final class TypedRequestTests: XCTestCase {
    private let config = VoiceConfiguration(endpoint: "https://voice.example/session", accessToken: String(repeating: "a", count: 32))

    private func ready(audio: TypedFakeAudio = TypedFakeAudio(), silentPlaybackFallback: Bool? = nil) -> (RealtimeVoiceSession, TypedFakeTransport) {
        let token = TypedFakeToken(), transport = TypedFakeTransport()
        let voice = RealtimeVoiceSession(tokenClient: token, audio: audio, transportFactory: { transport },
                                         configuration: config, speaksLocally: false, silentPlaybackFallback: silentPlaybackFallback, requestPermission: { $0(true) })
        voice.start(); token.complete(.success("ephemeral"))
        transport.emit(["type": "session.created"]); transport.emit(["type": "session.updated"])
        acknowledgeOpeningGreeting(transport.sent, emit: transport.emit)
        return (voice, transport)
    }

    func testSendTextCreatesUserItemThenResponse() throws {
        let (voice, transport) = ready()
        transport.sent.removeAll()
        XCTAssertTrue(voice.sendText("where is the exit"))
        XCTAssertEqual(transport.sent.compactMap { $0["type"] as? String }, ["conversation.item.create", "response.create"])
        let item = try XCTUnwrap(transport.sent[0]["item"] as? [String: Any])
        XCTAssertEqual(item["role"] as? String, "user")
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content.first?["text"] as? String, "where is the exit")
        XCTAssertFalse(voice.sendText("   "), "Blank text is not sent")
        XCTAssertFalse(voice.sendText(String(repeating: "x", count: 161)), "Overlong text is not sent")
    }

    func testSendTextWaitsForTheCurrentReply() {
        let (voice, transport) = ready()
        transport.emit(["type": "response.created", "response": ["id": "r1"]])
        XCTAssertFalse(voice.sendText("where is the exit"), "A typed request must not race the reply in progress")
        transport.emit(["type": "response.done", "response": ["id": "r1"]])
        XCTAssertTrue(voice.sendText("where is the exit"))
    }

    func testSendTextIsRejectedWhileIdle() {
        let voice = RealtimeVoiceSession(tokenClient: TypedFakeToken(), audio: TypedFakeAudio(), transportFactory: { TypedFakeTransport() },
                                         configuration: config, speaksLocally: false, requestPermission: { $0(true) })
        XCTAssertFalse(voice.sendText("hello"))
    }

    func testSimulatorPolicyKeepsCaptionsWhenAudioCannotRun() {
        let audio = TypedFakeAudio()
        audio.playError = VoiceAudioError.notRunning
        let (voice, transport) = ready(audio: audio, silentPlaybackFallback: true)
        transport.emit(["type": "response.created", "response": ["id": "r1"]])
        transport.emit(["type": "response.output_audio.delta", "response_id": "r1", "item_id": "i1", "delta": Data([1, 0, 2, 0]).base64EncodedString()])
        XCTAssertTrue(voice.isActive, "A missing audio output must not disconnect the session")
        XCTAssertTrue(voice.audioUnavailable)
        transport.emit(["type": "response.output_audio_transcript.delta", "response_id": "r1", "delta": "I'm here."])
        XCTAssertEqual(voice.caption, "I'm here.")
        transport.emit(["type": "response.done", "response": ["id": "r1"]])
        XCTAssertEqual(voice.phase, .listening)
    }
    func testDevicePolicyStopsBrokenAudioRejectsLateEventsAndReconnects() {
        let token = TypedFakeToken(), transport = TypedFakeTransport(), audio = TypedFakeAudio()
        let voice = RealtimeVoiceSession(tokenClient: token, audio: audio, transportFactory: { transport },
            configuration: config, speaksLocally: false, silentPlaybackFallback: false, requestPermission: { $0(true) })
        defer { voice.disconnect() }
        var actions = 0
        voice.onCommand = { _ in actions += 1; return ["ok": true] }
        func configure() {
            token.complete(.success("ephemeral"))
            transport.emit(["type": "session.created"])
            transport.emit(["type": "session.updated"])
            acknowledgeOpeningGreeting(transport.sent, emit: transport.emit)
        }
        voice.start(); configure()
        XCTAssertTrue(audio.running)
        audio.playError = VoiceAudioError.notRunning
        transport.emit(["type": "response.created", "response": ["id": "broken"]])
        transport.emit(["type": "response.output_audio.delta", "response_id": "broken", "delta": Data([1, 0]).base64EncodedString()])
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertFalse(audio.running)
        XCTAssertFalse(voice.audioUnavailable, "A device failure must not silently switch to simulator captions")
        XCTAssertEqual(voice.errorMessage, "Voice playback stopped. Tap to retry.")
        transport.emit(["type": "response.function_call_arguments.done", "response_id": "broken", "call_id": "late", "name": "start_camera", "arguments": "{}"])
        XCTAssertEqual(actions, 0)
        audio.playError = nil
        voice.resumeAssistant(); configure()
        XCTAssertTrue(audio.running)
        XCTAssertTrue(voice.isActive)
        transport.emit(["type": "response.created", "response": ["id": "recovered"]])
        transport.emit(["type": "response.output_audio.delta", "response_id": "recovered", "delta": Data([1, 0]).base64EncodedString()])
        XCTAssertEqual(voice.phase, .speaking)
        XCTAssertTrue(voice.errorMessage.isEmpty)
    }

}
