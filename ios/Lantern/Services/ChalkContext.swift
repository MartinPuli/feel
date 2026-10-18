import Foundation
import FeelCore

/// The app sends only allowlisted operations to its authenticated proxy. Chalk service credentials never ship.
enum ChalkContextRequest: Equatable {
    case lastSeen(String)
    case roomStructure(venue: String, tag: String)
    case roomAnchors(venue: String, tag: String)

    var body: [String: String]? {
        switch self {
        case .lastSeen(let object):
            guard !object.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            let normalized = RoomAnchor.normalized(object)
            guard (1...80).contains(normalized.count), !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return ["operation": "last_seen", "object": normalized]
        case .roomStructure(let venue, let tag), .roomAnchors(let venue, let tag):
            guard RoomMemoryStore.isTagId(venue), RoomMemoryStore.isTagId(tag) else { return nil }
            let operation: String
            if case .roomStructure = self { operation = "room_structure" } else { operation = "room_anchors" }
            return ["operation": operation, "venue_id": venue, "tag_id": tag]
        }
    }
    var outputs: Set<String> {
        switch self {
        case .lastSeen: return ["object_history.spoken"]
        case .roomStructure: return ["room_memory.structure", "room_memory.structure_visits"]
        case .roomAnchors: return ["room_memory.targets"]
        }
    }
}

enum ChalkQueryError: Error, Equatable { case access, cancelled, network, http(Int), malformedReply, tooLarge }

protocol ChalkQuerying: AnyObject {
    var isEnabled: Bool { get }
    /// An opaque local generation, never a token or user identifier.
    var sessionIdentity: UUID? { get }
    func setEnabled(_ enabled: Bool)
    func cancelAll()
    func query(_ operation: ChalkContextRequest, completion: @escaping (Result<[String: Any], ChalkQueryError>) -> Void)
}

/// Explicit opt-in, existing Keychain sign-in, strict HTTPS endpoint, no refresh/credential copying or redirects.
/// All state and callbacks belong to the main thread, like the coordinator that owns this service.
final class ChalkQueryClient: ChalkQuerying {
    static let enabledKey = "feel.contextReadsEnabled"
    static let timeout: TimeInterval = 12
    static let maximumResponseBytes = 1_048_576
    private let endpoint: URL
    private let store: KeychainStore<AuthSessionTokens>
    private let defaults: UserDefaults
    private let configuration: URLSessionConfiguration
    private let now: () -> Date
    private var observedTokens: AuthSessionTokens?
    private var generation = UUID()
    private var identityGeneration = UUID()
    private var requests: [UUID: BoundedContextRequest] = [:]

    init?(endpoint: String, store: KeychainStore<AuthSessionTokens>, defaults: UserDefaults = .standard,
          configuration: URLSessionConfiguration = .ephemeral, now: @escaping () -> Date = Date.init) {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !endpoint.contains("$(") else { return nil }
        self.endpoint = url; self.store = store; self.defaults = defaults; self.configuration = configuration; self.now = now
    }
    static func forLaunch() -> ChalkQueryClient? {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting"),
              let endpoint = Bundle.main.object(forInfoDictionaryKey: "FEEL_CONTEXT_URL") as? String else { return nil }
        return ChalkQueryClient(endpoint: endpoint, store: AuthModel.sessionStore)
    }
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        identityGeneration = UUID(); cancelAll()
    }
    func cancelAll() {
        generation = UUID()
        let pending = Array(requests.values); requests.removeAll()
        pending.forEach { $0.cancel() }
    }
    private func currentTokens() -> AuthSessionTokens? {
        let tokens = store.load()
        if tokens != observedTokens { observedTokens = tokens; identityGeneration = UUID(); cancelAll() }
        guard isEnabled, let tokens,
              let claims = SupabaseConfiguration.claims(of: tokens.accessToken),
              let subject = claims["sub"] as? String, UUID(uuidString: subject) != nil,
              claims["role"] as? String == "authenticated",
              let expiry = claims["exp"] as? NSNumber, CFGetTypeID(expiry) != CFBooleanGetTypeID(),
              expiry.doubleValue > now().timeIntervalSince1970 else { return nil }
        return tokens
    }
    var sessionIdentity: UUID? { currentTokens() == nil ? nil : identityGeneration }

    func query(_ operation: ChalkContextRequest, completion: @escaping (Result<[String: Any], ChalkQueryError>) -> Void) {
        guard let tokens = currentTokens(), let body = operation.body,
              let encoded = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { completion(.failure(.access)); return }
        let owner = generation, id = UUID()
        var request = URLRequest(url: endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"; request.httpBody = encoded
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let pending = BoundedContextRequest(configuration: configuration) { [weak self] result in
            guard let self else { completion(.failure(.cancelled)); return }
            self.requests.removeValue(forKey: id)
            guard self.currentTokens() == tokens, self.generation == owner else { completion(.failure(.cancelled)); return }
            completion(result.flatMap { Self.parse($0, outputs: operation.outputs) })
        }
        requests[id] = pending
        pending.start(request)
    }
    static func parse(_ data: Data, outputs: Set<String>) -> Result<[String: Any], ChalkQueryError> {
        guard data.count <= maximumResponseBytes else { return .failure(.tooLarge) }
        guard let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(envelope.keys) == ["values"], let values = envelope["values"] as? [String: Any],
              Set(values.keys) == outputs else { return .failure(.malformedReply) }
        return .success(values)
    }
}

