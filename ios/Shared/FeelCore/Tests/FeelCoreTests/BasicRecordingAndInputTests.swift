import XCTest
@testable import FeelCore

final class BasicRecordingComponentTests: XCTestCase {
    private let info = RecordingInfo(source: "iphone", createdAt: "2026-10-17T19:31:43Z",
                                     cameraHeight: 1.2, note: "unit test")

    func testRecordingWithNoFramesPreservesMetadata() throws {
        let decoded = try SessionRecording.decode(SessionRecording.start(info))
        XCTAssertEqual(decoded.info, info)
        XCTAssertTrue(decoded.frames.isEmpty)
    }

    func testMultipleFramesPreserveTimePoseAndOrder() throws {
        let pose = CameraPose(position: Vector3(2, 1, -3),
                              right: Vector3(0, 0, -1), up: Vector3(0, 1, 0), back: Vector3(1, 0, 0))
        let frames = [
            RecordedFrame(timestamp: 100.125, trackingNormal: true, pose: pose, floorY: 0, depth: nil),
            RecordedFrame(timestamp: 100.225, trackingNormal: false, pose: .identity, floorY: nil, depth: nil)
        ]
        var data = try SessionRecording.start(info)
        for frame in frames { data.append(try SessionRecording.encode(frame)) }
        XCTAssertEqual(try SessionRecording.decode(data).frames, frames)
    }

    func testEveryPartialFrameIsRejectedInsteadOfSilentlyDropped() throws {
        let header = try SessionRecording.start(info)
        let depth = try XCTUnwrap(DepthFrame(width: 1, height: 1, depths: [1.25], confidence: [2],
            intrinsics: CameraIntrinsics(fx: 1, fy: 1, cx: 0, cy: 0)))
        let frame = try SessionRecording.encode(RecordedFrame(timestamp: 1, trackingNormal: true,
            pose: .identity, floorY: 0, depth: depth))
        for length in 1..<frame.count {
            var truncated = header
            truncated.append(frame.prefix(length))
            XCTAssertThrowsError(try SessionRecording.decode(truncated), "prefix length \(length)")
        }
        var complete = header
        complete.append(frame)
        XCTAssertEqual(try SessionRecording.decode(complete).frames.count, 1)
    }

    func testInvalidFrameJSONIsReportedAsBadHeader() throws {
        var data = try SessionRecording.start(info)
        // One-byte JSON header containing an invalid JSON token, then an empty payload.
        data.append(contentsOf: [1, 0, 0, 0, 0x21, 0, 0, 0, 0])
        XCTAssertThrowsError(try SessionRecording.decode(data)) { error in
            guard case SessionRecording.Failure.badHeader = error else {
                return XCTFail("Expected badHeader, received \(error)")
            }
        }
    }
}

final class BasicMountComponentTests: XCTestCase {
    func testUprightMountIsAcceptedAtAnyHorizontalHeading() {
        for degrees in [0.0, 90, 180, 270] {
            let a = degrees * .pi / 180
            let pose = CameraPose(right: Vector3(cos(a), 0, -sin(a)),
                                  up: Vector3(0, 1, 0), back: Vector3(sin(a), 0, cos(a)))
            XCTAssertTrue(DepthFrameProcessor.mountValid(pose), "heading \(degrees)")
        }
    }

    func testSidewaysUpsideDownAndFlatMountsAreRejected() {
        let poses = [
            CameraPose(right: Vector3(0, 1, 0), up: Vector3(-1, 0, 0)),
            CameraPose(right: Vector3(-1, 0, 0), up: Vector3(0, -1, 0)),
            CameraPose(up: Vector3(0, 0, 1), back: Vector3(0, -1, 0))
        ]
        for pose in poses {
            XCTAssertTrue(pose.isValid, "Fixture must be a valid rotation")
            XCTAssertFalse(DepthFrameProcessor.mountValid(pose))
        }
    }

    func testInvalidPoseCannotPassMountCheck() {
        XCTAssertFalse(DepthFrameProcessor.mountValid(CameraPose(position: Vector3(.nan, 0, 0))))
        XCTAssertFalse(DepthFrameProcessor.mountValid(CameraPose(right: Vector3(2, 0, 0))))
    }
}

final class BasicTargetSelectionComponentTests: XCTestCase {
    func testNoValidTargetsReturnsNil() {
        XCTAssertNil(TargetSelector.best([], at: 10))
        let invalid = [
            TargetObservation(bearingDegrees: 0, distance: 1, timestamp: 9),
            TargetObservation(bearingDegrees: 0, distance: 1, timestamp: 11),
            TargetObservation(bearingDegrees: 0, distance: 1, timestamp: 10, confidence: 0.1)
        ]
        XCTAssertNil(TargetSelector.best(invalid, at: 10))
    }

    func testConfidenceThenDistanceThenBearingDetermineSelection() {
        let strong = TargetObservation(bearingDegrees: 25, distance: 3, timestamp: 10, confidence: 0.9)
        let weakNear = TargetObservation(bearingDegrees: 0, distance: 0.5, timestamp: 10, confidence: 0.6)
        let near = TargetObservation(bearingDegrees: 10, distance: 1, timestamp: 10, confidence: 0.9)
        let tiedLeft = TargetObservation(bearingDegrees: -10, distance: 1, timestamp: 10, confidence: 0.9)
        for pair in [[strong, weakNear], [weakNear, strong]] {
            XCTAssertEqual(TargetSelector.best(pair, at: 10), strong)
        }
        for pair in [[strong, near], [near, strong]] {
            XCTAssertEqual(TargetSelector.best(pair, at: 10), near)
        }
        for pair in [[near, tiedLeft], [tiedLeft, near]] {
            XCTAssertEqual(TargetSelector.best(pair, at: 10), tiedLeft)
        }
    }
}
