import XCTest
@testable import FeelCore

final class DepthInputComponentTests: XCTestCase {
    private let intrinsics = CameraIntrinsics(fx: 100, fy: 100, cx: 0, cy: 0)

    private func frame(_ depths: [Float], _ confidence: [UInt8]) throws -> DepthFrame {
        try XCTUnwrap(DepthFrame(width: depths.count, height: 1, depths: depths,
                                confidence: confidence, intrinsics: intrinsics))
    }

    func testMismatchedDepthAndConfidenceBuffersAreRejected() {
        XCTAssertNil(DepthFrame(width: 2, height: 2, depths: [1, 2, 3],
                               confidence: [2, 2, 2, 2], intrinsics: intrinsics))
        XCTAssertNil(DepthFrame(width: 2, height: 2, depths: [1, 2, 3, 4],
                               confidence: [2, 2, 2], intrinsics: intrinsics))
    }

    func testMedianIgnoresInvalidAndLowConfidenceSamples() throws {
        let map = try frame([.nan, 1, 2, 3, 0.1], [2, 1, 2, 2, 0])
        XCTAssertEqual(map.medianDepth(x: 2, y: 0), 2)
    }

    func testMedianRequiresThreeUsableSamples() throws {
        let map = try frame([1, 2, 3, 4, 5], [2, 2, 0, 3, 2])
        XCTAssertNil(map.medianDepth(x: 2, y: 0))
    }

    func testMedianAtImageEdgeDoesNotWrapIntoOtherPixels() throws {
        let map = try frame([1, 2, 3, 0.1, 0.1], [2, 2, 2, 2, 2])
        XCTAssertEqual(map.medianDepth(x: 0, y: 0), 2)
        for x in [-1.0, 5, Double.nan, .infinity] {
            XCTAssertNil(map.medianDepth(x: x, y: 0))
        }
    }
}

final class ObstacleProjectionComponentTests: XCTestCase {
    private let pose = CameraPose(position: Vector3(0, 1, 0))
    // Main uses six sectors in wire slots 1...6; zero degrees selects slot 4.
    // These cases use single samples, so they ask for support 1; the support rule has its own tests.
    private func sample(_ bearing: Double, _ distance: Double, confidence: UInt8 = 2) -> DepthSample {
        let radians = bearing * .pi / 180
        return DepthSample(cameraPoint: Vector3(sin(radians) * distance, 0,
                                                -cos(radians) * distance), confidence: confidence)
    }

    func testNearestObstacleWinsRegardlessOfSampleOrder() throws {
        let inputs = [sample(0, 3), sample(0, 0.75), sample(0, 2)]
        for samples in [inputs, Array(inputs.reversed())] {
            let ranges = DepthProjector.sectors(samples: samples, pose: pose, floorY: 0, support: 1)
            XCTAssertEqual(try XCTUnwrap(ranges[4]), 0.75, accuracy: 1e-10)
            XCTAssertEqual(ranges.compactMap { $0 }.count, 1)
        }
    }

    func testSeparatedObstaclesLeaveCentralSectorUnknown() throws {
        let ranges = DepthProjector.sectors(samples: [sample(-25, 1), sample(25, 3)],
                                           pose: pose, floorY: 0, support: 1)
        XCTAssertEqual(try XCTUnwrap(ranges[2]), 1, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(ranges[5]), 3, accuracy: 1e-10)
        for column in [0, 1, 3, 4, 6] { XCTAssertNil(ranges[column]) }
    }

    func testLowConfidenceNearSampleCannotHideValidFarObstacle() throws {
        let ranges = DepthProjector.sectors(samples: [sample(0, 0.5, confidence: 0), sample(0, 3)],
                                           pose: pose, floorY: 0, support: 1)
        XCTAssertEqual(try XCTUnwrap(ranges[4]), 3, accuracy: 1e-10)
    }

