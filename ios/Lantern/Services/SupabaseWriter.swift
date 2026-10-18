import Foundation
import FeelCore

/// The phone's side of the shared memory. Every confirmed find, room anchor, room map and journey goes to the
/// Supabase tables Chalk reads (chalk/sql/schema.sql) as one PostgREST insert carrying the signed-in user's token,
/// so "where did I last see my keys", a room's anchors, its structure and its paths answer from what this phone saw.
/// Row Level Security files each row under that user (`user_id` must be the token's subject). Anchors, maps and
/// journeys are shared with other users only after a separate explicit sharing opt-in. Nothing here reaches the
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

/// The explicitly selected venue a row is filed under. It must exist in the venues table.
struct VenueRef: Equatable {
    let id: String, name: String
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

/// Main-queue uploader. Writes require explicit opt-in, ownership stays bound to the original
/// session, and a refreshed credential never replaces a session that signed out or switched users.
final class SupabaseWriter: NSObject, MemoryUploading, URLSessionTaskDelegate {
    struct Status: Equatable {
        var sent = 0, failed = 0, skipped = 0
        var lastError: String?
    }
    private(set) var status = Status()
    let configuration: SupabaseConfiguration?
    private let store: KeychainStore<AuthSessionTokens>
    private let now: () -> Date
    private let defaults: UserDefaults
    private let injected: URLSession?
    private lazy var session: URLSession = injected ?? URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    /// A selected venue is required for spatial records. Missing context is never replaced by a demo venue.
    var venue: () -> VenueRef? = { nil }
    static let uploadsKey = "feel.uploadMemory"
    static let sharingKey = "feel.shareRoomMemory"
    static let timeout: TimeInterval = 10
    static let refreshMargin: TimeInterval = 60
    private var consentGeneration = UUID()
    private var tasks: [UUID: URLSessionDataTask] = [:]
    private final class RefreshBatch {
        let tokens: AuthSessionTokens
        let generation: UUID
        var callbacks: [(AuthSessionTokens?) -> Void] = []
        init(tokens: AuthSessionTokens, generation: UUID) { self.tokens=tokens; self.generation=generation }
    }
    private var refreshing: RefreshBatch?

    init(configuration: SupabaseConfiguration?, store: KeychainStore<AuthSessionTokens>, session: URLSession? = nil,
         now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.configuration=configuration; self.store=store; self.injected=session; self.now=now; self.defaults=defaults
    }
    static func forLaunch() -> SupabaseWriter {
        let uiTesting=ProcessInfo.processInfo.arguments.contains("--uitesting")
        return SupabaseWriter(configuration: uiTesting ? nil : SupabaseConfiguration.fromBundle(), store: AuthModel.sessionStore)
    }
    var uploadsEnabled: Bool { defaults.object(forKey: Self.uploadsKey) as? Bool ?? false }
    var sharesRoomMemory: Bool { defaults.object(forKey: Self.sharingKey) as? Bool ?? false }
    func setUploadsEnabled(_ enabled: Bool) {
        guard enabled != uploadsEnabled else { return }
        defaults.set(enabled,forKey:Self.uploadsKey); invalidatePending()
    }
    func setSharingEnabled(_ enabled: Bool) {
        guard enabled != sharesRoomMemory else { return }
        defaults.set(enabled,forKey:Self.sharingKey); invalidatePending()
    }
    private func invalidatePending() {
        consentGeneration=UUID()
        for task in tasks.values { task.cancel() }
        // Work already accepted by the server cannot be recalled. No pending retry or refresh may send more.
    }
    private static func subject(_ tokens: AuthSessionTokens) -> String? {
        guard let value=SupabaseConfiguration.claims(of:tokens.accessToken)?["sub"] as? String,
              SupabaseRows.isUUID(value) else { return nil }
        return value
    }
    var userId: String? { store.load().flatMap(Self.subject) }
    var isReady: Bool { uploadsEnabled && configuration != nil && userId != nil }
    var statusReport: [String: Any] {
        ["configured":configuration != nil,"signed_in":userId != nil,"user_id":userId ?? "none","venue":venue()?.id ?? "none",
         "uploads_enabled":uploadsEnabled,"shares_room_memory":sharesRoomMemory,"sent":status.sent,"failed":status.failed,
         "skipped":status.skipped,"last_error":status.lastError ?? "none"]
    }

