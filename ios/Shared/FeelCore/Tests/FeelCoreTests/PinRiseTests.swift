import XCTest
@testable import FeelCore

/// Every physical pin, every band: an obstacle in one sector raises that pin alone, to the right
/// height, all the way from depth samples to the bytes on the wire. Six pins in wire slots 1...6;
/// slot 0 has no servo and must stay down.
final class PinRiseTests: XCTestCase {
    let pose = CameraPose(position: Vector3(0, 1, 0))
    /// Distance representative of each band, then the metre just inside each band's far edge.
    let bandDistances: [(band: UInt8, distance: Double)] = [(1, 0.5), (2, 1.2), (3, 2.0), (4, 3.0)]
    let bandEdges: [(band: UInt8, distance: Double)] = [(1, 0.89), (2, 0.9), (2, 1.59), (3, 1.6), (3, 2.49), (4, 2.5), (4, 4.0)]

    /// A real surface at `distance` metres along the bearing of wire slot `slot`, at chest height.
    func surface(slot: Int, distance: Double) -> [DepthSample] {
        let bearing = PuckLayout.bearing(ofColumn: slot) * .pi / 180
        let point = Vector3(sin(bearing) * distance, 0, -cos(bearing) * distance)
        return Array(repeating: DepthSample(cameraPoint: point, confidence: 2), count: DepthProjector.support)
    }
    func encode(_ distances: [Double?], sequence: UInt8 = 7) -> FeelPacket {
        TactileEncoder.encode(sequence: sequence, now: 10, frameTimestamp: 10, tracking: true,
                              distances: distances, target: nil, floorCalibrated: true).packet
    }

    func testEachPinRisesAloneFromDepthSamples() {
        for slot in PuckLayout.activeColumns {
            for (band, distance) in bandDistances {
                let ranges = DepthProjector.sectors(samples: surface(slot: slot, distance: distance), pose: pose, floorY: 0)
                for column in 0..<7 {
                    if column == slot {
                        XCTAssertEqual(try XCTUnwrap(ranges[column]), distance, accuracy: 1e-9, "slot \(slot) band \(band)")
                    } else {
                        XCTAssertNil(ranges[column], "slot \(slot) band \(band): column \(column) must stay unknown")
                    }
                }
                let packet = encode(ranges)
                var expected = [UInt8](repeating: 0, count: 7); expected[slot] = band
                XCTAssertEqual(packet.bands, expected, "slot \(slot) at \(distance) m must raise only itself to band \(band)")
                XCTAssertEqual(packet.highlight, 255)
                XCTAssertEqual(packet.forActiveLayout.bytes, [7] + expected + [255])
            }
        }
    }

    func testEachPinStepsThroughAllFourBandsAtTheBandEdges() {
        for slot in PuckLayout.activeColumns {
            for (band, distance) in bandEdges {
                var distances = [Double?](repeating: nil, count: 7); distances[slot] = distance
                let packet = encode(distances)
                XCTAssertEqual(packet.bands[slot], band, "slot \(slot) at \(distance) m")
                XCTAssertEqual(packet.bands.enumerated().filter { $0.offset != slot }.map(\.element), [UInt8](repeating: 0, count: 6))
            }
            // Beyond four metres, or unknown, the pin stays down.
            var far = [Double?](repeating: nil, count: 7); far[slot] = 4.01
            XCTAssertEqual(encode(far).bands[slot], 0, "slot \(slot) beyond 4 m")
            XCTAssertEqual(encode([Double?](repeating: nil, count: 7)).bands[slot], 0, "slot \(slot) unknown")
        }
    }

    func testReservedSlotNeverRisesEvenWhenAsked() {
        var distances = [Double?](repeating: 0.5, count: 7)
        XCTAssertEqual(encode(distances).bands[0], 0, "slot 0 has no servo")
        distances = [Double?](repeating: nil, count: 7); distances[0] = 0.5
        XCTAssertEqual(encode(distances).bands, [UInt8](repeating: 0, count: 7))
        // A point exactly on the camera axis belongs to slot 4, never slot 0.
        let ranges = DepthProjector.sectors(samples: surface(slot: 4, distance: 1), pose: pose, floorY: 0)
        XCTAssertNil(ranges[0]); XCTAssertNotNil(ranges[4])
    }

    func testEachPinRisesThroughTheSteadyingFilterWithinTwoFrames() {
        for slot in PuckLayout.activeColumns {
            for (band, distance) in bandDistances {
                var filter = SectorFilter()
                var distances = [Double?](repeating: nil, count: 7); distances[slot] = distance
                var shown: [Double?] = []
                var frames = 0
                for frame in 0..<filter.nearFrames {
                    shown = filter.update(distances, frameTimestamp: 10 + Double(frame) * 0.05)
                    frames = frame + 1
                    if shown[slot] != nil { break }
                }
                XCTAssertEqual(encode(shown).bands[slot], band, "slot \(slot) band \(band) must show after \(frames) frame(s)")
                XCTAssertLessThanOrEqual(frames, band == 1 ? 1 : filter.nearFrames, "band 1 is immediate; other bands within nearFrames")
                for column in 0..<7 where column != slot { XCTAssertNil(shown[column]) }
            }
        }
    }

    func testTwoPinsRiseTogetherWithoutLeaking() {
        for left in PuckLayout.activeColumns {
            for right in PuckLayout.activeColumns where right > left {
                let samples = surface(slot: left, distance: 0.5) + surface(slot: right, distance: 3.0)
                let packet = encode(DepthProjector.sectors(samples: samples, pose: pose, floorY: 0))
                var expected = [UInt8](repeating: 0, count: 7); expected[left] = 1; expected[right] = 4
                XCTAssertEqual(packet.bands, expected, "slots \(left) and \(right)")
            }
        }
    }
}
