import Foundation
import FeelCore

/// The phone's side of the shared memory. Every confirmed find, room anchor, room map and journey goes to the
/// Supabase tables Chalk reads (chalk/sql/schema.sql) as one PostgREST insert carrying the signed-in user's token,
/// so "where did I last see my keys", a room's anchors, its structure and its paths answer from what this phone saw.
/// Row Level Security files each row under that user (`user_id` must be the token's subject). Anchors, maps and
/// journeys are marked shared, the only rows Chalk may read, unless sharing was turned off. Nothing here reaches the
/// pins, and a failed upload costs a counter and nothing else: the stores on the phone stay the memory.
protocol MemoryUploading: AnyObject {
    /// Whether a row can leave the phone now: Supabase settings in the build and a signed-in user.
    var isReady: Bool { get }
    /// The signed-in user's id, the key the shared memory files finds under; nil without a sign-in.
    var userId: String? { get }
    /// For get_status: rows sent, failed and skipped, the last reason, and who the rows are filed under.
    var statusReport: [String: Any] { get }
    func upload(find objectName: String, place: String, confidence: Double, foundAt: Date)
    func upload(anchor: RoomAnchor, tagId: String)
    func upload(structure: RoomMap, tagId: String, seenAt: Date)
    func upload(journey: Journey)
}

/// The venue a row is filed under. It must exist in the venues table (a foreign key), so the loaded venue pack's
/// venue is used when there is one, else the demo venue, whose row went in with its pack.
struct VenueRef: Equatable {
    let id: String, name: String
    static let demo = VenueRef(id: "rubenstein-treehouse", name: "David Rubenstein Treehouse")
}

/// One insert: the table and its PostgREST JSON body, already checked against the table's constraints.
struct SupabaseRow: Equatable {
    let table: String
    let body: Data
}

/// Rows in the shape of the tables, built on the phone. Each builder applies the table's check constraints, so a
/// row the database would refuse is dropped here (nil) instead of costing a request. Keys are sorted, dates are
/// ISO 8601 seconds in UTC, the same bytes as the journey files on the phone.
enum SupabaseRows {
    static let maxLabel = 64, maxPlace = 200, maxId = 64
    static let reach = 100.0, maxArrivalDistance = 200.0
    static let dates = ISO8601DateFormatter()
    private static let tagPattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9-]{0,63}$")

    static func find(userId: String, objectName: String, place: String, confidence: Double, foundAt: Date) -> SupabaseRow? {
        let name = RoomAnchor.normalized(objectName), at = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUUID(userId), (1...maxLabel).contains(name.count), (1...maxPlace).contains(at.count), isUnit(confidence) else { return nil }
        return row("confirmed_finds", ["user_id": userId, "object_name": name, "place": at, "confidence": confidence, "found_at": dates.string(from: foundAt)])
    }

    static func anchor(userId: String, venueId: String, tagId: String, anchor: RoomAnchor, shared: Bool) -> SupabaseRow? {
        let p = anchor.position
        guard isUUID(userId), isId(venueId), isTag(tagId), (1...maxLabel).contains(anchor.label.count), anchor.label == RoomAnchor.normalized(anchor.label),
              [p.x, p.y, p.z].allSatisfy({ $0.isFinite && abs($0) <= reach }), isUnit(anchor.confidence) else { return nil }
        return row("anchors", ["user_id": userId, "venue_id": venueId, "tag_id": tagId, "label": anchor.label, "x": p.x, "y": p.y, "z": p.z,
                               "confidence": anchor.confidence, "shared": shared, "seen_at": dates.string(from: anchor.seenAt)])
    }

    /// RoomMap's own initializer holds the table's size, cell and origin checks; only the ids are checked here.
    static func roomMap(userId: String, venueId: String, tagId: String, map: RoomMap, shared: Bool, seenAt: Date) -> SupabaseRow? {
        guard isUUID(userId), isId(venueId), isTag(tagId) else { return nil }
        return row("room_maps", ["user_id": userId, "venue_id": venueId, "tag_id": tagId, "cell_size": map.cellSize, "origin_x": map.originX,
                                 "origin_y": map.originY, "width": map.width, "height": map.height, "cells": map.encoded, "shared": shared,
                                 "seen_at": dates.string(from: seenAt)])
    }

    /// The journey as its file encodes it (steps, obstacles, cue latencies, arrival), filed under this user and venue.
    static func journey(userId: String, venueId: String, journey: Journey, shared: Bool) -> SupabaseRow? {
        let label = RoomAnchor.normalized(journey.targetLabel)
        guard isUUID(userId), isId(venueId), isTag(journey.tagId), (1...maxId).contains(journey.sessionId.count), (1...maxLabel).contains(label.count),
              !journey.steps.isEmpty, let distance = journey.arrivalDistanceM, distance.isFinite, (0...maxArrivalDistance).contains(distance),
              let encoded = try? Journey.encoder.encode(journey),
              var fields = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return nil }
        fields["user_id"] = userId; fields["venue_id"] = venueId; fields["target_label"] = label; fields["shared"] = shared
        return row("journeys", fields)
    }

    private static func row(_ table: String, _ fields: [String: Any]) -> SupabaseRow? {
        guard JSONSerialization.isValidJSONObject(fields), let body = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return nil }
        return SupabaseRow(table: table, body: body)
    }
    static func isTag(_ id: String) -> Bool { tagPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil }
    static func isUnit(_ value: Double) -> Bool { value.isFinite && (0...1).contains(value) }
    static func isUUID(_ value: String) -> Bool { UUID(uuidString: value) != nil }
    static func isId(_ value: String) -> Bool { (1...maxId).contains(value.count) }
}

