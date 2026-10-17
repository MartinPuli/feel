import XCTest
@testable import Lantern

private final class ProviderFakeToken: VoiceTokenFetching {
    private(set) var fetchCount = 0
    private var completion: ((Result<String, Error>) -> Void)?
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void) { fetchCount += 1; self.completion = completion }
    func cancel() { completion = nil }
    func complete(_ result: Result<String, Error>) { completion?(result); completion = nil }
}

private final class ProviderFakeTransport: VoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?
    private(set) var openedURL: URL?
    private(set) var openedToken: String?
    var sent: [[String: Any]] = []
    func open(url: URL, token: String) { openedURL = url; openedToken = token }
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) { sent.append(event); completion(true) }
    func close() {}
    func emit(_ event: [String: Any]) { onEvent?(event) }
    func events(ofType type: String) -> [[String: Any]] { sent.filter { ($0["type"] as? String) == type } }
}

private final class ProviderFakeAudio: VoiceAudioIO {
    var pendingPlayback = false
    var playedMilliseconds = 0
    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws {}
    func play(_ pcm: Data) throws {}
    func interruptPlayback() {}
    func stop() {}
}

final class VoiceProviderTests: XCTestCase {
    private let key = String(repeating: "k", count: 40)

    private func session(_ configuration: VoiceConfiguration) -> (GrokVoiceSession, ProviderFakeToken, ProviderFakeTransport) {
        let token = ProviderFakeToken(), transport = ProviderFakeTransport()
        let voice = GrokVoiceSession(tokenClient: token, audio: ProviderFakeAudio(), transportFactory: { transport },
                                     configuration: configuration, speaksLocally: false, requestPermission: { $0(true) })
        return (voice, token, transport)
    }
    private func ready(_ configuration: VoiceConfiguration) -> (GrokVoiceSession, ProviderFakeTransport) {
        let (voice, token, transport) = session(configuration)
        voice.start()
        if !configuration.usesDirectKey { token.complete(.success("ephemeral")) }
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        return (voice, transport)
    }
    private var grok: VoiceConfiguration { VoiceConfiguration(provider: .grok, endpoint: "https://feel.example/session", accessToken: key) }
    private var openai: VoiceConfiguration { VoiceConfiguration(provider: .openai, endpoint: "", accessToken: key) }

    func testConfigurationValidityPerProvider() {
        XCTAssertTrue(grok.isValid)
        XCTAssertFalse(VoiceConfiguration(provider: .grok, endpoint: "", accessToken: key).isValid, "Grok needs the token service")
        XCTAssertTrue(openai.isValid, "OpenAI may use a direct key with no token service")
        XCTAssertTrue(openai.usesDirectKey)
        XCTAssertTrue(VoiceConfiguration(provider: .openai, endpoint: "https://feel.example/session", accessToken: key).isValid)
        XCTAssertFalse(VoiceConfiguration(provider: .openai, endpoint: "", accessToken: "short").isValid)
    }

    func testOldKeychainRecordDecodesAsGrok() throws {
        let data = Data(#"{"endpoint":"https://feel.example/session","accessToken":"\#(key)"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(VoiceConfiguration.self, from: data).provider, .grok)
    }

    func testOpenAIDirectKeySkipsTokenServiceAndOpensRealtime() {
        let (voice, token, transport) = session(openai)
        voice.start()
        XCTAssertEqual(token.fetchCount, 0)
        XCTAssertEqual(transport.openedURL?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")
        XCTAssertEqual(transport.openedToken, key)
    }

    func testGrokUsesTokenServiceAndXAIRealtime() {
        let (voice, token, transport) = session(grok)
        voice.start()
        XCTAssertEqual(token.fetchCount, 1)
        XCTAssertNil(transport.openedURL)
        token.complete(.success("ephemeral"))
        XCTAssertEqual(transport.openedURL?.absoluteString, "wss://api.x.ai/v1/realtime?model=grok-voice-latest")
        XCTAssertEqual(transport.openedToken, "ephemeral")
    }

    func testSessionUpdateShapeFollowsProvider() throws {
        let (_, grokTransport) = ready(grok)
        let grokSession = try XCTUnwrap(grokTransport.events(ofType: "session.update").first?["session"] as? [String: Any])
        XCTAssertEqual(grokSession["voice"] as? String, "sal")
        XCTAssertNotNil(grokSession["turn_detection"])
        XCTAssertNotNil(grokSession["tools"])

        let (_, openaiTransport) = ready(openai)
        let openaiSession = try XCTUnwrap(openaiTransport.events(ofType: "session.update").first?["session"] as? [String: Any])
        XCTAssertEqual(openaiSession["type"] as? String, "realtime")
        XCTAssertEqual(openaiSession["model"] as? String, "gpt-realtime-2.1")
        XCTAssertNil(openaiSession["voice"])
        XCTAssertNil(openaiSession["turn_detection"])
        let audio = try XCTUnwrap(openaiSession["audio"] as? [String: Any])
        XCTAssertEqual(((audio["output"] as? [String: Any])?["voice"]) as? String, "marin")
        XCTAssertEqual((((audio["input"] as? [String: Any])?["turn_detection"]) as? [String: Any])?["type"] as? String, "server_vad")
        XCTAssertEqual(openaiSession["output_modalities"] as? [String], ["audio"])
        XCTAssertNotNil(openaiSession["tools"])
        XCTAssertEqual(openaiSession["instructions"] as? String, VoiceCommand.instructions)
    }

    /// The readiness line ("I'm here.") is the first announcement every session makes.
    func testReadinessAnnouncementUsesProviderShape() throws {
        let (_, grokTransport) = ready(grok)
        let item = try XCTUnwrap(grokTransport.events(ofType: "conversation.item.create").first?["item"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "force_message")
        XCTAssertEqual(((item["content"] as? [[String: Any]])?.first?["text"]) as? String, "I'm here.")

        let (_, openaiTransport) = ready(openai)
        XCTAssertTrue(openaiTransport.events(ofType: "conversation.item.create").isEmpty)
        let response = try XCTUnwrap(openaiTransport.events(ofType: "response.create").first?["response"] as? [String: Any])
        XCTAssertTrue((response["instructions"] as? String ?? "").contains("I'm here."))
        XCTAssertEqual(response["output_modalities"] as? [String], ["audio"])
    }

    func testSendTextCreatesUserItemThenResponse() throws {
        let (voice, transport) = ready(openai)
        transport.sent.removeAll()
        XCTAssertTrue(voice.sendText("where is the exit"))
        let types = transport.sent.compactMap { $0["type"] as? String }
        XCTAssertEqual(types, ["conversation.item.create", "response.create"])
        let item = try XCTUnwrap(transport.sent[0]["item"] as? [String: Any])
        XCTAssertEqual(item["role"] as? String, "user")
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content.first?["text"] as? String, "where is the exit")
        XCTAssertFalse(voice.sendText("   "), "Blank text is not sent")
        XCTAssertFalse(voice.sendText(String(repeating: "x", count: 161)), "Overlong text is not sent")
    }

    func testSendTextIsRejectedWhileIdle() {
        let (voice, _, transport) = session(openai)
        XCTAssertFalse(voice.sendText("hello"))
        XCTAssertTrue(transport.sent.isEmpty)
    }
}