    func testHeightUsesFloorRelativeWorldCoordinates() {
        let samples = [DepthSample(cameraPoint: Vector3(0, -0.41, -1), confidence: 2),
                       DepthSample(cameraPoint: Vector3(0, 1.11, -1), confidence: 2)]
        for shift in [0.0, 10.0, -10.0] {
            let ranges = DepthProjector.sectors(samples: samples,
                pose: CameraPose(position: Vector3(0, 1 + shift, 0)), floorY: shift, support: 1)
            XCTAssertTrue(ranges.allSatisfy { $0 == nil })
            let accepted = DepthProjector.sectors(samples: [sample(0, 1)],
                pose: CameraPose(position: Vector3(0, 1 + shift, 0)), floorY: shift, support: 1)
            XCTAssertEqual(accepted[4], 1)
        }
    }
}

final class EncoderComponentRegressionTests: XCTestCase {
    private func encode(_ distances: [Double?], now: Double = 10,
                        tracking: Bool = true, calibrated: Bool = true) -> EncoderOutput {
        TactileEncoder.encode(sequence: 17, now: now, frameTimestamp: 10,
            tracking: tracking, distances: distances,
            target: TargetObservation(bearingDegrees: 25, distance: 1, timestamp: 10),
            floorCalibrated: calibrated)
    }

    func testEverySafetyGateSuppressesBothObstacleAndTarget() {
        let occupied: [Double?] = Array(repeating: 0.5, count: 7)
        let cases: [(EncoderOutput, GuidanceState)] = [
            (encode(occupied, tracking: false), .trackingLost),
            (encode(occupied, calibrated: false), .uncalibrated),
            (encode(occupied, now: 10.3), .staleDepth),
            (encode(occupied, now: 9), .invalidFrame),
            (encode(Array(occupied.dropLast())), .invalidFrame)
        ]
        for (output, state) in cases {
            XCTAssertEqual(output.state, state)
            XCTAssertEqual(output.packet, FeelPacket.neutral(sequence: 17))
            XCTAssertNil(output.targetColumns)
        }
    }

    func testLiveOutputActivatesOnlyObstacleAndTargetColumns() {
        let output = encode([nil, nil, nil, 2, nil, nil, nil])
        XCTAssertEqual(output.state, .live)
        XCTAssertEqual(output.packet.bands, [0, 0, 0, 3, 0, 2, 0])
        XCTAssertEqual(output.packet.highlight, 5)
    }

    func testNarrowObstacleAndFullWidthObstacleHaveDifferentOccupancy() {
        func bands(_ ranges: [Double?]) -> [UInt8] {
            TactileEncoder.encode(sequence: 1, now: 10, frameTimestamp: 10,
                                  tracking: true, distances: ranges).packet.bands
        }
        // Tests occupancy only: these ranges do not classify objects as chairs or walls.
        XCTAssertEqual(bands([nil, nil, 1.2, 1.2, 1.2, nil, nil]), [0, 0, 2, 2, 2, 0, 0])
        // The absent GPIO32 actuator reserves slot zero even for a full-width obstacle.
        XCTAssertEqual(bands(Array(repeating: 1.2, count: 7)), [0, 2, 2, 2, 2, 2, 2])
    }
}

final class PacketIsolationComponentTests: XCTestCase {
    func testEachColumnRetainsItsWirePosition() throws {
        for column in 0..<7 {
            for band: UInt8 in 1...4 {
                var bands = [UInt8](repeating: 0, count: 7)
                bands[column] = band
                let packet = try FeelPacket(sequence: 42, bands: bands, highlight: UInt8(column))
                var expected = [UInt8](repeating: 0, count: 9)
                expected[0] = 42
                expected[column + 1] = band
                expected[8] = UInt8(column)
                XCTAssertEqual(packet.bytes, expected)
                XCTAssertEqual(try FeelPacket(bytes: expected).bands, bands)
            }
        }
    }
}
