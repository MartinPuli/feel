import XCTest
import FeelCore
@testable import Lantern

final class SessionPlacesTests: XCTestCase {
    private var clock = 10.0
    private func pose(_ z: Double) -> CameraPose {
        CameraPose(position: Vector3(0, 1.2, z), right: Vector3(1, 0, 0), up: Vector3(0, 1, 0), back: Vector3(0, 0, 1))
    }
    func testRememberRecallKeepsNearObstacleAndNeutralizesOnTrackingLoss() throws {
        let places = SessionPlaces(now: { self.clock })
        places.observe(pose: pose(-2), worldEpoch: 1, timestamp: clock, tracking: true)
        XCTAssertNil(places.remember("Entrance")["error"])
        let id = try XCTUnwrap(places.memory.bookmarks.first?.id)
        places.observe(pose: pose(0), worldEpoch: 1, timestamp: clock, tracking: true)
        XCTAssertNil(places.recall(id)["error"])
        let output = try XCTUnwrap(places.encode(sequence: 7, distances: [nil,nil,nil,nil,0.5,nil,nil], calibrated: true, at: clock))
        XCTAssertEqual(output.packet.bands[0], 0)
        XCTAssertEqual(output.packet.bands[4], 1, "Remembered target must not replace a nearer obstacle")
        places.invalidate()
        XCTAssertEqual(places.encode(sequence: 8, distances: [Double?](repeating: nil, count: 7), calibrated: true, at: clock)?.packet, .neutral(sequence: 8))
    }
    func testNewWorldClearsOldBookmarksAndReturnPoint() {
        let places = SessionPlaces(now: { self.clock })
        places.observe(pose: pose(0), worldEpoch: 1, timestamp: clock, tracking: true)
        _ = places.remember("Entrance"); _ = places.setReturnPoint()
        places.observe(pose: pose(0), worldEpoch: 2, timestamp: clock, tracking: true)
        XCTAssertTrue(places.memory.bookmarks.isEmpty)
        XCTAssertNil(places.memory.returnPoint)
        XCTAssertNotNil(places.returnToPoint()["error"])
    }
    func testStalePoseCannotSaveOrGuide() throws {
        let places = SessionPlaces(now: { self.clock })
        places.observe(pose: pose(-2), worldEpoch: 1, timestamp: clock, tracking: true)
        _ = places.remember("Desk")
        _ = places.recall(try XCTUnwrap(places.memory.bookmarks.first?.id))
        clock += 1
        XCTAssertNotNil(places.remember("Stale")["error"])
        XCTAssertEqual(places.encode(sequence: 1, distances: [Double?](repeating: 2, count: 7), calibrated: true, at: clock)?.packet, .neutral(sequence: 1))
    }
    func testRenameDeleteAndStoppedSessionDoNotLeaveAnActiveTarget() throws {
        let places = SessionPlaces(now: { self.clock })
        places.observe(pose: pose(0), worldEpoch: 1, timestamp: clock, tracking: true)
        _ = places.remember("Desk")
        let id = try XCTUnwrap(places.memory.bookmarks.first?.id)
        _ = places.rename(id, to: "Work desk"); _ = places.recall(id)
        XCTAssertEqual(places.memory.bookmarks.first?.name, "Work desk")
        _ = places.delete(id)
        XCTAssertFalse(places.active)
        places.end()
        XCTAssertNotNil(places.remember("After stop")["error"])
    }
    func testCloudToolDecoderRejectsExtraOrMissingBookmarkFields() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "remember_place", arguments: #"{"name":"Desk"}"#), .rememberPlace("Desk"))
        XCTAssertEqual(try VoiceCommand.decode(name: "rename_place", arguments: #"{"id":"a","name":"Desk"}"#), .renamePlace("a", "Desk"))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "rename_place", arguments: #"{"id":"a"}"#))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "return_to_point", arguments: #"{"confirmed":true}"#))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "remember_place", arguments: #"{"name":"Desk","execute":true}"#))
    }
    func testBarcodePayloadIsOnlyASanitizedBoundedLabel() {
        XCTAssertEqual(ObjectDetector.barcodeLabel(nil), "Barcode")
        XCTAssertFalse(ObjectDetector.barcodeLabel("a\n\u{202e}b").contains("\n"))
        XCTAssertEqual(ObjectDetector.barcodeLabel(String(repeating: "x", count: 100)).count, 69)
    }
}
