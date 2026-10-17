import XCTest
import FeelCore
@testable import Lantern

/// The on-device finder: vocabulary gate, best detection, Vision box → placement, outcomes.
final class LocalWhereIsLogicTests: XCTestCase {
    private func outcome(of local: LocalWhereIs, thing: String, confidence: UInt8 = 2) -> WhereIsOutcome? {
        let done = expectation(description: "outcome"); var outcome: WhereIsOutcome?
        local.find(thing, snapshot: makeSnapshot(confidence: confidence)) { outcome = $0; done.fulfill() }
        wait(for: [done], timeout: 2)
        return outcome
    }

    func testBestDetectionIsPlacedUnderTheUsersWords() throws {
        var queries: [LocalQuery] = []
        let local = LocalWhereIs { query, _, completion in
            queries.append(query)
            completion([ImageDetection(label: "EXIT", box: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), confidence: 0.6),
                        ImageDetection(label: "EXIT", box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2), confidence: 0.9)])
        }
        guard case .placed(let target)? = outcome(of: local, thing: "exit") else { return XCTFail("expected a placed target") }
        XCTAssertEqual(queries, [.exitSign])
        XCTAssertEqual(target.label, "exit")
        XCTAssertEqual(target.worldEpoch, 1)
        // Box centre (0.5, 0.4) from the bottom-left → image centre column, 2 m straight ahead.
        XCTAssertEqual(target.position.x, 0, accuracy: 1e-6)
        XCTAssertEqual(target.position.z, -2, accuracy: 1e-6)
    }
    func testUnknownThingsAreUnsupportedWithoutRunningTheDetector() {
        var ran = false
        let local = LocalWhereIs { _, _, completion in ran = true; completion([]) }
        XCTAssertEqual(outcome(of: local, thing: "3D puck model"), .unsupported)
        XCTAssertFalse(ran)
    }
    func testNoDetectionIsNotVisibleAndBadDepthIsNoDepth() {
        XCTAssertEqual(outcome(of: LocalWhereIs { _, _, completion in completion([]) }, thing: "chair"), .notVisible)
        let hit = LocalWhereIs { _, _, completion in completion([ImageDetection(label: "chair", box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), confidence: 0.8)]) }
        XCTAssertEqual(outcome(of: hit, thing: "chair", confidence: 0), .noDepth)
    }
    func testQueriesTheDetectorCannotRunHereAreUnsupported() {
        XCTAssertEqual(outcome(of: LocalWhereIs { _, _, completion in completion(nil) }, thing: "chair"), .unsupported, "No Core ML weights bundled")
    }
    func testDetectorReceivesTheDecodedJpeg() {
        var received: Data?
        let local = LocalWhereIs { _, data, completion in received = data; completion([]) }
        _ = outcome(of: local, thing: "chair")
        XCTAssertEqual(received, Data("ABC".utf8))
    }
}

/// The real Vision path on a rendered photo, as it runs on the phone.
final class ObjectDetectorTests: XCTestCase {
    func testExitSignIsReadFromAPhoto() throws {
        let size = CGSize(width: 640, height: 480)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            NSString(string: "EXIT").draw(at: CGPoint(x: 200, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.red])
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let detections = try ObjectDetector().detect(jpeg: jpeg, query: .exitSign)
        let best = try XCTUnwrap(detections.max { $0.confidence < $1.confidence }, "EXIT was drawn near the top of the image")
        XCTAssertEqual(best.label, "EXIT")
        XCTAssertGreaterThan(best.box.midY, 0.5, "Vision boxes have a bottom-left origin; the word is in the upper half")
        XCTAssertGreaterThan(best.box.midX, 0.2); XCTAssertLessThan(best.box.midX, 0.8)
    }
    func testFinderModesMapOntoLocalQueries() {
        XCTAssertEqual(ObjectDetector.query(for: .exit), .exitSign)
        XCTAssertEqual(ObjectDetector.query(for: .door), .doorCandidate)
        XCTAssertEqual(ObjectDetector.query(for: .person), .person)
        XCTAssertEqual(ObjectDetector.query(for: .chair), .object(labels: ["chair"], spoken: "chair"))
        XCTAssertNil(ObjectDetector.query(for: .none)); XCTAssertNil(ObjectDetector.query(for: .teammate))
    }
}
