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
    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws {}
    func play(_ pcm: Data) throws { if let playError { throw playError } }
    func interruptPlayback() {}
    func stop() {}
}

/// Typed requests take the speech path, and a missing sound output must not end the session.
final class TypedRequestTests: XCTestCase {
    private let config = VoiceConfiguration(endpoint: "https://voice.example/session", accessToken: String(repeating: "a", count: 32))

    private func ready(audio: TypedFakeAudio = TypedFakeAudio()) -> (RealtimeVoiceSession, TypedFakeTransport) {
        let token = TypedFakeToken(), transport = TypedFakeTransport()
        let voice = RealtimeVoiceSession(tokenClient: token, audio: audio, transportFactory: { transport },
                                         configuration: config, speaksLocally: false, requestPermission: { $0(true) })
        voice.start(); token.complete(.success("ephemeral"))
        transport.emit(["type": "session.created"]); transport.emit(["type": "session.updated"])
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

    func testSendTextIsRejectedWhileIdle() {
        let voice = RealtimeVoiceSession(tokenClient: TypedFakeToken(), audio: TypedFakeAudio(), transportFactory: { TypedFakeTransport() },
                                         configuration: config, speaksLocally: false, requestPermission: { $0(true) })
        XCTAssertFalse(voice.sendText("hello"))
    }

    func testAudioNotRunningKeepsSessionAliveWithoutSound() {
        let audio = TypedFakeAudio()
        audio.playError = VoiceAudioError.notRunning
        let (voice, transport) = ready(audio: audio)
        transport.emit(["type": "response.created", "response": ["id": "r1"]])
        transport.emit(["type": "response.output_audio.delta", "response_id": "r1", "item_id": "i1", "delta": Data([1, 0, 2, 0]).base64EncodedString()])
        XCTAssertTrue(voice.isActive, "A missing audio output must not disconnect the session")
        XCTAssertTrue(voice.audioUnavailable)
        transport.emit(["type": "response.output_audio_transcript.delta", "response_id": "r1", "delta": "I'm here."])
        XCTAssertEqual(voice.caption, "I'm here.")
        transport.emit(["type": "response.done", "response": ["id": "r1"]])
        XCTAssertEqual(voice.phase, .listening)
    }
}
