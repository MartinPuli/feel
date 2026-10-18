import Foundation

/// Chalk Model Gateway settings, entered once in Assistant settings and kept in Keychain.
struct ChalkConfiguration: Codable, Equatable {
    static let defaultHost = "https://api.chalk.ai"
    static let defaultModel = "openai/gpt-6.1-sol"
    let apiHost: String
    let routerApiKey: String
    let environmentId: String
    let model: String

    var url: URL? {
        guard let url = URL(string: apiHost), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else { return nil }
        return url
    }
    var isValid: Bool {
        url != nil && routerApiKey.count >= 16 && !routerApiKey.contains(where: { $0.isWhitespace })
            && (1...64).contains(environmentId.count) && !model.isEmpty
    }
}

protocol ChalkConfigurationStoring {
    func loadForLaunch() -> ChalkConfiguration?
    func save(_ configuration: ChalkConfiguration) throws
    func clear()
}


struct ChalkConfigurationStore: ChalkConfigurationStoring {
    private let store = KeychainStore<ChalkConfiguration>(service: "org.feel.hackharvard.chalk", account: "gateway")
    func load() -> ChalkConfiguration? { store.load() }
    /// Keychain, or in DEBUG a paired developer launch (`FEEL_PROVISION_CHALK=1` with
    /// `FEEL_CHALK_KEY`, `FEEL_CHALK_ENV` and optional `FEEL_CHALK_HOST` / `FEEL_CHALK_MODEL`),
    /// the same pattern as the voice-service provisioning. Nothing is embedded in the app.
    func loadForLaunch() -> ChalkConfiguration? {
        let process = ProcessInfo.processInfo
        guard !process.arguments.contains("--uitesting") else { return nil }
        #if DEBUG
        if process.environment["FEEL_PROVISION_CHALK"] == "1" {
            return try? Self.provision(environment: process.environment, save: save)
        }
        #endif
        if let saved = load() { return saved }
        return provisionFromBundle()
    }

    /// First launch of a build whose config carried the gateway settings (ios/scripts/supabase_config.sh):
    /// saved to the Keychain once. Forgetting the setup in the app clears it; the next launch seeds it again.
    func provisionFromBundle(_ bundle: Bundle = .main) -> ChalkConfiguration? {
        guard let configuration = Self.configuration(fromInfo: bundle.infoDictionary ?? [:]),
              (try? save(configuration)) != nil else { return nil }
        return configuration
    }

    /// The build-config values, or nil when absent, blank, unexpanded `$(...)` or invalid.
    static func configuration(fromInfo info: [String: Any]) -> ChalkConfiguration? {
        func value(_ name: String) -> String? {
            guard let raw = info[name] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        guard let key = value("FEEL_CHALK_KEY"), let environmentId = value("FEEL_CHALK_ENV") else { return nil }
        let configuration = ChalkConfiguration(apiHost: value("FEEL_CHALK_HOST") ?? ChalkConfiguration.defaultHost, routerApiKey: key,
                                               environmentId: environmentId, model: value("FEEL_CHALK_MODEL") ?? ChalkConfiguration.defaultModel)
        return configuration.isValid ? configuration : nil
    }
    #if DEBUG
    static func provision(environment: [String: String], save: (ChalkConfiguration) throws -> Void) throws -> ChalkConfiguration? {
        guard environment["FEEL_PROVISION_CHALK"] == "1" else { return nil }
        let value = { (name: String) in environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let key = value("FEEL_CHALK_KEY"), let environmentId = value("FEEL_CHALK_ENV") else { throw KeychainStoreError.invalid }
        let configuration = ChalkConfiguration(apiHost: value("FEEL_CHALK_HOST") ?? ChalkConfiguration.defaultHost, routerApiKey: key,
                                               environmentId: environmentId, model: value("FEEL_CHALK_MODEL") ?? ChalkConfiguration.defaultModel)
        guard configuration.isValid else { throw KeychainStoreError.invalid }
        try save(configuration)
        return configuration
    }
    #endif
    func save(_ configuration: ChalkConfiguration) throws {
        guard configuration.isValid else { throw KeychainStoreError.invalid }
        try store.save(configuration)
    }
    func clear() { store.clear() }
}

/// One chat completion in, the reply text out. Stubbed in tests; `ChalkGateway` in the app.
protocol ChatGateway: AnyObject {
    @discardableResult
    func complete(body: Data, timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionTask?
}

enum GatewayError: Error, Equatable { case configuration, http(Int), malformedReply }

/// POST {host}/v1/router/chat/completions with Chalk's two headers. Completion runs on the main queue.
final class ChalkGateway: ChatGateway {
    private let configuration: ChalkConfiguration
    private let session: URLSession
    init(configuration: ChalkConfiguration, session: URLSession = .shared) {
        self.configuration = configuration; self.session = session
    }
    @discardableResult
    func complete(body: Data, timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionTask? {
        guard configuration.isValid, let base = configuration.url else {
            DispatchQueue.main.async { completion(.failure(GatewayError.configuration)) }
            return nil
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/router/chat/completions"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(configuration.routerApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.environmentId, forHTTPHeaderField: "X-Chalk-Env-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<String, Error>
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { result = .failure(GatewayError.http(http.statusCode)) }
            else if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
                    let content = message["content"] as? String { result = .success(content) }
            else { result = .failure(GatewayError.malformedReply) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
}
