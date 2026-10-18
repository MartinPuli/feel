import Foundation
import Security

struct VoiceConfiguration: Codable, Equatable {
    enum AuthMode: String, Codable { case demo, supabase }
    let endpoint: String
    /// Demo provisioning code only. Production configurations must leave this empty.
    let accessToken: String
    let authMode: AuthMode

    init(endpoint: String, accessToken: String = "", authMode: AuthMode = .demo) {
        self.endpoint = endpoint; self.accessToken = accessToken; self.authMode = authMode
    }
    private enum CodingKeys: String, CodingKey { case endpoint, accessToken, authMode }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try values.decode(String.self, forKey: .endpoint)
        accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        authMode = try values.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .demo
    }
    var url: URL? {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else { return nil }
        return url
    }
    var isValid: Bool {
        guard url != nil else { return false }
        if authMode == .supabase { return accessToken.isEmpty }
        return (32...4096).contains(accessToken.utf8.count)
            && accessToken.utf8.allSatisfy { (33...126).contains($0) }
            && !accessToken.hasPrefix("grok_") && !accessToken.hasPrefix("xai-") && !accessToken.hasPrefix("sk-")
    }
}

/// Local preflight only: the backend verifies the JWT against Supabase before issuing a provider credential.
/// A stable account/session identity allows ordinary token refresh without interrupting an existing voice session.
enum VoiceUserAuthentication {
    struct Identity: Equatable {
        let user: String
        let session: String?
        // Older JWTs cannot identify a login session. Keep those bound to the original bearer.
        fileprivate let legacyBearer: String?
    }
    static func identity(_ tokens: AuthSessionTokens?, now: Date = Date()) -> Identity? {
        guard let token = tokens?.accessToken, token.utf8.count <= 16_384,
              let claims = SupabaseConfiguration.claims(of: token),
              let user = claims["sub"] as? String, UUID(uuidString: user) != nil,
              claims["role"] as? String == "authenticated",
              let expiry = claims["exp"] as? NSNumber, CFGetTypeID(expiry) != CFBooleanGetTypeID(),
              expiry.doubleValue.isFinite, expiry.doubleValue > now.timeIntervalSince1970 else { return nil }
        if let anonymous = claims["is_anonymous"] {
            guard let value = anonymous as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID(), !value.boolValue else { return nil }
        }
        let session = claims["session_id"] as? String
        if claims["session_id"] != nil {
            guard let session, UUID(uuidString: session) != nil else { return nil }
        }
        return Identity(user: user, session: session, legacyBearer: session == nil ? token : nil)
    }
}

struct VoiceConfigurationStore {
    private let service = "org.feel.hackharvard.voice"
    func loadForLaunch() -> VoiceConfiguration? {
        let process = ProcessInfo.processInfo
        guard !process.arguments.contains("--uitesting") else { return nil }
        let info = Bundle.main.infoDictionary ?? [:]
        // A production build is authoritative even if setup is missing or invalid: never recover an old demo code.
        if Self.hasAuthoritativeAuthMode(info) { return Self.configuration(fromInfo: info) }
        #if DEBUG
        if process.environment["FEEL_PROVISION_VOICE"] == "1" {
            // A failed explicit setup must not silently reconnect to an older service.
            // Returning nil keeps the normal spoken setup recovery available.
            return try? Self.provision(environment: process.environment, arguments: process.arguments, save: save)
        }
        #endif
        if let saved = load() { return saved }
        return provisionFromBundle()
    }

    /// First launch of a build whose config carried the voice service (ios/scripts/supabase_config.sh):
    /// the values are saved to the Keychain once, so the assistant needs no typing. Forgetting the
    /// connection in the app clears the Keychain, and the next launch seeds it again from the same build.
    func provisionFromBundle(_ bundle: Bundle = .main) -> VoiceConfiguration? {
        guard let configuration = Self.configuration(fromInfo: bundle.infoDictionary ?? [:]),
              (try? save(configuration)) != nil else { return nil }
        return configuration
    }

    /// The build-config values, or nil when absent, blank, left as unexpanded `$(...)`, or not a valid pair.
    static func hasAuthoritativeAuthMode(_ info: [String: Any]) -> Bool {
        guard let raw = info["FEEL_VOICE_AUTH_MODE"] as? String else { return false }
        let mode = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !mode.isEmpty && !mode.hasPrefix("$(") && mode != "demo"
    }
    static func launchConfiguration(info: [String: Any], saved: VoiceConfiguration?) -> VoiceConfiguration? {
        if hasAuthoritativeAuthMode(info) { return configuration(fromInfo: info) }
        if let saved, saved.isValid { return saved }
        return configuration(fromInfo: info)
    }
    static func configuration(fromInfo info: [String: Any]) -> VoiceConfiguration? {
        guard let endpoint = info["FEEL_VOICE_ENDPOINT"] as? String,
              !endpoint.isEmpty, !endpoint.hasPrefix("$(") else { return nil }
        let raw = (info["FEEL_VOICE_AUTH_MODE"] as? String ?? "demo").trimmingCharacters(in: .whitespacesAndNewlines)
        let mode: VoiceConfiguration.AuthMode
        if raw.isEmpty || raw.hasPrefix("$(") { mode = .demo }
        else if let value = VoiceConfiguration.AuthMode(rawValue: raw) { mode = value }
        else { return nil }
        if mode == .supabase {
            let config = VoiceConfiguration(endpoint: endpoint, authMode: .supabase)
            return config.isValid ? config : nil
        }
        guard let token = info["FEEL_VOICE_ACCESS_TOKEN"] as? String, !token.isEmpty, !token.hasPrefix("$(") else { return nil }
        let config = VoiceConfiguration(endpoint: endpoint, accessToken: token)
        return config.isValid ? config : nil
    }

