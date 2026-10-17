import XCTest
@testable import FeelCore

final class HeldTargetTests: XCTestCase {
    private let pose = CameraPose.identity   // at the origin, facing -z, x to the right
    private func held(_ x: Double, _ z: Double) -> HeldTarget {
        HeldTarget(position: Vector3(x, 0, z), label: "desk", worldEpoch: 1, setAt: 0)
    }

    func testObservationIsStampedNow() throws {
        let observation = try XCTUnwrap(held(0, -2).observation(pose: pose, now: 7, worldEpoch: 1))
        XCTAssertEqual(observation.timestamp, 7)
        XCTAssertEqual(observation.bearingDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(observation.distance, 2, accuracy: 1e-9)
        XCTAssertEqual(observation.label, "desk")
        XCTAssertEqual(observation.confidence, 1)
    }
    func testEpochChangeInvalidates() {
        XCTAssertNil(held(0, -2).observation(pose: pose, now: 7, worldEpoch: 2))
    }
    func testOutsideFieldHasNoObservationButSpeaks() {
        let target = held(-2, 0)
        XCTAssertNil(target.observation(pose: pose, now: 1, worldEpoch: 1))
        XCTAssertEqual(target.spokenDirection(pose: pose), "desk is to your left.")
    }
    func testBehindSpeaksBehind() {
        XCTAssertEqual(held(0, 2).spokenDirection(pose: pose), "desk is behind you.")
    }
    func testRightSpeaksRight() {
        XCTAssertEqual(held(2, 0).spokenDirection(pose: pose), "desk is to your right.")
    }
    func testBeyondRangeSpeaksDistance() {
        let target = held(0, -6.4)
        XCTAssertNil(target.observation(pose: pose, now: 1, worldEpoch: 1))
        XCTAssertEqual(target.spokenDirection(pose: pose), "desk ahead, about 6 meters.")
    }
    func testInsideFieldSaysNothing() {
        XCTAssertNil(held(0, -2).spokenDirection(pose: pose))
    }
    func testReached() {
        XCTAssertTrue(held(0, -0.3).reached(pose: pose))
        XCTAssertFalse(held(0, -0.6).reached(pose: pose))
    }
    func testRelativeBearingIsFullCircle() throws {
        let relative = try XCTUnwrap(held(0, 2).relative(pose: pose))
        XCTAssertEqual(abs(relative.bearingDegrees), 180, accuracy: 1e-9)
        XCTAssertEqual(relative.horizontalDistance, 2, accuracy: 1e-9)
    }

    private func snapshot(confidence: UInt8) -> FrameSnapshot {
        let width = 20, height = 10
        return FrameSnapshot(timestamp: 3, worldEpoch: 1, pose: pose,
                             intrinsics: CameraIntrinsics(fx: 10, fy: 10, cx: 10, cy: 5),
                             depth: DepthGrid(width: width, height: height,
                                              depths: Array(repeating: 2.0, count: width * height),
                                              confidence: Array(repeating: confidence, count: width * height)),
                             jpegBase64: "")
    }
    func testPlacementUsesMedianDepthAtBoxCentre() throws {
        let answer = WhereIsAnswer(found: true, label: "desk", box: NormalizedBox(xMin: 0.4, yMin: 0.4, xMax: 0.6, yMax: 0.6), confidence: 0.9)
        let target = try XCTUnwrap(WhereIsPlacement.place(answer: answer, snapshot: snapshot(confidence: 2)))
        XCTAssertEqual(target.position.x, 0, accuracy: 1e-6)
        XCTAssertEqual(target.position.y, 0, accuracy: 1e-6)
        XCTAssertEqual(target.position.z, -2, accuracy: 1e-6)
        XCTAssertEqual(target.label, "desk")
        XCTAssertEqual(target.worldEpoch, 1)
        XCTAssertEqual(target.setAt, 3)
    }
    func testNoDepthGivesNoTarget() {
        let answer = WhereIsAnswer(found: true, label: "desk", box: NormalizedBox(xMin: 0.4, yMin: 0.4, xMax: 0.6, yMax: 0.6), confidence: 0.9)
        XCTAssertNil(WhereIsPlacement.place(answer: answer, snapshot: snapshot(confidence: 0)))
    }
    func testNotFoundGivesNoTarget() {
        let answer = WhereIsAnswer(found: false, label: "", box: nil, confidence: 0)
        XCTAssertNil(WhereIsPlacement.place(answer: answer, snapshot: snapshot(confidence: 2)))
    }
    func testDepthGridMedianIgnoresLowConfidenceAndOutOfRange() {
        var depths = Array(repeating: 2.0, count: 25), confidence = Array(repeating: UInt8(2), count: 25)
        depths[12] = 9; confidence[0] = 0
        let grid = DepthGrid(width: 5, height: 5, depths: depths, confidence: confidence)
        XCTAssertEqual(grid.medianDepth(x: 2, y: 2), 2)
        XCTAssertNil(DepthGrid(width: 5, height: 5, depths: depths, confidence: Array(repeating: 0, count: 25)).medianDepth(x: 2, y: 2))
        XCTAssertNil(grid.medianDepth(x: -1, y: 2))
    }
}
