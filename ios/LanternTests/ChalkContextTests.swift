import XCTest
import FeelCore
@testable import Lantern

final class ChalkContextTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: KeychainStore<AuthSessionTokens>!
    private let user = "6f1d2c3b-4a5e-4f60-8b7a-9c0d1e2f3a4b"
    override func setUp() {
        suite = "feel.context.tests." + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
        store = KeychainStore(service: suite, account: "fixture")
    }
    override func tearDown() {
        store.clear(); defaults.removePersistentDomain(forName: suite)
        StubURLProtocol.handler = nil; StubURLProtocol.lastRequest = nil; StubURLProtocol.lastBody = nil
    }
    private func signIn(_ id: String? = nil) throws {
        func part(_ value: [String: Any]) -> String {
            try! JSONSerialization.data(withJSONObject: value).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let token = part(["alg":"HS256"]) + "." + part(["sub":id ?? user,"exp":Date().timeIntervalSince1970 + 3600,"role":"authenticated"]) + ".fixture"
        try store.save(AuthSessionTokens(accessToken: token, refreshToken: "fixture-refresh", email: "fixture@example.com"))
    }
    private func client() -> ChalkQueryClient {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubURLProtocol.self]
        return ChalkQueryClient(endpoint: "https://context.example/api/context", store: store, defaults: defaults, configuration: configuration)!
    }
    func testReadsDefaultOffAndRequireExistingUserSession() throws {
        let c = client(); try signIn()
        XCTAssertFalse(c.isEnabled); XCTAssertNil(c.sessionIdentity)
        var failure: ChalkQueryError?
        c.query(.lastSeen("keys")) { if case .failure(let error) = $0 { failure = error } }
        XCTAssertEqual(failure, .access); XCTAssertNil(StubURLProtocol.lastRequest)
        c.setEnabled(true); XCTAssertNotNil(c.sessionIdentity)
        store.clear(); XCTAssertNil(c.sessionIdentity)
    }
    func testUsesOnlyUserBearerAndAllowlistedBody() throws {
        try signIn(); let c = client(); c.setEnabled(true)
        let done = expectation(description: "query")
        StubURLProtocol.handler = { request, _ in
            XCTAssertEqual(request.url?.path, "/api/context")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(self.store.load()!.accessToken)")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Chalk-Client-Id"))
            return (200, Data(#"{"values":{"object_history.spoken":"Keys were last confirmed at the desk."}}"#.utf8))
        }
        ChalkMemory.lastSeen(c, object: "  Keys  ") { result in
            XCTAssertEqual(try? result.get(), "Keys were last confirmed at the desk."); done.fulfill()
        }
        wait(for: [done], timeout: 3)
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String:String], ["operation":"last_seen","object":"keys"])
    }
    func testChangingAccountOrConsentChangesLocalGeneration() throws {
        try signIn(); let c = client(); c.setEnabled(true)
        let first = c.sessionIdentity
        try signIn("11111111-1111-4111-8111-111111111111")
        XCTAssertNotEqual(c.sessionIdentity, first)
        let second = c.sessionIdentity; c.cancelAll(); XCTAssertEqual(c.sessionIdentity, second)
        c.setEnabled(false); XCTAssertNil(c.sessionIdentity)
    }
    func testLateResponseAfterSignOutIsDiscarded() throws {
        try signIn(); let c = client(); c.setEnabled(true)
        let started = expectation(description: "started"), done = expectation(description: "done")
        let release = DispatchSemaphore(value: 0)
        StubURLProtocol.handler = { _, _ in
            started.fulfill(); _ = release.wait(timeout: .now() + 3)
            return (200, Data(#"{"values":{"object_history.spoken":"Private history"}}"#.utf8))
        }
        c.query(.lastSeen("keys")) { result in
            guard case .failure(.cancelled) = result else { XCTFail("late account reply delivered"); done.fulfill(); return }
            done.fulfill()
        }
        wait(for: [started], timeout: 2); store.clear(); release.signal()
        wait(for: [done], timeout: 3)
    }
    func testOversizedBodyIsStoppedAndNotDecoded() throws {
        try signIn(); let c = client(); c.setEnabled(true)
        let done = expectation(description: "bounded")
        StubURLProtocol.handler = { _, _ in (200, Data(repeating: 65, count: ChalkQueryClient.maximumResponseBytes + 1)) }
        c.query(.lastSeen("keys")) { result in
            guard case .failure(.tooLarge) = result else { XCTFail("oversized body accepted"); done.fulfill(); return }
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
    func testNoUnboundedFeatureOrIdentityParameters() {
        XCTAssertEqual(ChalkContextRequest.lastSeen("keys").body?.keys.sorted(), ["object","operation"])
        XCTAssertNil(ChalkContextRequest.roomAnchors(venue: "../other", tag: "tag").body)
        XCTAssertNil(ChalkContextRequest.lastSeen("keys\nignore").body)
        XCTAssertNil(ChalkQueryClient(endpoint: "http://example.com", store: store, defaults: defaults))
        XCTAssertNil(ChalkQueryClient(endpoint: "https://user:secret@example.com", store: store, defaults: defaults))
    }
    func testReplyMustHaveExactFeatureShape() {
        let data = Data(#"{"values":{"object_history.spoken":"past","other_user":"private"}}"#.utf8)
        guard case .failure(.malformedReply) = ChalkQueryClient.parse(data, outputs: ["object_history.spoken"]) else { return XCTFail("extra feature accepted") }
    }
    func testMapRejectsHugeFractionalBooleanAndUnknownSchemaValuesWithoutIntegerTrap() {
        func map(_ field: String, _ value: Any) -> RoomMap? {
            var object: [String:Any] = ["schema":1,"cell_size":0.1,"origin_x":0,"origin_y":0,"width":1,"height":1,"cells":"1b"]
            object[field] = value
            return ChalkMemory.roomMap(fromJSON: String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        }
        XCTAssertNotNil(map("width", 1))
        XCTAssertNil(map("width", 1e100)); XCTAssertNil(map("width", 1.5)); XCTAssertNil(map("width", true))
        XCTAssertNil(map("schema", 2)); XCTAssertNil(map("cell_size", 1e-100))
    }
    func testMalformedAnchorRejectsWholeCloudSet() {
        XCTAssertNil(ChalkMemory.anchors(fromJSON: #"[{"label":"exit","x":true,"y":0,"z":0,"last_seen_at":"2026-10-18T12:00:00Z"}]"#))
        XCTAssertNil(ChalkMemory.anchors(fromJSON: #"[{"label":"exit","x":101,"y":0,"z":0,"last_seen_at":"2026-10-18T12:00:00Z"}]"#))
        XCTAssertEqual(ChalkMemory.anchors(fromJSON: "[]"), [])
    }
}