    #if DEBUG
    /// A paired developer launch can provision Keychain without embedding credentials in the app.
    /// Only the separate token-service credential belongs here, never the provider API key.
    static func provision(environment: [String: String], arguments: [String],
                          save: (VoiceConfiguration) throws -> Void) throws -> VoiceConfiguration? {
        guard !arguments.contains("--uitesting"), environment["FEEL_PROVISION_VOICE"] == "1" else { return nil }
        guard let endpoint = environment["FEEL_VOICE_ENDPOINT"],
              let token = environment["FEEL_VOICE_ACCESS_TOKEN"] else {
            throw StoreError.invalid
        }
        let configuration = VoiceConfiguration(endpoint: endpoint, accessToken: token)
        guard configuration.isValid else { throw StoreError.invalid }
        try save(configuration)
        return configuration
    }
    #endif

    func load() -> VoiceConfiguration? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "token-service",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(VoiceConfiguration.self, from: data)
    }
    func save(_ configuration: VoiceConfiguration) throws {
        guard configuration.isValid else { throw StoreError.invalid }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "token-service"]
        let data = try JSONEncoder().encode(configuration)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailable }
        } else if update != errSecSuccess { throw StoreError.unavailable }
    }
    func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "token-service"] as CFDictionary)
    }
    enum StoreError: Error { case invalid, unavailable }
}

protocol VoiceTokenFetching: AnyObject {
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

/// Refuse redirects so a service credential cannot travel to another host.
final class VoiceTokenClient: NSObject, VoiceTokenFetching, URLSessionTaskDelegate {
    private var task: URLSessionDataTask?
    private var generation = UUID()
    private let store: KeychainStore<AuthSessionTokens>
    private let injected: URLSession?
    private let now: () -> Date
    private lazy var session = injected ?? URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    init(store: KeychainStore<AuthSessionTokens> = AuthModel.sessionStore, session: URLSession? = nil, now: @escaping () -> Date = Date.init) {
        self.store = store; self.injected = session; self.now = now
    }
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void) {
        cancel()
        guard configuration.isValid, let url = configuration.url else { completion(.failure(TokenError.configuration)); return }
        let tokens = configuration.authMode == .supabase ? store.load() : nil
        let identity = VoiceUserAuthentication.identity(tokens, now: now())
        let bearer: String
        if configuration.authMode == .supabase {
            guard let tokens, identity != nil else { completion(.failure(TokenError.authentication)); return }
            bearer = tokens.accessToken
        } else { bearer = configuration.accessToken }
        let id = generation
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { completion(.failure(TokenError.cancelled)); return }
                guard self.generation == id else { completion(.failure(TokenError.cancelled)); return }
                if configuration.authMode == .supabase {
                    let current = self.store.load()
                    // A refresh may rotate the bearer while this request is in flight. Accept it only
                    // within the same valid login session; legacy tokens without a session ID must match exactly.
                    guard let identity, let currentIdentity = VoiceUserAuthentication.identity(current, now: self.now()),
                          identity == currentIdentity,
                          identity.session != nil || current == tokens else {
                        completion(.failure(TokenError.authentication)); return
                    }
                }
                let result: Result<String, Error>
                if error != nil { result = .failure(TokenError.unavailable) }
                else if let http = response as? HTTPURLResponse, [401,403].contains(http.statusCode) {
                    result = .failure(configuration.authMode == .supabase ? TokenError.authentication : TokenError.unavailable)
                }
                else if let http = response as? HTTPURLResponse, http.statusCode == 200,
                        let data, data.count < 16_384,
                        let secret = try? JSONDecoder().decode(ClientSecret.self, from: data),
                        !secret.value.isEmpty, secret.value.count < 8192,
                        secret.expires_at > self.now().timeIntervalSince1970 + 5 {
                    result = .success(secret.value)
                } else { result = .failure(TokenError.unavailable) }
                completion(result)
            }
        }
        task?.resume()
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    private struct ClientSecret: Decodable { let value: String; let expires_at: TimeInterval }
    enum TokenError: Error, Equatable { case configuration, unavailable, authentication, cancelled }
}
