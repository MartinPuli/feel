import XCTest
import FeelCore
@testable import Lantern

/// A query client fed by hand: records what was asked and answers when the test says.
final class ScriptedChalkQuery: ChalkQuerying {
    struct Call { let name: String; let inputs: [String: Any]; let outputs: [String] }
    private(set) var calls: [Call] = []
    private var completions: [(Result<[String: Any], ChalkQueryError>) -> Void] = []
    func query(_ name: String, inputs: [String: Any], outputs: [String], completion: @escaping (Result<[String: Any], ChalkQueryError>) -> Void) {
        calls.append(Call(name: name, inputs: inputs, outputs: outputs)); completions.append(completion)
    }
    /// Answers the oldest pending query.
    func answer(_ result: Result<[String: Any], ChalkQueryError>) { completions.removeFirst()(result) }
    var pending: Int { completions.count }
}

/// The read side of the shared memory: the phone's online query has the wire shape of chalk/feel_chalk/context.py,
/// the two named queries are keyed the same way, replies are checked rather than guessed at, and the assistant's
/// last_seen tool speaks Chalk's sentence as a past record.
final class ChalkContextTests: XCTestCase {
    private let token = String(repeating: "t", count: 24)
    private let user = "6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b"
    private let merged = RoomMap(cellSize: 0.1, originX: -0.2, originY: 0, width: 8, height: 6, encoded: "28f2b10f2u6b")!
    private var access: ChalkQueryAccess { ChalkQueryAccess(engine: "https://engine.example.test", environmentId: "env1", clientId: "id1", token: token)! }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
    override func tearDown() { StubURLProtocol.handler = nil; StubURLProtocol.lastRequest = nil; StubURLProtocol.lastBody = nil }
    private func client(now: Date = Date()) -> ChalkQueryClient { ChalkQueryClient(access: access, session: session(), now: { now }) }
    private func json(_ data: Data?) throws -> NSDictionary { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? NSDictionary) }
    private func reply(_ data: [[String: Any]], errors: [[String: Any]]? = nil) -> Data {
        var object: [String: Any] = ["data": data]
        if let errors { object["errors"] = errors }
        return try! JSONSerialization.data(withJSONObject: object)
    }
    private func run<T>(_ start: (@escaping (Result<T, ChalkQueryError>) -> Void) -> Void) -> Result<T, ChalkQueryError>? {
        let done = expectation(description: "reply")
        var received: Result<T, ChalkQueryError>?
        start { received = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return received
    }

    // MARK: Access from the build config
    func testAccessComesFromTheBuildConfigAndRefusesWhatIsNotAnHTTPSEngineOrAToken() {
        let info: [String: Any] = ["FEEL_CHALK_QUERY_ENGINE": "https://engine.example.test", "FEEL_CHALK_ENV": "env1",
                                   "FEEL_CHALK_CLIENT_ID": "id1", "FEEL_CHALK_QUERY_TOKEN": token]
        XCTAssertEqual(ChalkQueryAccess.fromInfo(info), access)
        XCTAssertNil(ChalkQueryAccess.fromInfo([:]), "a build without the lines has no access")
        var unexpanded = info; unexpanded["FEEL_CHALK_QUERY_TOKEN"] = "$(FEEL_CHALK_QUERY_TOKEN)"
        XCTAssertNil(ChalkQueryAccess.fromInfo(unexpanded), "an unexpanded build setting is no token")
        var plain = info; plain["FEEL_CHALK_QUERY_ENGINE"] = "http://engine.example.test"
        XCTAssertNil(ChalkQueryAccess.fromInfo(plain))
        var short = info; short["FEEL_CHALK_QUERY_TOKEN"] = "short"
        XCTAssertNil(ChalkQueryAccess.fromInfo(short))
        var noClient = info; noClient.removeValue(forKey: "FEEL_CHALK_CLIENT_ID")
        XCTAssertNil(ChalkQueryAccess.fromInfo(noClient)?.clientId, "the client id header is optional")
        XCTAssertNotNil(ChalkQueryAccess.fromInfo(noClient))
    }

    func testAnExpiredTokenIsNotSentAndAnOpaqueOneIs() throws {
        func jwt(exp: TimeInterval) -> String {
            func part(_ object: [String: Any]) -> String {
                try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            }
            return part(["alg": "HS256"]) + "." + part(["exp": exp, "sub": "svc"]) + ".sig"
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = ChalkQueryAccess(engine: "https://engine.example.test", environmentId: "env1", clientId: nil, token: jwt(exp: now.timeIntervalSince1970 - 1))!
        XCTAssertEqual(expired.expiresAt, now.addingTimeInterval(-1))
        XCTAssertFalse(expired.isUsable(at: now))
        XCTAssertTrue(ChalkQueryAccess(engine: "https://e.test", environmentId: "env1", clientId: nil, token: jwt(exp: now.timeIntervalSince1970 + 60))!.isUsable(at: now))
        XCTAssertNil(access.expiresAt); XCTAssertTrue(access.isUsable(at: now), "an opaque token is tried; the server decides")
        StubURLProtocol.handler = { _, _ in (200, Data()) }
        let result: Result<[String: Any], ChalkQueryError>? = run { ChalkQueryClient(access: expired, session: self.session(), now: { now }).query("last_seen", inputs: [:], outputs: [], completion: $0) }
        XCTAssertEqual(try XCTUnwrap(result).failureValue, .access)
        XCTAssertNil(StubURLProtocol.lastRequest, "no request for a token known to be expired")
    }

    // MARK: Wire shape
    func testLastSeenIsOneOnlineQueryWithChalksHeadersAndKey() throws {
        StubURLProtocol.handler = { _, _ in (200, self.reply([["field": "object_history.spoken", "value": "Keys: last confirmed at the kitchen table, 2 hours ago."]])) }
        let result: Result<String, ChalkQueryError>? = run { ChalkContext.lastSeen(self.client(), userId: self.user, object: "  My   Keys ", completion: $0) }
        XCTAssertEqual(try XCTUnwrap(result).get(), "Keys: last confirmed at the kitchen table, 2 hours ago.")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://engine.example.test/v1/query/online", "the environment's engine answers, not api.chalk.ai")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Chalk-Env-Id"), "env1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Chalk-Client-Id"), "id1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Chalk-Deployment-Type"), "engine")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try json(StubURLProtocol.lastBody), ["inputs": ["object_history.id": "\(user):my keys"], "outputs": ["object_history.spoken"], "query_name": "last_seen"])
    }

    func testRepliesAreCheckedNotGuessed() throws {
        func failure(_ status: Int, _ body: Data) throws -> ChalkQueryError {
            StubURLProtocol.handler = { _, _ in (status, body) }
            let result: Result<String, ChalkQueryError>? = run { ChalkContext.lastSeen(self.client(), userId: self.user, object: "keys", completion: $0) }
            return try XCTUnwrap(XCTUnwrap(result).failureValue)
        }
        XCTAssertEqual(try failure(401, Data("{}".utf8)), .http(401))
        XCTAssertEqual(try failure(200, Data("not json".utf8)), .malformedReply)
        XCTAssertEqual(try failure(200, reply([], errors: [["code": "401", "message": "bad token"]])), .query("401 bad token"))
        XCTAssertEqual(try failure(200, reply([["field": "object_history.spoken", "error": ["message": "no such user"]]])), .feature("object_history.spoken", "no such user"))
        XCTAssertEqual(try failure(200, reply([])), .missing("object_history.spoken"))
        XCTAssertEqual(try failure(200, reply([["field": "object_history.spoken", "value": ""]])), .malformedReply, "an empty sentence is nothing to read out")
    }

    func testRedirectsAreRefusedSoTheTokenStaysWithTheEngine() {
        let client = ChalkQueryClient(access: access)
        let done = expectation(description: "redirect")
        client.urlSession(URLSession.shared, task: URLSession.shared.dataTask(with: access.engine), willPerformHTTPRedirection: HTTPURLResponse(url: access.engine, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                          newRequest: URLRequest(url: URL(string: "https://elsewhere.test")!)) { XCTAssertNil($0); done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    // MARK: Room structure and anchors
    func testRoomStructureIsKeyedLikeTheChalkClientAndDecodesTheMergedMap() throws {
        let structure = #"{"cell_size": 0.1, "cells": "28f2b10f2u6b", "height": 6, "origin_x": -0.2, "origin_y": 0.0, "schema": 1, "width": 8}"#
        StubURLProtocol.handler = { _, _ in (200, self.reply([["field": "room_memory.structure", "value": structure], ["field": "room_memory.structure_visits", "value": 3]])) }
        let result: Result<(map: RoomMap?, visits: Int), ChalkQueryError>? = run { ChalkContext.roomStructure(self.client(), venueId: " Harvard-Yard ", tagId: "FEEL-TAG-01 ", completion: $0) }
        let shared = try XCTUnwrap(result).get()
        XCTAssertEqual(shared.map, merged, "the same map FeelCore reads from the room_maps columns")
        XCTAssertEqual(shared.visits, 3)
        XCTAssertEqual(try json(StubURLProtocol.lastBody), ["inputs": ["room_memory.id": "harvard-yard:feel-tag-01"],
                                                            "outputs": ["room_memory.structure", "room_memory.structure_visits"], "query_name": "room_structure"])
    }

    func testARoomNobodySharedIsNoMapAndAMalformedMapIsAFailure() throws {
        StubURLProtocol.handler = { _, _ in (200, self.reply([["field": "room_memory.structure", "value": NSNull()], ["field": "room_memory.structure_visits", "value": 0]])) }
        var result: Result<(map: RoomMap?, visits: Int), ChalkQueryError>? = run { ChalkContext.roomStructure(self.client(), venueId: "v", tagId: "t", completion: $0) }
        XCTAssertNil(try XCTUnwrap(result).get().map)
        XCTAssertEqual(try XCTUnwrap(result).get().visits, 0)
        StubURLProtocol.handler = { _, _ in (200, self.reply([["field": "room_memory.structure", "value": #"{"cell_size": 0.1, "cells": "3f", "height": 6, "origin_x": 0, "origin_y": 0, "width": 8}"#],
                                                              ["field": "room_memory.structure_visits", "value": 1]])) }
        result = run { ChalkContext.roomStructure(self.client(), venueId: "v", tagId: "t", completion: $0) }
        XCTAssertEqual(try XCTUnwrap(result).failureValue, .malformedReply, "48 cells promised, 3 encoded")
        StubURLProtocol.handler = { _, _ in (200, self.reply([["field": "room_memory.structure", "value": NSNull()], ["field": "room_memory.structure_visits", "value": true]])) }
        result = run { ChalkContext.roomStructure(self.client(), venueId: "v", tagId: "t", completion: $0) }
        XCTAssertEqual(try XCTUnwrap(result).failureValue, .malformedReply, "a boolean is not a count")
    }

    func testRoomAnchorsBecomeSightingsTheLocalStoreCanHold() throws {
        let targets = #"[{"label": "exit", "x": 1.5, "y": 6.0, "z": 0.0, "sightings": 4, "last_seen_at": "2026-10-17T12:00:00+00:00"}, "#
            + #"{"label": "Water Fountain", "x": -1.0, "y": 3.0, "z": 0.1, "sightings": 2, "last_seen_at": "2026-10-16T09:30:00.250000+00:00"}, {"label": "bad", "x": "no"}]"#
        StubURLProtocol.handler = { _, _ in (200, self.reply([["field": "room_memory.targets", "value": targets]])) }
        let result: Result<[RoomAnchor], ChalkQueryError>? = run { ChalkContext.roomAnchors(self.client(), venueId: "harvard-yard", tagId: "feel-tag-01", completion: $0) }
        let anchors = try XCTUnwrap(result).get()
        XCTAssertEqual(anchors.map(\.label), ["exit", "water fountain"], "a malformed item is skipped, never guessed")
        XCTAssertEqual(anchors.first?.position, Vector3(1.5, 6, 0))
        XCTAssertEqual(anchors.first?.confidence, ChalkContext.sharedConfidence)
        XCTAssertEqual(anchors.first?.seenAt, ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z"))
        XCTAssertEqual(anchors.last?.seenAt.timeIntervalSince1970 ?? 0, ISO8601DateFormatter().date(from: "2026-10-16T09:30:00Z")!.timeIntervalSince1970 + 0.25, accuracy: 0.001)
        XCTAssertEqual(try json(StubURLProtocol.lastBody)["query_name"] as? String, "room_anchors")
    }

    // MARK: The assistant's tool
    func testLastSeenCommandDecodingAndTool() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "last_seen", arguments: #"{"object":" my keys "}"#), .lastSeen("my keys"))
        for arguments in ["{}", #"{"object":""}"#, #"{"object":"\#(String(repeating: "x", count: 61))"}"#, #"{"object":"keys","extra":1}"#, #"{"object":7}"#] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: "last_seen", arguments: arguments), arguments)
        }
        let tool = try XCTUnwrap(VoiceCommand.tools.first { ($0["name"] as? String) == "last_seen" })
        XCTAssertEqual(((tool["parameters"] as? [String: Any])?["required"] as? [String]), ["object"])
        XCTAssertTrue((tool["description"] as? String)?.contains("never say the object is still there") == true)
        XCTAssertTrue(VoiceCommand.instructions.contains("last_seen"))
    }

    private func makeModel(signedIn: Bool = true, query: ChalkQuerying?) -> (LanternModel, RecordingUploader) {
        let uploader = RecordingUploader()
        uploader.ready = signedIn
        let model = LanternModel(voice: RealtimeVoiceSession(configuration: nil, speaksLocally: false), chalkStore: MemoryChalkStore(),
                                 gatewayFactory: { _ in StubChatGateway() }, localFinder: StubLocalFinder(), roomMemory: RoomMemory(store: RoomMemoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))),
                                 uploader: uploader, chalkQuery: query)
        return (model, uploader)
    }
    private func memoryStatus(_ model: LanternModel) throws -> [String: Any] { try XCTUnwrap(model.voiceSnapshot()["room_memory"] as? [String: Any]) }

    func testLastSeenNeedsASignInAndQueryAccess() throws {
        let query = ScriptedChalkQuery()
        var (model, _) = makeModel(signedIn: false, query: query)
        XCTAssertEqual(model.performVoiceCommand(.lastSeen("keys"))["error"] as? String, "Not signed in, so there is no find history to search.")
        XCTAssertEqual(query.calls.count, 0)
        (model, _) = makeModel(query: nil)
        XCTAssertTrue((model.performVoiceCommand(.lastSeen("keys"))["error"] as? String)?.contains("Chalk memory setup") == true)
        XCTAssertEqual(try memoryStatus(model)["shared_memory"] as? String, "no query access in this build")
    }

    func testLastSeenAsksChalkForThisUsersObjectAndSpeaksTheRecordAsGiven() throws {
        let query = ScriptedChalkQuery()
        let (model, uploader) = makeModel(query: query)
        let result = model.performVoiceCommand(.lastSeen("My Keys"))
        XCTAssertEqual(result["pending"] as? Bool, true)
        XCTAssertTrue((result["status"] as? String)?.contains("Say only Checking") == true)
        XCTAssertEqual(query.calls.map(\.name), ["last_seen"])
        XCTAssertEqual(query.calls.first?.inputs["object_history.id"] as? String, "\(uploader.user!):my keys")
        XCTAssertEqual(query.calls.first?.outputs, ["object_history.spoken"])
        XCTAssertEqual(try memoryStatus(model)["last_seen"] as? String, "none")
        query.answer(.success(["object_history.spoken": "My keys: last confirmed at the David Rubenstein Treehouse, about 4 m from tag feel-tag-01, 2 hours ago."]))
        XCTAssertEqual(model.lastSeenNotice, "My keys: last confirmed at the David Rubenstein Treehouse, about 4 m from tag feel-tag-01, 2 hours ago.")
        XCTAssertEqual(try memoryStatus(model)["last_seen"] as? String, model.lastSeenNotice)
        XCTAssertEqual(model.whereIsNotice, model.lastSeenNotice, "the line goes out the same way as a Where-is result")
    }

    func testALateAnswerToAnEarlierAskIsDroppedAndFailuresAreSaidPlainly() throws {
        let query = ScriptedChalkQuery()
        let (model, _) = makeModel(query: query)
        model.performVoiceCommand(.lastSeen("keys"))
        model.performVoiceCommand(.lastSeen("phone"))
        XCTAssertEqual(query.pending, 2)
        query.answer(.success(["object_history.spoken": "Keys: last confirmed at the desk, yesterday."]))
        XCTAssertNil(model.lastSeenNotice, "the answer about the keys came after the user asked about the phone")
        query.answer(.failure(.http(503)))
        XCTAssertEqual(model.lastSeenNotice, "I couldn't reach the find history just now.")
        model.performVoiceCommand(.lastSeen("keys"))
        query.answer(.failure(.access))
        XCTAssertEqual(model.lastSeenNotice, "The find history isn't available on this phone right now.")
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}