/// POST {SUPABASE_URL}/rest/v1/{table} with the publishable key and the signed-in user's access token, `Prefer:
/// return=minimal`. The token is the one the sign-in saved to the Keychain; it lasts an hour, so one about to expire
/// (or refused with 401) is exchanged for a new one with the saved refresh token, which is then saved in its place,
/// and the row is sent once more. Redirects are refused so the token cannot travel to another host. Main thread;
/// the counters change on the main queue.
final class SupabaseWriter: NSObject, MemoryUploading, URLSessionTaskDelegate {
    struct Status: Equatable {
        var sent = 0, failed = 0, skipped = 0
        var lastError: String?
    }
    private(set) var status = Status()
    /// Nil when the build has no Supabase settings: every row is then skipped and counted.
    let configuration: SupabaseConfiguration?
    private let store: KeychainStore<AuthSessionTokens>
    private let now: () -> Date
    private let injected: URLSession?
    private lazy var session: URLSession = injected ?? URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    /// The venue rows are filed under; the app points this at the loaded venue pack.
    var venue: () -> VenueRef = { .demo }
    /// Anchors, room maps and journeys are marked shared, which lets Chalk merge them into the room's memory for every
    /// FEEL user, unless this default is set to false. Finds are the user's own and have no such mark.
    static let sharingKey = "feel.shareRoomMemory"
    static let timeout: TimeInterval = 10
    /// A token this close to its expiry is refreshed before the row goes, so the hour's first write does not fail.
    static let refreshMargin: TimeInterval = 60

    init(configuration: SupabaseConfiguration?, store: KeychainStore<AuthSessionTokens>, session: URLSession? = nil, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.store = store; self.injected = session; self.now = now
    }
    /// The app's writer: the build's Supabase settings and the sign-in's Keychain session. UI tests send nothing.
    static func forLaunch() -> SupabaseWriter {
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        return SupabaseWriter(configuration: uiTesting ? nil : SupabaseConfiguration.fromBundle(), store: AuthModel.sessionStore)
    }

    var sharesRoomMemory: Bool { UserDefaults.standard.object(forKey: Self.sharingKey) as? Bool ?? true }
    /// The signed-in user's id, the token's subject: what the tables' Row Level Security compares with auth.uid().
    var userId: String? { store.load().flatMap { SupabaseConfiguration.claims(of: $0.accessToken)?["sub"] as? String } }
    var isReady: Bool { configuration != nil && userId != nil }
    var statusReport: [String: Any] {
        ["configured": configuration != nil, "signed_in": userId != nil, "user_id": userId ?? "none", "venue": venue().id,
         "shares_room_memory": sharesRoomMemory, "sent": status.sent, "failed": status.failed, "skipped": status.skipped,
         "last_error": status.lastError ?? "none"]
    }

