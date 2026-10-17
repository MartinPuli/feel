import Foundation
import Combine
import Security

struct ChalkPlace: Codable, Equatable { let id: String; let name: String }
struct ChalkContext: Codable, Equatable {
    let places: [ChalkPlace]
    let trackingValid: Bool
    let restoring: Bool
    let mode: String
    let hasReturnPoint: Bool
}
struct ChalkRequest: Encodable {
    let requestId: String
    let sessionId: String
    let utterance: String
    let language: String
    let context: ChalkContext
    let consent: Bool
}
struct ChalkDecision: Decodable {
    enum Action: String, Decodable { case recall, remember, listPlaces = "list_places", returnToPoint = "return_to_point", clarify, reject, stop }
    let action: Action
    let placeId: String?
    let name: String?
    let message: String
}
struct ChalkResponse: Decodable {
    let requestId: String
    let sessionId: String
    let decision: ChalkDecision
    let traceId: String
    let latencyMs: Double
    func validate(for request: ChalkRequest) throws {
        guard requestId == request.requestId, sessionId == request.sessionId,
              !traceId.isEmpty, traceId.count <= 128, latencyMs.isFinite, latencyMs >= 0,
              latencyMs <= 120_000, decision.message.count <= 500, !decision.message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ChalkError.invalidResponse }
        switch decision.action {
        case .recall:
            guard let id=decision.placeId, request.context.places.contains(where: { $0.id == id }), decision.name == nil else { throw ChalkError.invalidResponse }
        case .remember:
            guard decision.placeId == nil, let name=decision.name,
                  !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count <= 40,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ChalkError.invalidResponse }
        default:
            guard decision.placeId == nil, decision.name == nil else { throw ChalkError.invalidResponse }
        }
    }
}
enum ChalkError: Error, LocalizedError {
    case configuration, invalidResponse, service
    var errorDescription: String? {
        switch self {
        case .configuration: return "Enable sharing and configure an HTTPS FEEL server with an app token."
        case .invalidResponse: return "The server returned an invalid action. No action was applied."
        case .service: return "The FEEL server could not complete the request. Try again."
        }
    }
}
/// Refuse redirects so a configured service cannot forward the bearer credential elsewhere.
private final class ChalkRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class ChalkTransport {
    private let session: URLSession
    init(session: URLSession? = nil) {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=8
        configuration.timeoutIntervalForResource=10
        self.session=session ?? URLSession(configuration:configuration,delegate:ChalkRedirectGuard(),delegateQueue:nil)
    }
    func post<T: Encodable>(_ body: T, path: String, endpoint: String, token: String) async throws -> Data {
        guard var parts=URLComponents(string:endpoint), parts.scheme == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", !token.isEmpty, token.count <= 4096,
              !token.contains("\n"), !token.contains("\r") else { throw ChalkError.configuration }
        parts.path=path
        guard let url=parts.url else { throw ChalkError.configuration }
        var request=URLRequest(url:url)
        request.httpMethod="POST"; request.timeoutInterval=8
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let encoder=JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody=try encoder.encode(body)
        let (data,response)=try await session.data(for:request)
        try Task.checkCancellation()
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),data.count <= 65_536 else { throw ChalkError.service }
        return data
    }
    func interpret(_ request: ChalkRequest, endpoint: String, token: String) async throws -> ChalkResponse {
        let data=try await post(request,path:"/v1/interpret",endpoint:endpoint,token:token)
        let decoder=JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response=try decoder.decode(ChalkResponse.self,from:data)
        try response.validate(for:request)
        return response
    }
}
/// App bearer tokens stay in the device Keychain, never UserDefaults or source control.
enum ChalkTokenStore {
    private static let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:"org.feel.chalk", kSecAttrAccount as String:"app-token"]
    static func read() -> String {
        var request=query; request[kSecReturnData as String]=true; request[kSecMatchLimit as String]=kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary,&item) == errSecSuccess,let data=item as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
    static func write(_ token: String) -> Bool {
        if token.isEmpty { let result=SecItemDelete(query as CFDictionary); return result == errSecSuccess || result == errSecItemNotFound }
        let values: [String:Any] = [kSecValueData as String:Data(token.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result=SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if result == errSecItemNotFound { return SecItemAdd(query.merging(values) { _,new in new } as CFDictionary,nil) == errSecSuccess }
        return result == errSecSuccess
    }
}
