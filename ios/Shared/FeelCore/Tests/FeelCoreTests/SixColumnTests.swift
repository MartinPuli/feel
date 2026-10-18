import XCTest
@testable import FeelCore

final class SixColumnTests: XCTestCase {
    func testFullFieldMapsToSixActiveSlots() {
        let centers = [-37.5, -22.5, -7.5, 7.5, 22.5, 37.5]
        for (index, angle) in centers.enumerated() {
            XCTAssertEqual(TactileGeometry.column(bearingDegrees: angle), index + 1)
            XCTAssertEqual(PuckLayout.bearing(ofColumn: index + 1), angle)
        }
        XCTAssertEqual(TactileGeometry.column(bearingDegrees: -45), 1)
        XCTAssertEqual(TactileGeometry.column(bearingDegrees: 45), 6)
    }

    func testEveryTargetKeepsUnusedSlotNeutral() {
        for angle in stride(from: -45.0, through: 45.0, by: 0.5) {
            let output = TactileEncoder.encode(sequence: 1, now: 1, frameTimestamp: 1,
                tracking: true, distances: Array(repeating: 1, count: 7),
                target: TargetObservation(bearingDegrees: angle, distance: 2, timestamp: 1))
            XCTAssertEqual(output.packet.bands[0], 0)
            XCTAssertTrue((1...6).contains(Int(output.packet.highlight)))
            XCTAssertEqual(output.packet.bytes.count, 9)
        }
    }

    func testFinalAdapterSuppressesLegacySlotWithoutMovingOtherColumns() throws {
        let legacy = try FeelPacket(sequence: 42, bands: [4,1,2,3,4,1,2], highlight: 0)
        XCTAssertEqual(legacy.forActiveLayout.bytes, [42,0,1,2,3,4,1,2,255])
        XCTAssertEqual(legacy.bands[0], 4, "Raw decoder retains legacy compatibility")
        let right = try FeelPacket(sequence: 2, bands: [4,1,2,3,4,1,2], highlight: 6)
        XCTAssertEqual(right.forActiveLayout.highlight, 6)
    }

    func testAllCuesLeaveMissingColumnOffAndStraightIsSymmetric() {
        let cues: [DirectionCue] = [.straight, .turnLeft, .turnRight, .turnAround, .arrived]
            + (1...6).map { .bear(column: $0) }
        for cue in cues { for frame in cue.frames { XCTAssertEqual(frame[0], 0) } }
        for frame in DirectionCue.straight.frames {
            XCTAssertEqual(Array(frame[1...6]), Array(frame[1...6].reversed()))
        }
    }

    func testPointingRejectsRemovedPhysicalPosition() {
        XCTAssertNil(PuckBackLayout.column(atU: 36))
        XCTAssertNil(PuckBackLayout.cell(at: .init(36, 14.5)))
    }
}
