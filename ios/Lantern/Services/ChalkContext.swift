import Foundation
import FeelCore

/// The read side of the shared memory: what Chalk merged from every phone's rows comes back to this one through
/// Chalk's online queries (chalk/feel_context, named queries `last_seen`, `room_structure` and `room_anchors`). The
/// phone never holds the Chalk client secret: it ships a short-lived query token minted on the Mac
/// (`python -m feel_chalk.query_token`, copied into the git-ignored build config by `ios/scripts/supabase_config.sh`),
/// the engine host that token's grant named, and the environment and client ids the engine wants as headers. When
/// the token has expired, or the build carries none, every query fails with `.access` and the phone's own stores
/// stay the memory. Nothing read here reaches the pins, and a remembered place is always spoken as a past sighting.
struct ChalkQueryAccess: Equatable {
    /// The environment's own engine, from the token grant; api.chalk.ai only answers its version record to a query.
    let engine: URL
    let environmentId: String
    /// The `X-Chalk-Client-Id` header; an id, not a secret. Optional because a token minted another way may lack one.
    let clientId: String?
    /// The bearer token; a JWT whose `exp` the phone reads to skip a query it knows would be refused.
    let token: String

    init?(engine: String?, environmentId: String?, clientId: String?, token: String?) {
        guard let engine = engine?.trimmingCharacters(in: .whitespaces), let url = URL(string: engine), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let environmentId = environmentId?.trimmingCharacters(in: .whitespaces), (1...64).contains(environmentId.count),
              let token = token?.trimmingCharacters(in: .whitespaces), token.count >= 16, !token.contains(where: { $0.isWhitespace }) else { return nil }
        let clientId = clientId?.trimmingCharacters(in: .whitespaces)
        self.engine = url; self.environmentId = environmentId; self.clientId = (clientId?.isEmpty ?? true) ? nil : clientId; self.token = token
    }

    /// `FEEL_CHALK_QUERY_ENGINE`, `FEEL_CHALK_QUERY_TOKEN`, `FEEL_CHALK_CLIENT_ID` and the gateway's `FEEL_CHALK_ENV`, copied into
    /// Info.plist from the build config; absent, blank or unexpanded `$(...)` values mean no access.
    static func fromInfo(_ info: [String: Any]) -> ChalkQueryAccess? {
        func value(_ name: String) -> String? {
            guard let raw = info[name] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        return ChalkQueryAccess(engine: value("FEEL_CHALK_QUERY_ENGINE"), environmentId: value("FEEL_CHALK_ENV"),
                                clientId: value("FEEL_CHALK_CLIENT_ID"), token: value("FEEL_CHALK_QUERY_TOKEN"))
    }
    static func fromBundle(_ bundle: Bundle = .main) -> ChalkQueryAccess? { fromInfo(bundle.infoDictionary ?? [:]) }

    /// When the token stops working, read from its claims (the server decides; this only spares a doomed request). Nil for an opaque token.
    var expiresAt: Date? { (SupabaseConfiguration.claims(of: token)?["exp"] as? Double).map { Date(timeIntervalSince1970: $0) } }
    func isUsable(at now: Date) -> Bool { expiresAt.map { $0 > now } ?? true }
}

enum ChalkQueryError: Error, Equatable {
    /// No access in this build, or a token already expired.
    case access
    case network
    case http(Int)
    case malformedReply
    /// The query itself failed (the reply's `errors`), with Chalk's code and message.
    case query(String)
    /// One output feature carried an error instead of a value.
    case feature(String, String)
    /// An output was not in the reply at all.
    case missing(String)
}

/// One online query: the named query's inputs in, `{feature: value}` out. Stubbed in tests; `ChalkQueryClient` in the app.
protocol ChalkQuerying: AnyObject {
    func query(_ name: String, inputs: [String: Any], outputs: [String], completion: @escaping (Result<[String: Any], ChalkQueryError>) -> Void)
}

/// POST {engine}/v1/query/online with the bearer token and Chalk's three headers, the same request as
/// chalk/feel_chalk/context.py makes. Redirects are refused so the token cannot travel to another host. The reply's
/// `errors` fail the query; each `data` item is one output's value or error. Completion runs on the main queue.
final class ChalkQueryClient: NSObject, ChalkQuerying, URLSessionTaskDelegate {
    static let timeout: TimeInterval = 12
    let access: ChalkQueryAccess
    private let now: () -> Date
    private let injected: URLSession?
    private lazy var session: URLSession = injected ?? URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(access: ChalkQueryAccess, session: URLSession? = nil, now: @escaping () -> Date = Date.init) {
        self.access = access; self.injected = session; self.now = now
    }
    /// The app's client, or nil when the build carries no query access (UI tests never query).
    static func forLaunch() -> ChalkQueryClient? {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting"), let access = ChalkQueryAccess.fromBundle() else { return nil }
        return ChalkQueryClient(access: access)
    }

