import XCTest
import FeelCore
@testable import Lantern

/// Records request bodies and lets each test decide when and how a reply arrives.
final class StubChatGateway: ChatGateway {
    private(set) var bodies: [Data] = []
    private var pending: [(Result<String, Error>) -> Void] = []
    var calls: Int { bodies.count }
    func complete(body: Data, timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionTask? {
        bodies.append(body); pending.append(completion); return nil
    }
    func reply(_ index: Int, _ result: Result<String, Error>) { pending[index](result) }
}

final class WhereIsServiceTests: XCTestCase {
    private let found = #"{"found": true, "label": "registration desk", "box": [0.4, 0.4, 0.6, 0.6], "confidence": 0.82}"#
    private func snapshot(confidence: UInt8 = 2) -> FrameSnapshot {
        let width = 20, height = 10
        return FrameSnapshot(timestamp: 3, worldEpoch: 1, pose: .identity, intrinsics: CameraIntrinsics(fx: 10, fy: 10, cx: 10, cy: 5),
                             depth: DepthGrid(width: width, height: height, depths: Array(repeating: 2.0, count: width * height),
                                              confidence: Array(repeating: confidence, count: width * height)),
                             jpegBase64: "QUJD")
    }
    private func run(reply: Result<String, Error>, confidence: UInt8 = 2) -> WhereIsOutcome? {
        let gateway = StubChatGateway()
        let service = WhereIsService(gateway: gateway, model: "openai/gpt-6.1-sol")
        let done = expectation(description: "outcome")
        var outcome: WhereIsOutcome?
        service.find("desk", snapshot: snapshot(confidence: confidence)) { outcome = $0; done.fulfill() }
        gateway.reply(0, reply)
        wait(for: [done], timeout: 2)
        return outcome
    }

    func testFoundPlacesTarget() throws {
        guard case .placed(let target)? = run(reply: .success(found)) else { return XCTFail("expected a placed target") }
        XCTAssertEqual(target.label, "registration desk")
        XCTAssertEqual(target.position.z, -2, accuracy: 1e-6)
        XCTAssertEqual(target.worldEpoch, 1)
    }
    func testNotFoundIsNotVisible() {
        XCTAssertEqual(run(reply: .success(#"{"found": false, "label": "", "box": null, "confidence": 0}"#)), .notVisible)
    }
    func testNoDepthGivesNoDepthOutcome() {
        XCTAssertEqual(run(reply: .success(found), confidence: 0), .noDepth)
    }
    func testMalformedReplyIsFailed() {
        XCTAssertEqual(run(reply: .success("The desk is on your right.")), .failed)
    }
    func testGatewayErrorIsFailed() {
        XCTAssertEqual(run(reply: .failure(GatewayError.http(500))), .failed)
    }
    func testRequestAsksWhereIsThing() throws {
        let gateway = StubChatGateway()
        WhereIsService(gateway: gateway, model: "openai/gpt-6.1-sol").find("desk", snapshot: snapshot()) { _ in }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(gateway.bodies.first)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "openai/gpt-6.1-sol")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts[0]["text"] as? String, "Where is the desk?")
        XCTAssertEqual((parts[1]["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,QUJD")
    }
    func testSecondRequestCancelsFirst() {
        let gateway = StubChatGateway()
        let service = WhereIsService(gateway: gateway, model: "m")
        var outcomes: [WhereIsOutcome] = []
        let done = expectation(description: "second outcome")
        service.find("desk", snapshot: snapshot()) { outcomes.append($0) }
        service.find("chair", snapshot: snapshot()) { outcomes.append($0); done.fulfill() }
        gateway.reply(0, .success(found))   // late answer to the cancelled first request
        gateway.reply(1, .success(#"{"found": true, "label": "chair", "box": [0.4, 0.4, 0.6, 0.6], "confidence": 0.9}"#))
        wait(for: [done], timeout: 2)
        XCTAssertEqual(outcomes.count, 1)
        guard case .placed(let target)? = outcomes.first else { return XCTFail("expected the second request's target") }
        XCTAssertEqual(target.label, "chair")
    }
}