    func upload(find objectName: String, place: String, confidence: Double, foundAt: Date) {
        guard let tokens=ready(),let userId=Self.subject(tokens) else { return }
        send(SupabaseRows.find(userId:userId,objectName:objectName,place:place,confidence:confidence,foundAt:foundAt),kind:"find",tokens:tokens)
    }
    func upload(anchor: RoomAnchor, tagId: String) {
        guard let tokens=ready(),let userId=Self.subject(tokens),let venue=selectedVenue() else { return }
        send(SupabaseRows.anchor(userId:userId,venueId:venue.id,tagId:tagId,anchor:anchor,shared:sharesRoomMemory),kind:"anchor",tokens:tokens)
    }
    func upload(structure: RoomMap, tagId: String, seenAt: Date) {
        guard let tokens=ready(),let userId=Self.subject(tokens),let venue=selectedVenue() else { return }
        send(SupabaseRows.roomMap(userId:userId,venueId:venue.id,tagId:tagId,map:structure,shared:sharesRoomMemory,seenAt:seenAt),kind:"room map",tokens:tokens)
    }
    func upload(journey: Journey) {
        guard let tokens=ready(),let userId=Self.subject(tokens),let venue=selectedVenue() else { return }
        send(SupabaseRows.journey(userId:userId,venueId:venue.id,journey:journey,shared:sharesRoomMemory),kind:"journey",tokens:tokens)
    }
    private func selectedVenue() -> VenueRef? {
        guard let value=venue(),SupabaseRows.isId(value.id) else { skip("select a venue before uploading room memory"); return nil }
        return value
    }
    private func ready() -> AuthSessionTokens? {
        guard configuration != nil else { skip("no Supabase settings in this build"); return nil }
        guard uploadsEnabled else { skip("uploads are off"); return nil }
        guard let tokens=store.load(),Self.subject(tokens) != nil else { skip("not signed in"); return nil }
        return tokens
    }
    private func current(_ tokens: AuthSessionTokens, generation: UUID) -> Bool {
        uploadsEnabled && generation==consentGeneration && store.load()==tokens
    }
    private func skip(_ reason: String) { status.skipped += 1; status.lastError=reason }
    private func fail(_ reason: String) { status.failed += 1; status.lastError=reason }
    private func send(_ row: SupabaseRow?, kind: String, tokens: AuthSessionTokens) {
        guard let row else { skip("\(kind) row is outside the table's limits"); return }
        post(row,tokens:tokens,generation:consentGeneration,retried:false)
    }
    private func retry(_ row: SupabaseRow, tokens: AuthSessionTokens, generation: UUID) {
        refresh(tokens:tokens,generation:generation) { [weak self] fresh in
            guard let self else { return }
            if let fresh { self.post(row,tokens:fresh,generation:generation,retried:true) }
            else if !self.current(tokens,generation:generation) { self.skip("upload canceled because consent or sign-in changed") }
            else { self.fail("\(row.table): the session expired; sign in again") }
        }
    }
    private func post(_ row: SupabaseRow, tokens: AuthSessionTokens, generation: UUID, retried: Bool) {
        guard let configuration,current(tokens,generation:generation) else { skip("upload canceled because consent or sign-in changed"); return }
        if !retried,let exp=SupabaseConfiguration.claims(of:tokens.accessToken)?["exp"] as? Double,
           Date(timeIntervalSince1970:exp)<=now().addingTimeInterval(Self.refreshMargin) {
            retry(row,tokens:tokens,generation:generation); return
        }
        var request=URLRequest(url:configuration.url.appendingPathComponent("rest/v1/\(row.table)"),timeoutInterval:Self.timeout)
        request.httpMethod="POST"; request.httpBody=row.body
        request.setValue(configuration.publishableKey,forHTTPHeaderField:"apikey")
        request.setValue("Bearer \(tokens.accessToken)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("return=minimal",forHTTPHeaderField:"Prefer")
        let id=UUID()
        let task=session.dataTask(with:request) { [weak self] data,response,error in
            let code=(response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let self else { return }; self.tasks.removeValue(forKey:id)
                guard self.current(tokens,generation:generation) else { self.skip("upload completed after consent or sign-in changed"); return }
                guard error==nil,let code else { self.fail("\(row.table): no reply from Supabase"); return }
                switch code {
                case 200..<300: self.status.sent += 1
                case 401 where !retried: self.retry(row,tokens:tokens,generation:generation)
                default: self.fail("\(row.table) \(code): \(Self.message(data))")
                }
            }
        }
        tasks[id]=task; task.resume()
    }

    /// Concurrent uploads share one refresh. A delayed refresh may only replace its exact original token pair.
    private func refresh(tokens: AuthSessionTokens, generation: UUID, completion: @escaping (AuthSessionTokens?) -> Void) {
        guard let configuration,current(tokens,generation:generation),
              let body=try? JSONEncoder().encode(["refresh_token":tokens.refreshToken]) else { completion(nil); return }
        if let refreshing,refreshing.tokens==tokens,refreshing.generation==generation {
            refreshing.callbacks.append(completion); return
        }
        let batch=RefreshBatch(tokens:tokens,generation:generation); batch.callbacks=[completion]; refreshing=batch
        var components=URLComponents(url:configuration.url.appendingPathComponent("auth/v1/token"),resolvingAgainstBaseURL:false)!
        components.queryItems=[URLQueryItem(name:"grant_type",value:"refresh_token")]
        var request=URLRequest(url:components.url!,timeoutInterval:Self.timeout)
        request.httpMethod="POST"; request.httpBody=body
        request.setValue(configuration.publishableKey,forHTTPHeaderField:"apikey")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let id=UUID()
        let task=session.dataTask(with:request) { [weak self] data,response,error in
            let result=SupabaseAuthClient.parseSignIn(data:data,status:(response as? HTTPURLResponse)?.statusCode,failed:error != nil)
            DispatchQueue.main.async {
                guard let self else { return }; self.tasks.removeValue(forKey:id)
                if self.refreshing === batch { self.refreshing=nil }
                var accepted:AuthSessionTokens?
                if self.current(tokens,generation:generation),case .success(let fresh)=result,
                   Self.subject(fresh)==Self.subject(tokens) {
                    let replacement=AuthSessionTokens(accessToken:fresh.accessToken,refreshToken:fresh.refreshToken,email:fresh.email.isEmpty ? tokens.email : fresh.email)
                    do { try self.store.save(replacement); accepted=replacement } catch { accepted=nil }
                }
                for callback in batch.callbacks { callback(accepted) }
            }
        }
        tasks[id]=task; task.resume()
    }
    private static func message(_ data: Data?) -> String {
        guard let data,!data.isEmpty else { return "no detail" }
        if let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let message=object["message"] as? String { return String(message.prefix(200)) }
        return String(String(decoding:data.prefix(120),as:UTF8.self))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