    func query(_ name: String, inputs: [String: Any], outputs: [String], completion: @escaping (Result<[String: Any], ChalkQueryError>) -> Void) {
        guard access.isUsable(at: now()),
              let body = try? JSONSerialization.data(withJSONObject: ["inputs": inputs, "outputs": outputs, "query_name": name], options: [.sortedKeys]) else {
            DispatchQueue.main.async { completion(.failure(.access)) }; return
        }
        var request = URLRequest(url: access.engine.appendingPathComponent("v1/query/online"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(access.token)", forHTTPHeaderField: "Authorization")
        request.setValue(access.environmentId, forHTTPHeaderField: "X-Chalk-Env-Id")
        if let clientId = access.clientId { request.setValue(clientId, forHTTPHeaderField: "X-Chalk-Client-Id") }
        request.setValue("engine", forHTTPHeaderField: "X-Chalk-Deployment-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            let result: Result<[String: Any], ChalkQueryError>
            if error != nil || response == nil { result = .failure(.network) }
            else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { result = .failure(.http(http.statusCode)) }
            else { result = Self.parse(data, outputs: outputs) }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// The values of `outputs` from a query reply, or the first thing wrong with it; never a guess for a missing value.
    static func parse(_ data: Data?, outputs: [String]) -> Result<[String: Any], ChalkQueryError> {
        guard let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure(.malformedReply) }
        if let errors = object["errors"] as? [Any], let first = errors.first {
            let error = first as? [String: Any]
            return .failure(.query("\(error?["code"] ?? "error") \(String(describing: error?["message"] ?? "").prefix(200))".trimmingCharacters(in: .whitespaces)))
        }
        var values: [String: Any] = [:]
        for case let item as [String: Any] in object["data"] as? [Any] ?? [] {
            guard let field = item["field"] as? String else { continue }
            if let error = item["error"], !(error is NSNull) {
                let message = (error as? [String: Any])?["message"].map { String(describing: $0) } ?? String(describing: error)
                return .failure(.feature(field, String(message.prefix(200))))
            }
            values[field] = item["value"] ?? NSNull()
        }
        if let missing = outputs.first(where: { values[$0] == nil }) { return .failure(.missing(missing)) }
        return .success(values)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// The named queries the phone reads, keyed exactly as chalk/feel_chalk/context.py keys them, and the shapes it
/// accepts back. Each is a past record: where an object was last confirmed, what shared visits saw of a room.
enum ChalkContext {
    /// ObjectHistory.id: the user and the object as the finds table stores it (lower case, single spaces).
    static func lastSeenKey(userId: String, object: String) -> String {
        "\(userId.trimmingCharacters(in: .whitespaces)):\(RoomAnchor.normalized(object))"
    }
    /// RoomMemory.id: the venue slug and the tag id as printed, '<venue_id>:<tag_id>'.
    static func roomKey(venueId: String, tagId: String) -> String {
        "\(venueId.trimmingCharacters(in: .whitespaces).lowercased()):\(tagId.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// The sentence Chalk wrote for the last confirmed find ("Keys: last confirmed at the …, 2 hours ago."), or why there is none.
    static func lastSeen(_ client: ChalkQuerying, userId: String, object: String, completion: @escaping (Result<String, ChalkQueryError>) -> Void) {
        client.query("last_seen", inputs: ["object_history.id": lastSeenKey(userId: userId, object: object)], outputs: ["object_history.spoken"]) { result in
            completion(result.flatMap { values in
                guard let spoken = values["object_history.spoken"] as? String, !spoken.isEmpty else { return .failure(.malformedReply) }
                return .success(spoken)
            })
        }
    }

    /// The room's structure as Chalk merged it from shared visits, with the number of visits that voted; nil while nobody shared one.
    static func roomStructure(_ client: ChalkQuerying, venueId: String, tagId: String,
                              completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void) {
        client.query("room_structure", inputs: ["room_memory.id": roomKey(venueId: venueId, tagId: tagId)],
                     outputs: ["room_memory.structure", "room_memory.structure_visits"]) { result in
            completion(result.flatMap { values in
                guard let visits = (values["room_memory.structure_visits"] as? NSNumber).flatMap({ CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue }),
                      visits >= 0 else { return .failure(.malformedReply) }
                if values["room_memory.structure"] is NSNull { return .success((nil, visits)) }
                guard let raw = values["room_memory.structure"] as? String, let map = roomMap(fromJSON: raw) else { return .failure(.malformedReply) }
                return .success((map, visits))
            })
        }
    }

    /// The targets remembered at the tag (the per-label medians of shared sightings), as anchors the local store can
    /// hold: one sighting per label at Chalk's time, confidence 0.5, since the median of other people's confirmations
    /// is weaker evidence than this user's own "found it".
    static func roomAnchors(_ client: ChalkQuerying, venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void) {
        client.query("room_anchors", inputs: ["room_memory.id": roomKey(venueId: venueId, tagId: tagId)], outputs: ["room_memory.targets"]) { result in
            completion(result.flatMap { values in
                guard let raw = values["room_memory.targets"] as? String, let anchors = anchors(fromJSON: raw) else { return .failure(.malformedReply) }
                return .success(anchors)
            })
        }
    }

    /// chalk/feel_chalk/room_map.py `to_json`: schema, cell_size, origin_x, origin_y, width, height, cells (run-length encoded).
    static func roomMap(fromJSON text: String) -> RoomMap? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let cellSize = number(object["cell_size"]), let originX = number(object["origin_x"]), let originY = number(object["origin_y"]),
              let width = number(object["width"]), let height = number(object["height"]), width == width.rounded(), height == height.rounded(),
              let cells = object["cells"] as? String else { return nil }
        return RoomMap(cellSize: cellSize, originX: originX, originY: originY, width: Int(width), height: Int(height), encoded: cells)
    }
    /// chalk/feel_chalk/anchors.py `to_json`: label, x, y, z, sightings, last_seen_at (ISO 8601). Malformed items are skipped, never guessed.
    static func anchors(fromJSON text: String) -> [RoomAnchor]? {
        guard let items = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any] else { return nil }
        return items.compactMap { item -> RoomAnchor? in
            guard let item = item as? [String: Any], let label = item["label"] as? String, let x = number(item["x"]), let y = number(item["y"]), let z = number(item["z"]),
                  let time = item["last_seen_at"] as? String, let seenAt = date(time) else { return nil }
            let anchor = RoomAnchor(label: RoomAnchor.normalized(label), position: Vector3(x, y, z), confidence: 0.5, seenAt: seenAt)
            return anchor.isUsable ? anchor : nil
        }
    }
    static let sharedConfidence = 0.5
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static let withFraction: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let whole = ISO8601DateFormatter()
    /// Python's isoformat: "2026-10-17T12:00:00+00:00", with or without fractional seconds.
    private static func date(_ text: String) -> Date? { withFraction.date(from: text) ?? whole.date(from: text) }
}