    func upload(find objectName: String, place: String, confidence: Double, foundAt: Date) {
        guard let userId = ready() else { return }
        send(SupabaseRows.find(userId: userId, objectName: objectName, place: place, confidence: confidence, foundAt: foundAt), kind: "find")
    }
    func upload(anchor: RoomAnchor, tagId: String) {
        guard let userId = ready() else { return }
        send(SupabaseRows.anchor(userId: userId, venueId: venue().id, tagId: tagId, anchor: anchor, shared: sharesRoomMemory), kind: "anchor")
    }
    func upload(structure: RoomMap, tagId: String, seenAt: Date) {
        guard let userId = ready() else { return }
        send(SupabaseRows.roomMap(userId: userId, venueId: venue().id, tagId: tagId, map: structure, shared: sharesRoomMemory, seenAt: seenAt), kind: "room map")
    }
    func upload(journey: Journey) {
        guard let userId = ready() else { return }
        send(SupabaseRows.journey(userId: userId, venueId: venue().id, journey: journey, shared: sharesRoomMemory), kind: "journey")
    }

    private func ready() -> String? {
        guard configuration != nil else { skip("no Supabase settings in this build"); return nil }
        guard let userId else { skip("not signed in"); return nil }
        return userId
    }
    private func skip(_ reason: String) { status.skipped += 1; status.lastError = reason }
    private func fail(_ reason: String) { status.failed += 1; status.lastError = reason }
    private func send(_ row: SupabaseRow?, kind: String) {
        guard let row else { skip("\(kind) row is outside the table's limits"); return }
        post(row, retried: false)
    }

    private func post(_ row: SupabaseRow, retried: Bool) {
        guard let configuration, let tokens = store.load() else { skip("not signed in"); return }
        if !retried, let exp = SupabaseConfiguration.claims(of: tokens.accessToken)?["exp"] as? Double,
           Date(timeIntervalSince1970: exp) <= now().addingTimeInterval(Self.refreshMargin) {
            refresh { [weak self] ok in
                if ok { self?.post(row, retried: true) } else { self?.fail("\(row.table): the session expired; sign in again") }
            }
            return
        }
        var request = URLRequest(url: configuration.url.appendingPathComponent("rest/v1/\(row.table)"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = row.body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        session.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, let code else { self.fail("\(row.table): no reply from Supabase"); return }
                switch code {
                case 200..<300: self.status.sent += 1
                case 401 where !retried:
                    self.refresh { ok in
                        if ok { self.post(row, retried: true) } else { self.fail("\(row.table): the session expired; sign in again") }
                    }
                default: self.fail("\(row.table) \(code): \(Self.message(data))")
                }
            }
        }.resume()
    }

    /// POST auth/v1/token?grant_type=refresh_token: a new access and refresh token, saved where the sign-in saved them.
    private func refresh(_ completion: @escaping (Bool) -> Void) {
        guard let configuration, let tokens = store.load(), let body = try? JSONEncoder().encode(["refresh_token": tokens.refreshToken]) else {
            completion(false); return
        }
        var components = URLComponents(url: configuration.url.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var request = URLRequest(url: components.url!, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        session.dataTask(with: request) { [weak self] data, response, error in
            let result = SupabaseAuthClient.parseSignIn(data: data, status: (response as? HTTPURLResponse)?.statusCode, failed: error != nil)
            DispatchQueue.main.async {
                guard let self, case .success(let fresh) = result else { completion(false); return }
                let email = fresh.email.isEmpty ? tokens.email : fresh.email
                try? self.store.save(AuthSessionTokens(accessToken: fresh.accessToken, refreshToken: fresh.refreshToken, email: email))
                completion(true)
            }
        }.resume()
    }

    /// PostgREST's message for the log line, or the start of whatever came back.
    private static func message(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "no detail" }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let message = object["message"] as? String { return message }
        return String(String(decoding: data.prefix(120), as: UTF8.self))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