/// Streams a bounded body on the main delegate queue. A missing Content-Length cannot bypass the byte limit.
private final class BoundedContextRequest: NSObject, URLSessionDataDelegate {
    private let configuration: URLSessionConfiguration
    private var completion: ((Result<Data, ChalkQueryError>) -> Void)?
    private var session: URLSession?
    private var data = Data()
    init(configuration: URLSessionConfiguration, completion: @escaping (Result<Data, ChalkQueryError>) -> Void) {
        self.configuration = configuration.copy() as! URLSessionConfiguration; self.completion = completion
        self.configuration.timeoutIntervalForRequest = ChalkQueryClient.timeout
        self.configuration.timeoutIntervalForResource = ChalkQueryClient.timeout
        self.configuration.urlCache = nil; self.configuration.httpCookieStorage = nil
    }
    func start(_ request: URLRequest) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session; session.dataTask(with: request).resume()
    }
    func cancel() { finish(.failure(.cancelled)) }
    private func finish(_ result: Result<Data, ChalkQueryError>) {
        guard let callback = completion else { return }
        completion = nil; session?.invalidateAndCancel(); session = nil; data.removeAll()
        callback(result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); finish(.failure(.network)); return }
        guard (200..<300).contains(http.statusCode) else { completionHandler(.cancel); finish(.failure(.http(http.statusCode))); return }
        guard response.expectedContentLength <= ChalkQueryClient.maximumResponseBytes else { completionHandler(.cancel); finish(.failure(.tooLarge)); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard completion != nil else { return }
        guard bytes.count <= ChalkQueryClient.maximumResponseBytes - data.count else { finish(.failure(.tooLarge)); return }
        data.append(bytes)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error == nil ? .success(data) : .failure(.network))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(.http(response.statusCode)))
    }
}

/// Strict decoding of the three public proxy operations. Values are past records, never live detections.
enum ChalkMemory {
    static func lastSeen(_ client: ChalkQuerying, object: String, completion: @escaping (Result<String, ChalkQueryError>) -> Void) {
        client.query(.lastSeen(object)) { result in
            completion(result.flatMap { values in
                guard let line = values["object_history.spoken"] as? String, (1...1000).contains(line.count),
                      !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .failure(.malformedReply) }
                return .success(line)
            })
        }
    }
    static func roomStructure(_ client: ChalkQuerying, venueId: String, tagId: String,
                              completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void) {
        client.query(.roomStructure(venue: venueId, tag: tagId)) { result in
            completion(result.flatMap { values in
                guard let count = number(values["room_memory.structure_visits"]), count >= 0, count <= 50, count == count.rounded() else { return .failure(.malformedReply) }
                if values["room_memory.structure"] is NSNull { return .success((nil, Int(count))) }
                guard count > 0, let text = values["room_memory.structure"] as? String, let map = roomMap(fromJSON: text) else { return .failure(.malformedReply) }
                return .success((map, Int(count)))
            })
        }
    }
    static func roomAnchors(_ client: ChalkQuerying, venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void) {
        client.query(.roomAnchors(venue: venueId, tag: tagId)) { result in
            completion(result.flatMap { values in
                guard let text = values["room_memory.targets"] as? String, let anchors = anchors(fromJSON: text) else { return .failure(.malformedReply) }
                return .success(anchors)
            })
        }
    }
    static func roomMap(fromJSON text: String) -> RoomMap? {
        guard text.utf8.count <= ChalkQueryClient.maximumResponseBytes,
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], number(object["schema"]) == 1,
              let size = number(object["cell_size"]), size >= 0.01, size <= 1,
              let x = number(object["origin_x"]), let y = number(object["origin_y"]),
              let width = number(object["width"]), let height = number(object["height"]),
              width >= 1, height >= 1, width <= Double(RoomMap.maxSide), height <= Double(RoomMap.maxSide),
              width == width.rounded(), height == height.rounded(), width * height <= Double(RoomMap.maxCells),
              let cells = object["cells"] as? String else { return nil }
        return RoomMap(cellSize: size, originX: x, originY: y, width: Int(width), height: Int(height), encoded: cells)
    }
    static func anchors(fromJSON text: String) -> [RoomAnchor]? {
        guard text.utf8.count <= ChalkQueryClient.maximumResponseBytes,
              let items = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]], items.count <= 200 else { return nil }
        var result: [RoomAnchor] = []
        for item in items {
            guard let label = item["label"] as? String, (1...80).contains(label.count),
                  !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let x = number(item["x"]), let y = number(item["y"]), let z = number(item["z"]),
                  let timestamp = item["last_seen_at"] as? String,
                  let date = withFraction.date(from: timestamp) ?? whole.date(from: timestamp) else { return nil }
            let anchor = RoomAnchor(label: RoomAnchor.normalized(label), position: Vector3(x,y,z), confidence: 0.5, seenAt: date)
            guard anchor.isUsable else { return nil }
            result.append(anchor)
        }
        return result
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }; return n.doubleValue
    }
    private static let withFraction: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let whole = ISO8601DateFormatter()
}
