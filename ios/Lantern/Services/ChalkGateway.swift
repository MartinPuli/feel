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

struct ChalkConfigurationStore {
    private let store = KeychainStore<ChalkConfiguration>(service: "org.feel.hackharvard.chalk", account: "gateway")
    func load() -> ChalkConfiguration? { store.load() }
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
