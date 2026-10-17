import Foundation
import Security

struct VoiceConfiguration: Codable, Equatable {
    let endpoint: String
    let accessToken: String

    var url: URL? {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else { return nil }
        return url
    }
    var isValid: Bool {
        url != nil && (32...4096).contains(accessToken.utf8.count)
            && accessToken.utf8.allSatisfy { (33...126).contains($0) }
            && !accessToken.hasPrefix("grok_") && !accessToken.hasPrefix("xai-")
    }
}

struct VoiceConfigurationStore {
    private let service = "org.feel.hackharvard.voice"
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
