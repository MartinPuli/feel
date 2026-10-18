import XCTest
import FeelCore
@testable import Lantern

/// Records what the app hands to the shared memory, so the write path is checked without a network.
final class RecordingUploader: MemoryUploading {
    var ready = true
    var user: String? = "6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b"
    var userId: String? { ready ? user : nil }
    var finds: [(objectName: String, place: String, confidence: Double, foundAt: Date)] = []
    var anchors: [(anchor: RoomAnchor, tagId: String)] = []
    var structures: [(map: RoomMap, tagId: String, seenAt: Date)] = []
    var journeys: [Journey] = []
    var isReady: Bool { ready }
    var statusReport: [String: Any] { ["configured": true, "signed_in": ready, "sent": finds.count + anchors.count + structures.count + journeys.count] }
    func upload(find objectName: String, place: String, confidence: Double, foundAt: Date) { finds.append((objectName, place, confidence, foundAt)) }
    func upload(anchor: RoomAnchor, tagId: String) { anchors.append((anchor, tagId)) }
    func upload(structure: RoomMap, tagId: String, seenAt: Date) { structures.append((structure, tagId, seenAt)) }
    func upload(journey: Journey) { journeys.append(journey) }
}

/// The phone's writes to the shared memory on Supabase: rows in the tables' shape, posted with the signed-in user's
/// token, refreshed when that token has expired, and skipped (never failed loudly) when nothing can leave the phone.
final class SupabaseWriterTests: XCTestCase {
    private let user = "6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b"
    private let seenAt = ISO8601DateFormatter().date(from: "2026-10-18T14:00:00Z")!
    private let configuration = SupabaseConfiguration(url: "https://kgdt.supabase.co", publishableKey: "sb_publishable_0123456789abcdef")!
    /// The tag upright on the wall 3 m ahead of the identity camera: out of the tag is world +z, down is −y, right along it is +x.
    private let tagFrame = RoomFrame(origin: Vector3(0, 0, -3), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 0, 1), zAxis: Vector3(0, -1, 0))
    private let exit = RoomAnchor(label: "exit", position: Vector3(-1, 1, 0), confidence: 0.9, seenAt: ISO8601DateFormatter().date(from: "2026-10-18T14:00:00Z")!)
    private var store: KeychainStore<AuthSessionTokens>!
    private var directory: URL!
    private var defaults: UserDefaults!
    private var defaultsName: String!

    override func setUp() {
        store = KeychainStore(service: "org.feel.hackharvard.auth.tests", account: "writer-\(name)")
        store.clear()
        defaultsName="feel.writer.tests."+UUID().uuidString
        defaults=UserDefaults(suiteName:defaultsName)!
        defaults.removePersistentDomain(forName:defaultsName)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() {
        store.clear(); defaults.removePersistentDomain(forName:defaultsName); try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.handler = nil; StubURLProtocol.lastRequest = nil; StubURLProtocol.lastBody = nil
    }

    /// An unsigned JWT with the claims Supabase puts in its access tokens; the writer reads sub and exp, the server would verify.
    private func token(sub: String, exp: TimeInterval, tag: String = "a") -> String {
        func part(_ object: [String: Any]) -> String {
            try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return part(["alg": "HS256", "typ": "JWT"]) + "." + part(["sub": sub, "exp": exp, "role": "authenticated"]) + ".sig-\(tag)"
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
    private func makeWriter(consent: Bool = true, selectedVenue: Bool = true) -> SupabaseWriter {
        let writer=SupabaseWriter(configuration:configuration,store:store,session:session(),now:{ self.seenAt },defaults:defaults)
        writer.setUploadsEnabled(consent)
        if selectedVenue { writer.venue={ VenueRef(id:"harvard-yard",name:"Harvard Yard") } }
        return writer
    }
    private func signIn(exp: TimeInterval = 3600, tag: String = "a") throws -> String {
        let access = token(sub: user, exp: seenAt.timeIntervalSince1970 + exp, tag: tag)
        try store.save(AuthSessionTokens(accessToken: access, refreshToken: "r1", email: "ben@example.com"))
        return access
    }
    private func json(_ data: Data?) throws -> NSDictionary { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? NSDictionary) }
    private func object(_ row: SupabaseRow?) throws -> NSDictionary { try json(XCTUnwrap(row).body) }
    private func location(_ request: URLRequest) -> String { request.url!.path + (request.url!.query.map { "?\($0)" } ?? "") }
    /// Spins the main run loop until the writer's counters moved (its completions run on the main queue).
    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 5, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(condition(), "timed out waiting", line: line)
    }

    // MARK: Rows in the tables' shape
    func testAFindRowIsTheConfirmedFindsTable() throws {
        let row = SupabaseRows.find(userId: user, objectName: "  Water  Bottle ", place: " lab bench by the window ", confidence: 0.9, foundAt: seenAt)
        XCTAssertEqual(row?.table, "confirmed_finds")
        XCTAssertEqual(try object(row), ["user_id": user, "object_name": "water bottle", "place": "lab bench by the window", "confidence": 0.9, "found_at": "2026-10-18T14:00:00Z"])
        let body = String(decoding: try XCTUnwrap(row).body, as: UTF8.self)
        XCTAssertTrue(body.hasPrefix(#"{"confidence":0.9"#) && body.hasSuffix(#""user_id":"\#(user)"}"#), "sorted keys, so the same bytes every time: \(body)")
    }

    func testAnAnchorRowCarriesTheVenueTheTagAndTheSharingMark() throws {
        let anchor = RoomAnchor(label: "exit", position: Vector3(-1, 1, 0.25), confidence: 0.9, seenAt: seenAt)
        let row = SupabaseRows.anchor(userId: user, venueId: "rubenstein-treehouse", tagId: "feel-tag-01", anchor: anchor, shared: true)
        XCTAssertEqual(row?.table, "anchors")
        XCTAssertEqual(try object(row), ["user_id": user, "venue_id": "rubenstein-treehouse", "tag_id": "feel-tag-01", "label": "exit", "x": -1, "y": 1, "z": 0.25,
                                         "confidence": 0.9, "shared": true, "seen_at": "2026-10-18T14:00:00Z"])
        XCTAssertEqual(try object(SupabaseRows.anchor(userId: user, venueId: "harvard-yard", tagId: "feel-tag-01", anchor: anchor, shared: false))["shared"] as? Bool, false)
    }

    func testARoomMapRowCarriesTheEncodedCells() throws {
        let map = try XCTUnwrap(RoomMap(cellSize: 0.1, originX: -0.2, originY: 0, width: 3, height: 2, cells: [.free, .blocked, .unknown, .free, .free, .free]))
        let row = SupabaseRows.roomMap(userId: user, venueId: "rubenstein-treehouse", tagId: "feel-tag-01", map: map, shared: true, seenAt: seenAt)
        XCTAssertEqual(row?.table, "room_maps")
        XCTAssertEqual(try object(row), ["user_id": user, "venue_id": "rubenstein-treehouse", "tag_id": "feel-tag-01", "cell_size": 0.1, "origin_x": -0.2, "origin_y": 0,
                                         "width": 3, "height": 2, "cells": map.encoded, "shared": true, "seen_at": "2026-10-18T14:00:00Z"])
    }

    func testAJourneyRowIsTheJourneyFileUnderThisUserAndVenue() throws {
        let walk = Journey(tagId: "feel-tag-01", sessionId: "abc", startedAt: seenAt, targetLabel: "Exit",
                           steps: [Journey.Step(t: 0, x: -1, y: 1.1, headingDeg: 0), Journey.Step(t: 2, x: -1, y: 2.1, headingDeg: 270)],
                           obstacles: [FloorPoint(-2.05, 4.05)], cueLatencyMs: [120, 95], arrivedAt: seenAt.addingTimeInterval(14), arrivalDistanceM: 0.3)
        let row = SupabaseRows.journey(userId: user, venueId: "rubenstein-treehouse", journey: walk, shared: true)
        XCTAssertEqual(row?.table, "journeys")
        XCTAssertEqual(try object(row), ["user_id": user, "venue_id": "rubenstein-treehouse", "tag_id": "feel-tag-01", "session_id": "abc", "target_label": "exit",
                                         "started_at": "2026-10-18T14:00:00Z", "arrived_at": "2026-10-18T14:00:14Z", "arrival_distance_m": 0.3, "shared": true,
                                         "steps": [["t": 0, "x": -1, "y": 1.1, "heading_deg": 0], ["t": 2, "x": -1, "y": 2.1, "heading_deg": 270]],
                                         "obstacles": [["x": -2.05, "y": 4.05]], "cue_latency_ms": [120, 95]])
        var unfinished = walk; unfinished.arrivedAt = nil; unfinished.arrivalDistanceM = 3.6
        let stopped = try object(SupabaseRows.journey(userId: user, venueId: "rubenstein-treehouse", journey: unfinished, shared: false))
        XCTAssertEqual(stopped["arrived_at"] as? NSNull, NSNull(), "stopped short: arrived_at is null, as the table allows")
        XCTAssertEqual(stopped["arrival_distance_m"] as? Double, 3.6)
    }

    func testRowsTheTablesWouldRefuseAreDroppedOnThePhone() {
        XCTAssertNil(SupabaseRows.find(userId: "not-a-uuid", objectName: "keys", place: "desk", confidence: 0.9, foundAt: seenAt))
        XCTAssertNil(SupabaseRows.find(userId: user, objectName: "   ", place: "desk", confidence: 0.9, foundAt: seenAt), "an empty name")
        XCTAssertNil(SupabaseRows.find(userId: user, objectName: String(repeating: "k", count: 65), place: "desk", confidence: 0.9, foundAt: seenAt))
        XCTAssertNil(SupabaseRows.find(userId: user, objectName: "keys", place: String(repeating: "p", count: 201), confidence: 0.9, foundAt: seenAt))
        XCTAssertNil(SupabaseRows.find(userId: user, objectName: "keys", place: "desk", confidence: 1.5, foundAt: seenAt))
        let far = RoomAnchor(label: "exit", position: Vector3(101, 0, 0), confidence: 0.9, seenAt: seenAt)
        XCTAssertNil(SupabaseRows.anchor(userId: user, venueId: "harvard-yard", tagId: "feel-tag-01", anchor: far, shared: true), "beyond the table's 100 m")
        XCTAssertNil(SupabaseRows.anchor(userId: user, venueId: "harvard-yard", tagId: "Feel Tag 01", anchor: exit, shared: true), "tag ids are lower-case slugs")
        XCTAssertNil(SupabaseRows.anchor(userId: user, venueId: "", tagId: "feel-tag-01", anchor: exit, shared: true))
        let unnormalized = RoomAnchor(label: "Exit", position: Vector3(-1, 1, 0), confidence: 0.9, seenAt: seenAt)
        XCTAssertNil(SupabaseRows.anchor(userId: user, venueId: "harvard-yard", tagId: "feel-tag-01", anchor: unnormalized, shared: true), "labels are stored normalized")
        var walk = Journey(tagId: "feel-tag-01", sessionId: "s", startedAt: seenAt, targetLabel: "exit", steps: [], arrivalDistanceM: 0)
        XCTAssertNil(SupabaseRows.journey(userId: user, venueId: "harvard-yard", journey: walk, shared: true), "no steps, no walk")
        walk.steps = [Journey.Step(t: 0, x: 0, y: 1, headingDeg: 0)]; walk.arrivalDistanceM = nil
        XCTAssertNil(SupabaseRows.journey(userId: user, venueId: "harvard-yard", journey: walk, shared: true), "the table needs the arrival distance")
        walk.arrivalDistanceM = 250
        XCTAssertNil(SupabaseRows.journey(userId: user, venueId: "harvard-yard", journey: walk, shared: true), "farther than the table allows")
    }

    // MARK: The wire
    func testARowIsPostedWithTheApiKeyAndTheUsersToken() throws {
        let access = try signIn()
        let writer = makeWriter()
        XCTAssertTrue(writer.isReady); XCTAssertEqual(writer.userId, user)
        StubURLProtocol.handler = { _, _ in (201, Data()) }
        writer.upload(find: "keys", place: "lab bench by the window", confidence: 0.9, foundAt: seenAt)
        waitUntil(writer.status.sent == 1)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://kgdt.supabase.co/rest/v1/confirmed_finds")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_0123456789abcdef")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(access)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=minimal")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try json(StubURLProtocol.lastBody)["object_name"] as? String, "keys")
        XCTAssertEqual(writer.status, SupabaseWriter.Status(sent: 1, failed: 0, skipped: 0, lastError: nil))
        XCTAssertEqual(writer.statusReport["user_id"] as? String, user)
        XCTAssertEqual(writer.statusReport["venue"] as? String, "harvard-yard", "the explicitly selected venue")
    }

    func testAnExpiredTokenIsRefreshedBeforeTheRowGoes() throws {
        let old = try signIn(exp: -10, tag: "old")
        let fresh = token(sub: user, exp: seenAt.timeIntervalSince1970 + 3600, tag: "new")
        let writer = makeWriter()
        var calls: [(location: String, authorization: String?)] = []
        StubURLProtocol.handler = { request, body in
            calls.append((self.location(request), request.value(forHTTPHeaderField: "Authorization")))
            guard request.url!.path.hasSuffix("auth/v1/token") else { return (201, Data()) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_0123456789abcdef")
            XCTAssertEqual((try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: String], ["refresh_token": "r1"])
            return (200, Data(#"{"access_token":"\#(fresh)","refresh_token":"r2","user":{"email":"ben@example.com"}}"#.utf8))
        }
        writer.upload(find: "keys", place: "desk", confidence: 0.9, foundAt: seenAt)
        waitUntil(writer.status.sent == 1)
        XCTAssertEqual(calls.map { $0.location }, ["/auth/v1/token?grant_type=refresh_token", "/rest/v1/confirmed_finds"])
        XCTAssertEqual(calls.last?.authorization, "Bearer \(fresh)")
        XCTAssertNotEqual(old, fresh)
        XCTAssertEqual(store.load(), AuthSessionTokens(accessToken: fresh, refreshToken: "r2", email: "ben@example.com"), "the new tokens replace the old ones for the sign-in too")
    }

    func testARefusedTokenIsRefreshedOnceAndTheRowSentAgain() throws {
        let access = try signIn()
        let writer = makeWriter()
        var posts = 0, refreshes = 0
        StubURLProtocol.handler = { request, _ in
            if request.url!.path.hasSuffix("auth/v1/token") { refreshes += 1; return (200, Data(#"{"access_token":"\#(access)","refresh_token":"r2"}"#.utf8)) }
            posts += 1
            return (401, Data(#"{"message":"JWT expired"}"#.utf8))
        }
        writer.upload(anchor: exit, tagId: "feel-tag-01")
        waitUntil(writer.status.failed == 1)
        XCTAssertEqual(posts, 2, "once before the refresh, once after; never a loop")
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(writer.status.lastError, "anchors 401: JWT expired")
        StubURLProtocol.handler = { request, _ in (request.url!.path.hasSuffix("auth/v1/token") ? 400 : 401, Data(#"{"error_code":"refresh_token_not_found"}"#.utf8)) }
        writer.upload(anchor: exit, tagId: "feel-tag-01")
        waitUntil(writer.status.failed == 2)
        XCTAssertEqual(writer.status.lastError, "anchors: the session expired; sign in again")
    }

    func testTheDatabasesRefusalIsCountedWithItsMessage() throws {
        _ = try signIn()
        let writer = makeWriter()
        StubURLProtocol.handler = { _, _ in (409, Data(#"{"code":"23503","message":"insert or update on table \"anchors\" violates foreign key constraint"}"#.utf8)) }
        writer.upload(anchor: exit, tagId: "feel-tag-01")
        waitUntil(writer.status.failed == 1)
        XCTAssertEqual(writer.status.lastError, "anchors 409: insert or update on table \"anchors\" violates foreign key constraint")
        XCTAssertEqual(writer.statusReport["failed"] as? Int, 1)
    }

    func testNothingLeavesWithoutASignInOrSettingsAndTheReasonIsReported() {
        StubURLProtocol.handler = { _, _ in XCTFail("no request without a session"); return (500, Data()) }
        let writer = makeWriter()
        XCTAssertFalse(writer.isReady)
        writer.upload(find: "keys", place: "desk", confidence: 0.9, foundAt: seenAt)
        XCTAssertEqual(writer.status, SupabaseWriter.Status(sent: 0, failed: 0, skipped: 1, lastError: "not signed in"))
        let unconfigured = SupabaseWriter(configuration: nil, store: store, session: session())
        unconfigured.upload(journey: Journey(tagId: "feel-tag-01", sessionId: "s", startedAt: seenAt, targetLabel: "exit"))
        XCTAssertEqual(unconfigured.status, SupabaseWriter.Status(sent: 0, failed: 0, skipped: 1, lastError: "no Supabase settings in this build"))
        XCTAssertEqual(unconfigured.statusReport["configured"] as? Bool, false)
        XCTAssertEqual(unconfigured.statusReport["signed_in"] as? Bool, false)
    }

    func testARowOutsideTheTablesLimitsIsSkippedNotSent() throws {
        _ = try signIn()
        let writer = makeWriter()
        StubURLProtocol.handler = { _, _ in XCTFail("a row the table would refuse never leaves"); return (500, Data()) }
        writer.upload(anchor: RoomAnchor(label: "exit", position: Vector3(500, 0, 0), confidence: 0.9, seenAt: seenAt), tagId: "feel-tag-01")
        XCTAssertEqual(writer.status, SupabaseWriter.Status(sent: 0, failed: 0, skipped: 1, lastError: "anchor row is outside the table's limits"))
    }

    func testUploadsAndSharingDefaultOffEvenWhenSignedIn() throws {
        _=try signIn()
        let writer=makeWriter(consent:false)
        StubURLProtocol.handler={ _,_ in XCTFail("no network before upload consent"); return (500,Data()) }
        XCTAssertFalse(writer.uploadsEnabled); XCTAssertFalse(writer.sharesRoomMemory); XCTAssertFalse(writer.isReady)
        writer.upload(find:"keys",place:"desk",confidence:0.9,foundAt:seenAt)
        writer.upload(anchor:exit,tagId:"feel-tag-01")
        let map=try XCTUnwrap(RoomMap(cellSize:0.1,originX:0,originY:0,width:1,height:1,cells:[.free]))
        writer.upload(structure:map,tagId:"feel-tag-01",seenAt:seenAt)
        writer.upload(journey:Journey(tagId:"feel-tag-01",sessionId:"s",startedAt:seenAt,targetLabel:"exit"))
        XCTAssertEqual(writer.status.skipped,4)
    }
    func testUploadConsentDoesNotEnablePublicRoomSharing() throws {
        _=try signIn(); let writer=makeWriter()
        StubURLProtocol.handler={ _,_ in (201,Data()) }
        writer.upload(anchor:exit,tagId:"feel-tag-01")
        waitUntil(writer.status.sent==1)
        XCTAssertEqual(try json(StubURLProtocol.lastBody)["shared"] as? Bool,false)
        writer.setSharingEnabled(true)
        writer.upload(anchor:exit,tagId:"feel-tag-01")
        waitUntil(writer.status.sent==2)
        XCTAssertEqual(try json(StubURLProtocol.lastBody)["shared"] as? Bool,true)
    }
    func testMissingVenueSkipsAllSpatialUploads() throws {
        _=try signIn(); let writer=makeWriter(selectedVenue:false)
        StubURLProtocol.handler={ _,_ in XCTFail("no invented spatial venue"); return (500,Data()) }
        writer.upload(anchor:exit,tagId:"feel-tag-01")
        let map=try XCTUnwrap(RoomMap(cellSize:0.1,originX:0,originY:0,width:1,height:1,cells:[.free]))
        writer.upload(structure:map,tagId:"feel-tag-01",seenAt:seenAt)
        writer.upload(journey:Journey(tagId:"feel-tag-01",sessionId:"s",startedAt:seenAt,targetLabel:"exit"))
        XCTAssertEqual(writer.status.skipped,3)
        XCTAssertEqual(writer.statusReport["venue"] as? String,"none")
    }
    private func delayedRefresh(change: (SupabaseWriter) throws -> Void) throws {
        _=try signIn(exp:-10,tag:"old"); let writer=makeWriter()
        let fresh=token(sub:user,exp:seenAt.timeIntervalSince1970+3600,tag:"fresh")
        let started=expectation(description:"refresh started"),release=DispatchSemaphore(value:0)
        defer { release.signal() }
        StubURLProtocol.handler={ request,_ in
            guard request.url!.path.hasSuffix("auth/v1/token") else { XCTFail("stale refresh must not send a row"); return (500,Data()) }
            started.fulfill(); _=release.wait(timeout:.now()+3)
            return (200,Data(#"{"access_token":"\#(fresh)","refresh_token":"r2"}"#.utf8))
        }
        writer.upload(find:"keys",place:"desk",confidence:0.9,foundAt:seenAt)
        wait(for:[started],timeout:2)
        try change(writer)
        let expected=store.load()
        release.signal()
        waitUntil(writer.status.skipped==1)
        XCTAssertEqual(store.load(),expected,"late refresh cannot resurrect or replace the current sign-in")
        XCTAssertEqual(writer.status.sent,0)
    }
    func testRefreshAfterSignOutCannotRestoreCredentialsOrRetry() throws {
        try delayedRefresh { _ in self.store.clear() }
    }
    func testRefreshAfterAccountSwitchCannotReplaceNewCredentialsOrRetry() throws {
        try delayedRefresh { _ in
            let other=self.token(sub:"d4e5f607-1234-4321-8765-abcdef123456",exp:self.seenAt.timeIntervalSince1970+3600)
            try self.store.save(AuthSessionTokens(accessToken:other,refreshToken:"other-refresh",email:"other@example.com"))
        }
    }
    func testConsentWithdrawalCancelsPendingRefreshAndRetry() throws {
        try delayedRefresh { writer in writer.setUploadsEnabled(false) }
    }
    func testSharingWithdrawalCannotRetryAnAlreadySharedRow() throws {
        _=try signIn(exp:-10); let writer=makeWriter(); writer.setSharingEnabled(true)
        let started=expectation(description:"refresh started"),release=DispatchSemaphore(value:0)
        defer { release.signal() }
        let fresh=token(sub:user,exp:seenAt.timeIntervalSince1970+3600)
        StubURLProtocol.handler={ request,_ in
            guard request.url!.path.hasSuffix("auth/v1/token") else { XCTFail("shared row cannot retry after sharing is withdrawn"); return (500,Data()) }
            started.fulfill(); _=release.wait(timeout:.now()+3)
            return (200,Data(#"{"access_token":"\#(fresh)","refresh_token":"r2"}"#.utf8))
        }
        writer.upload(anchor:exit,tagId:"feel-tag-01")
        wait(for:[started],timeout:2); writer.setSharingEnabled(false); release.signal()
        waitUntil(writer.status.skipped==1)
        XCTAssertEqual(writer.status.sent,0)
    }
    func testConcurrentExpiredUploadsShareOneRefresh() throws {
        _=try signIn(exp:-10); let writer=makeWriter()
        let fresh=token(sub:user,exp:seenAt.timeIntervalSince1970+3600)
        var refreshes=0
        StubURLProtocol.handler={ request,_ in
            if request.url!.path.hasSuffix("auth/v1/token") {
                refreshes += 1
                return (200,Data(#"{"access_token":"\#(fresh)","refresh_token":"r2"}"#.utf8))
            }
            return (201,Data())
        }
        writer.upload(find:"keys",place:"desk",confidence:0.9,foundAt:seenAt)
        writer.upload(find:"bottle",place:"desk",confidence:0.9,foundAt:seenAt)
        waitUntil(writer.status.sent==2)
        XCTAssertEqual(refreshes,1)
    }

    // MARK: From the app
    func testConfirmedAnchorsKeptVisitsAndKeptJourneysLeaveThroughTheUploader() throws {
        let uploader = RecordingUploader()
        let memory = RoomMemory(store: RoomMemoryStore(directory: directory.appendingPathComponent("RoomMemory")), now: { self.seenAt })
        memory.uploader = uploader
        let sighting = TagSighting(tagId: "feel-tag-01", frame: tagFrame, worldEpoch: 1, timestamp: 1)
        memory.sawTag(sighting)
        XCTAssertNotNil(memory.confirm(HeldTarget(position: Vector3(0, 0, -2), label: "Desk", worldEpoch: 1, setAt: 0), confidence: 0.9))
        XCTAssertEqual(uploader.anchors.map { $0.tagId }, ["feel-tag-01"])
        XCTAssertEqual(uploader.anchors.first?.anchor, RoomAnchor(label: "desk", position: Vector3(0, 1, 0), confidence: 0.9, seenAt: seenAt),
                       "normalized label, in the tag frame: 2 m ahead of the camera is 1 m out from the tag on the wall 3 m away")
        let map = try XCTUnwrap(RoomMap(cellSize: 0.1, originX: 0, originY: 0, width: 10, height: 10, cells: [FloorGrid.State](repeating: .free, count: 100)))
        XCTAssertTrue(memory.keepStructure(map, tagId: "feel-tag-01"))
        XCTAssertEqual(uploader.structures.map { $0.tagId }, ["feel-tag-01"])
        XCTAssertEqual(uploader.structures.first?.map, map); XCTAssertEqual(uploader.structures.first?.seenAt, seenAt)
        let glance = try XCTUnwrap(RoomMap(cellSize: 0.1, originX: 0, originY: 0, width: 4, height: 4, cells: [FloorGrid.State](repeating: .free, count: 16)))
        XCTAssertFalse(memory.keepStructure(glance, tagId: "feel-tag-01"))
        XCTAssertEqual(uploader.structures.count, 1, "a session that only glanced at the room is not a visit, here or there")

        let log = JourneyLog(directory: directory.appendingPathComponent("Journeys"), exportFile: directory.appendingPathComponent("journeys.json"), now: { self.seenAt })
        log.uploader = uploader
        XCTAssertTrue(log.begin(targetLabel: "exit", target: Vector3(-1, 0, -2), sighting: sighting, startUptime: 10))
        log.record(pose: CameraPose(position: Vector3(0, 0, 0)), now: 10)
        log.record(pose: CameraPose(position: Vector3(0, 0, -1)), now: 11)
        let kept = try XCTUnwrap(log.end(arrived: true, pose: CameraPose(position: Vector3(-1, 0, -2)), now: 12))
        XCTAssertEqual(uploader.journeys, [kept])
        log.begin(targetLabel: "exit", target: Vector3(-1, 0, -2), sighting: sighting, startUptime: 20)
        XCTAssertNil(log.end(arrived: false, pose: nil, now: 20.1))
        XCTAssertEqual(uploader.journeys.count, 1, "a walk too short to keep is not uploaded either")
    }

    func testFoundItWithoutVenueKeepsLocalAnchorButDoesNotInventHistory() throws {
        let uploader=RecordingUploader()
        let memory=RoomMemory(store:RoomMemoryStore(directory:directory),now:{ self.seenAt })
        let model=LanternModel(voice:RealtimeVoiceSession(configuration:nil,speaksLocally:false),chalkStore:MemoryChalkStore(),
                              gatewayFactory:{ _ in StubChatGateway() },localFinder:StubLocalFinder(),roomMemory:memory,uploader:uploader,
                              venueInfo:VenueInfo(store:VenuePackStore(directory:directory.appendingPathComponent("EmptyVenue"))))
        XCTAssertNil(model.venueInfo.pack,"this fixture requires no selected venue")
        let desk=HeldTarget(position:Vector3(0,0,-2),label:"desk",worldEpoch:1,setAt:0)
        model.handleWhereIs(.placed(desk),thing:"desk",frame:makeFrame())
        var reply=model.performVoiceCommand(.foundIt)
        XCTAssertTrue(uploader.finds.isEmpty,"never invent a venue for history")
        XCTAssertEqual(reply["history"] as? String,"Cloud history was not updated. Upload consent, sign-in and a selected venue are required.")
        XCTAssertTrue(uploader.anchors.isEmpty,"no tag means no local anchor")

        model.handleWhereIs(.placed(desk),thing:"desk",frame:makeFrame())
        memory.sawTag(TagSighting(tagId:"feel-tag-01",frame:tagFrame,worldEpoch:1,timestamp:1))
        reply=model.performVoiceCommand(.foundIt)
        XCTAssertEqual(reply["remembered"] as? Bool,true)
        XCTAssertEqual(memory.anchors.map(\.label),["desk"],"local memory still works without a cloud venue")
        XCTAssertTrue(uploader.finds.isEmpty)
        XCTAssertEqual(uploader.anchors.map { $0.anchor.label },["desk"],"the production writer independently skips this hook without a venue")
        XCTAssertEqual(LanternModel.findPlace(venue:"Harvard Yard",tag:(id:"feel-tag-01",distance:2.4)),"Harvard Yard, about 2 m from tag feel-tag-01")
        XCTAssertEqual(LanternModel.findPlace(venue:"Harvard Yard",tag:nil),"Harvard Yard")
    }

    func testTheSignInsTokenNamesTheUser() {
        XCTAssertEqual(SupabaseConfiguration.claims(of: token(sub: user, exp: 1))?["sub"] as? String, user)
        XCTAssertNil(SupabaseConfiguration.claims(of: "sb_publishable_0123456789abcdef"), "a publishable key is not a JWT")
        XCTAssertNil(SupabaseConfiguration.claims(of: "a.b.c"))
    }
}
