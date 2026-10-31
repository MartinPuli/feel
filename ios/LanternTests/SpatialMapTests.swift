import XCTest
import FeelCore
@testable import Lantern

final class SpatialMapTests: XCTestCase {
    private func update(session: Int = 1, world: Int = 1, revision: Int = 1, time: Double = 10,
                        tracking: Bool = true, supported: Bool = true, pose: CameraPose? = .identity,
                        chunks: [SpatialMeshChunk] = SpatialMapModel.demoRoom) -> SpatialMapUpdate {
        SpatialMapUpdate(sessionEpoch: session, worldEpoch: world, chunks: chunks, geometryRevision: revision,
                         pose: pose, timestamp: time, tracking: tracking, supported: supported)
    }
    func testOldSessionAndStoppedCallbacksCannotReviveGeometry() {
        let model = SpatialMapModel()
        model.prepare(sessionEpoch: 2)
        model.apply(update(session: 1)); XCTAssertTrue(model.chunks.isEmpty)
        model.apply(update(session: 2)); XCTAssertEqual(model.triangleCount, 10)
        model.stop(); model.apply(update(session: 2, time: 11))
        XCTAssertEqual(model.mode, .stopped); XCTAssertTrue(model.chunks.isEmpty)
    }
    func testNewWorldReplacesRatherThanMergesOldRoom() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1)
        model.apply(update()); model.apply(update(world: 2, time: 11, chunks: []))
        XCTAssertTrue(model.chunks.isEmpty); XCTAssertEqual(model.mode, .waiting)
        model.apply(update(world: 1, time: 12)); XCTAssertTrue(model.chunks.isEmpty)
    }
    func testInterruptionRejectsAlreadyQueuedOldWorldObservation() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1); model.apply(update())
        model.invalidate(); model.invalidate(); model.apply(update(time: 11))
        XCTAssertEqual(model.mode, .trackingLost); XCTAssertTrue(model.chunks.isEmpty)
        model.apply(update(world: 2, revision: 2, time: 12))
        XCTAssertEqual(model.mode, .live); XCTAssertEqual(model.triangleCount, 10)
    }
    func testNoNewFramesExpiresStatusWithoutNewCallback() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1); model.apply(update())
        XCTAssertTrue(model.status(at: 10.5).contains("Live scan"))
        XCTAssertTrue(model.status(at: 10.751).contains("stale"))
        XCTAssertTrue(model.status(at: 9).contains("stale"))
        XCTAssertTrue(model.status(at: .nan).contains("stale"))
    }
    func testTrackingLossIsUnavailableAndNoHitNeverMeansClear() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1)
        model.apply(update(chunks: [])); XCTAssertEqual(model.status(at: 10), "Waiting for observed surfaces")
        model.apply(update(revision: 2, time: 11, tracking: false))
        XCTAssertEqual(model.mode, .trackingLost)
        XCTAssertTrue(model.status(at: 11).contains("not current"))
    }
    func testUnsupportedDeviceAndInvalidTimestampAreExplicit() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1)
        model.apply(update(time: .nan)); XCTAssertTrue(model.chunks.isEmpty)
        model.apply(update(supported: false, chunks: []))
        XCTAssertEqual(model.mode, .unsupported)
        XCTAssertTrue(model.status(at: 10).contains("unavailable"))
    }
    func testInvalidPoseTrackingLossImmediatelyClearsMarkerWithoutAcceptingGeometry() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1); model.apply(update())
        model.apply(update(revision: 2, time: 11, tracking: false,
                           pose: CameraPose(position: Vector3(.nan, 0, 0)), chunks: []))
        XCTAssertEqual(model.mode, .trackingLost); XCTAssertNil(model.pose)
        XCTAssertEqual(model.triangleCount, 10, "Only the previous geometry remains, explicitly marked not current")
        XCTAssertTrue(model.status(at: 11).contains("not current"))
    }
    func testMissingPoseCannotBecomeLiveAndNewWorldLossDropsOldRoom() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1); model.apply(update())
        model.apply(update(time: 11, pose: nil))
        XCTAssertEqual(model.mode, .trackingLost); XCTAssertNil(model.pose)
        model.apply(update(world: 2, time: 12, tracking: false))
        XCTAssertTrue(model.chunks.isEmpty)
        model.apply(update(world: 1, time: 13)); XCTAssertTrue(model.chunks.isEmpty)
        model.apply(update(world: 2, time: 14)); XCTAssertEqual(model.mode, .live)
    }
    func testOutOfOrderFramesAndGeometryRevisionsAreRejected() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1); model.apply(update(revision: 2))
        model.apply(update(revision: 3, time: 9, chunks: [])); XCTAssertEqual(model.triangleCount, 10)
        model.apply(update(revision: 1, time: 11, chunks: [])); XCTAssertEqual(model.triangleCount, 10)
    }
    func testSyntheticRoomCannotBeOverwrittenByLateLiveCallbacks() {
        let model = SpatialMapModel(); model.prepare(sessionEpoch: 1); model.showDemo()
        model.apply(update(chunks: [])); XCTAssertEqual(model.mode, .simulation)
        XCTAssertEqual(model.triangleCount, 10)
        model.toggleDemoTracking(); XCTAssertEqual(model.mode, .trackingLost)
        model.toggleDemoTracking(); XCTAssertEqual(model.mode, .simulation)
        model.stop(); XCTAssertEqual(model.mode, .stopped); XCTAssertEqual(model.triangleCount, 0)
    }
    func testMapSimulationLeavesCameraAndGuidanceStopped() {
        let model = LanternModel(); model.simulateSpatialMap()
        XCTAssertEqual(model.mode, .stopped)
        XCTAssertEqual(model.spatialMap.mode, .simulation)
        XCTAssertEqual(model.packet.bands, [UInt8](repeating: 0, count: 7))
        XCTAssertFalse(model.memorySimulation)
        model.stop(); XCTAssertEqual(model.spatialMap.mode, .stopped)
    }
}
