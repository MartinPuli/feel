import Foundation
import Security

/// Which realtime speech service the assistant talks to. Both speak the same event protocol.
enum VoiceProvider: String, Codable, CaseIterable {
    case grok, openai

    var displayName: String { self == .grok ? "Grok" : "OpenAI" }
    var realtimeURL: URL {
        switch self {
        case .grok: return URL(string: "wss://api.x.ai/v1/realtime?model=grok-voice-latest")!
        case .openai: return URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")!
        }
    }
    /// The session.update payload. xAI keeps the older top-level shape; OpenAI's GA API nests audio settings.
    func sessionUpdate(instructions: String, tools: [[String: Any]]) -> [String: Any] {
        let format: [String: Any] = ["type": "audio/pcm", "rate": 24000]
        switch self {
        case .grok:
            return ["voice": "sal", "instructions": instructions, "turn_detection": ["type": "server_vad"], "tools": tools,
                    "audio": ["input": ["format": format], "output": ["format": format]]]
        case .openai:
            return ["type": "realtime", "model": "gpt-realtime-2.1", "output_modalities": ["audio"], "instructions": instructions, "tools": tools,
                    "audio": ["input": ["format": format, "turn_detection": ["type": "server_vad"]],
                              "output": ["format": format, "voice": "marin"]]]
        }
    }
    /// Speak exact app text without a user turn.
    func announcement(_ text: String) -> [String: Any] {
        switch self {
        case .grok:
            return ["type": "conversation.item.create", "item": ["type": "force_message", "role": "assistant",
                     "content": [["type": "output_text", "text": text]]]]
        case .openai:
            return ["type": "response.create", "response": ["instructions": "Say exactly this, and nothing else: \(text)",
                                                             "output_modalities": ["audio"]]]
        }
    }
}

struct VoiceConfiguration: Codable, Equatable {
    var provider: VoiceProvider = .grok
    let endpoint: String
    let accessToken: String

    init(provider: VoiceProvider = .grok, endpoint: String, accessToken: String) {
        self.provider = provider; self.endpoint = endpoint; self.accessToken = accessToken
    }
    // Records saved before providers existed have no `provider`; they are Grok.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(VoiceProvider.self, forKey: .provider) ?? .grok
        endpoint = try values.decode(String.self, forKey: .endpoint)
        accessToken = try values.decode(String.self, forKey: .accessToken)
    }

    var url: URL? {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else { return nil }
        return url
    }
    /// OpenAI can be reached with the API key itself (no token service). Grok always needs the service,
    /// and the service credential must never be a raw provider key.
    var usesDirectKey: Bool { provider == .openai && endpoint.isEmpty }
    private var tokenLooksValid: Bool {
        (32...4096).contains(accessToken.utf8.count) && accessToken.utf8.allSatisfy { (33...126).contains($0) }
    }
    var isValid: Bool {
        guard tokenLooksValid else { return false }
        if usesDirectKey { return true }
        return url != nil && !accessToken.hasPrefix("grok_") && !accessToken.hasPrefix("xai-") && !accessToken.hasPrefix("sk-")
    }
}

struct VoiceConfigurationStore {
    private let store = KeychainStore<VoiceConfiguration>(service: "org.feel.hackharvard.voice", account: "token-service")
    func loadForLaunch() -> VoiceConfiguration? {
        let process = ProcessInfo.processInfo
        guard !process.arguments.contains("--uitesting") else { return nil }
        #if DEBUG
        if process.environment["FEEL_PROVISION_VOICE"] == "1" {
            // A failed explicit setup must not silently reconnect to an older service.
            // Returning nil keeps the normal spoken setup recovery available.
            return try? Self.provision(environment: process.environment, arguments: process.arguments, save: save)
        }
        #endif
        return load()
    }

    #if DEBUG
    /// A paired developer launch can provision Keychain without embedding credentials in the app.
    /// Only the separate token-service credential belongs here, never the provider API key.
    static func provision(environment: [String: String], arguments: [String],
                          save: (VoiceConfiguration) throws -> Void) throws -> VoiceConfiguration? {
        guard !arguments.contains("--uitesting"), environment["FEEL_PROVISION_VOICE"] == "1" else { return nil }
        let value = { (name: String) in environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let token = value("FEEL_VOICE_ACCESS_TOKEN") else { throw StoreError.invalid }
        let provider = VoiceProvider(rawValue: value("FEEL_VOICE_PROVIDER") ?? "grok") ?? .grok
        let configuration = VoiceConfiguration(provider: provider, endpoint: value("FEEL_VOICE_ENDPOINT") ?? "", accessToken: token)
        guard configuration.isValid else { throw StoreError.invalid }
        try save(configuration)
        return configuration
    }
    #endif

    func load() -> VoiceConfiguration? { store.load() }
    func save(_ configuration: VoiceConfiguration) throws {
        guard configuration.isValid else { throw StoreError.invalid }
        do { try store.save(configuration) } catch { throw StoreError.unavailable }
    }
    func clear() { store.clear() }
    enum StoreError: Error { case invalid, unavailable }
}

protocol VoiceTokenFetching: AnyObject {
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

/// Refuse redirects so a service credential cannot travel to another host.
final class VoiceTokenClient: NSObject, VoiceTokenFetching, URLSessionTaskDelegate {
    private var task: URLSessionDataTask?
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void) {
        guard configuration.isValid, let url = configuration.url else { completion(.failure(TokenError.configuration)); return }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: request) { data, response, error in
            let result: Result<String, Error>
            if error != nil { result = .failure(TokenError.unavailable) }
            else if let http = response as? HTTPURLResponse, http.statusCode == 200,
                    let data, data.count < 16_384,
                    let secret = try? JSONDecoder().decode(ClientSecret.self, from: data),
                    !secret.value.isEmpty, secret.value.count < 8192,
                    secret.expires_at > Date().timeIntervalSince1970 + 5 {
                result = .success(secret.value)
            } else { result = .failure(TokenError.unavailable) }
            DispatchQueue.main.async { completion(result) }
        }
        task?.resume()
    }
    func cancel() { task?.cancel(); task = nil }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    private struct ClientSecret: Decodable { let value: String; let expires_at: TimeInterval }
    enum TokenError: Error { case configuration, unavailable }
}
