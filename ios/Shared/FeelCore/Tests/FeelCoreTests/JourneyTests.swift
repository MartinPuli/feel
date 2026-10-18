import XCTest
@testable import FeelCore

/// protocol/journey-v1.json: the journeys, the planned path and its progress points shared with Chalk.
func journeyVector() throws -> [String: Any] {
    var url=URL(fileURLWithPath:#filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return try XCTUnwrap(JSONSerialization.jsonObject(with:try Data(contentsOf:url.appendingPathComponent("protocol/journey-v1.json"))) as? [String:Any])
}
private func floorPoints(_ value: Any?) throws -> [FloorPoint] {
    try XCTUnwrap(value as? [[Double]]).map { FloorPoint($0[0],$0[1]) }
}
private func journeys(in vector: [String: Any]) throws -> [Journey] {
    try XCTUnwrap(vector["journeys"] as? [[String:Any]]).map { try Journey.decoder.decode(Journey.self,from:JSONSerialization.data(withJSONObject:$0)) }
}

/// The tag upright on the wall 3 m ahead of the identity camera: x right along it, y out of it (world +z), down is −y.
private let tagFrame=RoomFrame(origin:Vector3(0,0,-3),xAxis:Vector3(1,0,0),yAxis:Vector3(0,0,1),zAxis:Vector3(0,-1,0))
private let startedAt=ISO8601DateFormatter().date(from:"2026-10-15T18:00:00Z")!
/// The exit of the shared vector, (−4, 5.1) on the tag floor, in the world.
private let exit=Vector3(-4,0,2.1)
/// A camera at tag-floor point (x, y), 1.2 m up, facing along the tag's +y (heading 0), +x (90) or −x (270).
private func cameraAt(_ x: Double,_ y: Double,heading: Double=0) -> CameraPose {
    let position=Vector3(x,1.2,-3+y)
    switch heading {
    case 90: return CameraPose(position:position,right:Vector3(0,0,1),up:Vector3(0,1,0),back:Vector3(-1,0,0))
    case 270: return CameraPose(position:position,right:Vector3(0,0,-1),up:Vector3(0,1,0),back:Vector3(1,0,0))
    default: return CameraPose(position:position,right:Vector3(-1,0,0),up:Vector3(0,1,0),back:Vector3(0,0,-1))
    }
}
private func makeRecorder(target: Vector3=exit) -> JourneyRecorder {
    JourneyRecorder(venueId:"harvard-yard",tagId:"feel-tag-01",userId:"00000000-0000-0000-0000-000000000001",sessionId:"seed-session-01",
                    startedAt:startedAt,startUptime:100,targetLabel:"exit",target:target,frame:tagFrame)!
}

final class JourneyVectorTests: XCTestCase {
    func testTheRecorderReproducesTheFirstSharedJourney() throws {
        let expected=try XCTUnwrap(journeys(in:try journeyVector()).first)
        var recorder=makeRecorder()
        // Up 4 m from (−1, 1.1), a turn, then 3 m to the left: a step every metre and two seconds.
        for k in 0...4 { recorder.record(pose:cameraAt(-1,1.1+Double(k),heading:k == 4 ? 270 : 0),now:100+Double(2*k)) }
        for k in 1...3 { recorder.record(pose:cameraAt(-1-Double(k),5.1,heading:270),now:108+Double(2*k)) }
        for (changed,shown) in [(100.0,100.12),(102.0,102.095),(104.0,104.14),(106.0,106.11),(108.0,108.4)] { recorder.targetChanged(now:changed); recorder.cueShown(now:shown) }
        recorder.noteBlocked(worldCentres:[Vector3(-2.05,0,1.05),Vector3(-2.05,0,1.05)],cellSize:0.1)
        recorder.end(pose:cameraAt(-4,5.1,heading:270),now:114,arrivedAt:startedAt.addingTimeInterval(14))
        let journey=recorder.journey
        XCTAssertEqual(journey.venueId,expected.venueId); XCTAssertEqual(journey.tagId,expected.tagId); XCTAssertEqual(journey.userId,expected.userId)
        XCTAssertEqual(journey.sessionId,expected.sessionId); XCTAssertEqual(journey.startedAt,expected.startedAt); XCTAssertEqual(journey.targetLabel,"exit")
        XCTAssertEqual(journey.steps.count,expected.steps.count,"the end pose was the last step already")
        for (step,want) in zip(journey.steps,expected.steps) {
            XCTAssertEqual(step.t,want.t,accuracy:1e-9); XCTAssertEqual(step.x,want.x,accuracy:1e-9); XCTAssertEqual(step.y,want.y,accuracy:1e-9)
            XCTAssertEqual(step.headingDeg,want.headingDeg,accuracy:1e-9)
        }
        XCTAssertEqual(journey.obstacles.count,expected.obstacles.count)
        for (cell,want) in zip(journey.obstacles,expected.obstacles) { XCTAssertEqual(cell.x,want.x,accuracy:1e-9); XCTAssertEqual(cell.y,want.y,accuracy:1e-9) }
        XCTAssertEqual(journey.cueLatencyMs.count,expected.cueLatencyMs.count)
        for (ms,want) in zip(journey.cueLatencyMs,expected.cueLatencyMs) { XCTAssertEqual(ms,want,accuracy:1e-6) }
        XCTAssertEqual(journey.arrivedAt,expected.arrivedAt)
        XCTAssertEqual(try XCTUnwrap(journey.arrivalDistanceM),try XCTUnwrap(expected.arrivalDistanceM),accuracy:1e-9)
    }
    func testAWalkThatStopsShortKeepsItsDistanceToTheTarget() throws {
        let expected=try XCTUnwrap(journeys(in:try journeyVector()).last)
        var recorder=makeRecorder()
        for k in 0...1 { recorder.record(pose:cameraAt(-1,1.1+Double(k)),now:100+Double(2*k)) }
        recorder.end(pose:cameraAt(-1,3.1),now:104,arrivedAt:nil)
        XCTAssertFalse(recorder.journey.arrived)
        XCTAssertEqual(recorder.journey.steps.count,3,"the end pose is a step whatever the step rule says")
        XCTAssertEqual(try XCTUnwrap(recorder.journey.arrivalDistanceM),try XCTUnwrap(expected.arrivalDistanceM),accuracy:1e-3,"3.606 m short of the exit")
    }
    func testTheSharedJourneysEncodeWithEveryKeyAndSurviveARoundTrip() throws {
        let vector=try journeyVector()
        let objects=try XCTUnwrap(vector["journeys"] as? [[String:Any]])
        for object in objects {
            let journey=try Journey.decoder.decode(Journey.self,from:JSONSerialization.data(withJSONObject:object))
            let data=try Journey.encoder.encode(journey)
            let encoded=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
            XCTAssertEqual(Set(encoded.keys),Set(object.keys).subtracting(["about","scores"]),"the contract's keys; the vector's notes and scores are Chalk's")
            XCTAssertEqual(encoded["started_at"] as? String,object["started_at"] as? String)
            XCTAssertEqual((encoded["steps"] as? [[String:Any]])?.first?.keys.sorted(),["heading_deg","t","x","y"])
            XCTAssertEqual(try Journey.decoder.decode(Journey.self,from:data),journey)
            if journey.arrived { XCTAssertEqual(encoded["arrived_at"] as? String,object["arrived_at"] as? String) }
            else { XCTAssertTrue(encoded["arrived_at"] is NSNull,"null, not absent") }
        }
        var anonymous=try XCTUnwrap(journeys(in:vector).first); anonymous.userId=nil; anonymous.arrivalDistanceM=nil
        let open=try XCTUnwrap(JSONSerialization.jsonObject(with:try Journey.encoder.encode(anonymous)) as? [String:Any])
        XCTAssertTrue(open["user_id"] is NSNull); XCTAssertTrue(open["arrival_distance_m"] is NSNull)
    }
    func testTheSharedPathSplitsIntoTheSharedProgressPoints() throws {
        let path=try XCTUnwrap(try journeyVector()["path"] as? [String:Any])
        let polyline=try floorPoints(path["polyline"]), progress=try floorPoints(path["progress_points"])
        let spacing=try XCTUnwrap(path["progress_spacing_m"] as? Double)
        XCTAssertEqual(spacing,ProgressPoints.spacing)
        let split=ProgressPoints.split(polyline:polyline,spacing:spacing)
        XCTAssertEqual(split.count,progress.count)
        for (point,want) in zip(split,progress) { XCTAssertEqual(point.x,want.x,accuracy:1e-3); XCTAssertEqual(point.y,want.y,accuracy:1e-3) }
        XCTAssertEqual(split.last,try floorPoints([path["target"]]).first,"the target is always last")
        let length=zip(polyline,polyline.dropFirst()).reduce(0) { $0+$1.0.distance(to:$1.1) }
        XCTAssertEqual(length,try XCTUnwrap(path["length_m"] as? Double),accuracy:1e-3)
    }
}

final class JourneyRecorderTests: XCTestCase {
    func testOneStepPerHalfMetreOrTwoSeconds() {
        var recorder=makeRecorder()
        recorder.record(pose:cameraAt(0,1),now:100)
        recorder.record(pose:cameraAt(0,1.3),now:101)
        XCTAssertEqual(recorder.journey.steps.count,1,"30 cm and one second: no step yet")
        recorder.record(pose:cameraAt(0,1.3),now:102)
        XCTAssertEqual(recorder.journey.steps.count,2,"two seconds standing still is a step")
        recorder.record(pose:cameraAt(0,1.8),now:102.5)
        XCTAssertEqual(recorder.journey.steps.count,3,"half a metre is a step")
        XCTAssertEqual(recorder.journey.steps.last?.t,2.5)
        XCTAssertEqual(recorder.journey.steps.last?.y ?? 0,1.8,accuracy:1e-9)
        recorder.record(pose:cameraAt(0,1.8),now:99)
        recorder.record(pose:CameraPose(position:Vector3(.nan,0,0)),now:200)
        XCTAssertEqual(recorder.journey.steps.count,3,"before the start or without a valid pose nothing is recorded")
    }
    func testHeadingIsTheWayTheCameraFacesClockwiseFromOutOfTheTag() {
        XCTAssertEqual(tagFrame.heading(of:cameraAt(0,1)) ?? -1,0,accuracy:1e-9)
        XCTAssertEqual(tagFrame.heading(of:cameraAt(0,1,heading:90)) ?? -1,90,accuracy:1e-9)
        XCTAssertEqual(tagFrame.heading(of:cameraAt(0,1,heading:270)) ?? -1,270,accuracy:1e-9)
        XCTAssertEqual(tagFrame.heading(of: .identity) ?? 0,180,accuracy:1e-9,"the identity camera looks at the tag, back along −y")
        XCTAssertNil(tagFrame.heading(of:CameraPose(position: .zero,right:Vector3(1,0,0),up:Vector3(0,0,-1),back:Vector3(0,1,0))),"looking straight down has no heading")
    }
    func testARecorderNeedsATagOnAWallAndATarget() {
        let flat=RoomFrame(origin: .zero,xAxis:Vector3(1,0,0),yAxis:Vector3(0,1,0),zAxis:Vector3(0,0,1))
        XCTAssertNil(JourneyRecorder(tagId:"feel-tag-01",sessionId:"s",startedAt:startedAt,startUptime:0,targetLabel:"exit",target:exit,frame:flat))
        XCTAssertNil(JourneyRecorder(tagId:"feel-tag-01",sessionId:"s",startedAt:startedAt,startUptime: .nan,targetLabel:"exit",target:exit,frame:tagFrame))
        XCTAssertNil(JourneyRecorder(tagId:"feel-tag-01",sessionId:"s",startedAt:startedAt,startUptime:0,targetLabel:"exit",target:Vector3(.infinity,0,0),frame:tagFrame))
        let recorder=JourneyRecorder(tagId:"feel-tag-01",sessionId:"s",startedAt:startedAt,startUptime:0,targetLabel:"exit",target:exit,frame:tagFrame)
        XCTAssertEqual(recorder?.target.x ?? 0,-4,accuracy:1e-9); XCTAssertEqual(recorder?.target.y ?? 0,5.1,accuracy:1e-9)
        XCTAssertNil(recorder?.journey.userId); XCTAssertNil(recorder?.journey.venueId)
    }
    func testCueLatencyClosesOncePerChange() {
        var recorder=makeRecorder()
        recorder.cueShown(now:100)
        XCTAssertEqual(recorder.journey.cueLatencyMs,[],"a packet without a change is not a latency")
        recorder.targetChanged(now:100); recorder.cueShown(now:100.2); recorder.cueShown(now:100.3)
        XCTAssertEqual(recorder.journey.cueLatencyMs.count,1)
        XCTAssertEqual(recorder.journey.cueLatencyMs[0],200,accuracy:1e-6)
        recorder.targetChanged(now:101); recorder.targetChanged(now:102); recorder.cueShown(now:102.05)
        XCTAssertEqual(recorder.journey.cueLatencyMs.count,2)
        XCTAssertEqual(recorder.journey.cueLatencyMs[1],50,accuracy:1e-6,"a change replaces an unshown change")
    }
    func testBlockedCellsAreKeptOnceAsTagFrameCellCentres() {
        var recorder=makeRecorder()
        recorder.noteBlocked(worldCentres:[Vector3(0.25,0,-2.95),Vector3(0.22,0,-2.91),Vector3(-0.35,0,-1.05)],cellSize:0.1)
        XCTAssertEqual(recorder.journey.obstacles.count,2)
        XCTAssertEqual(recorder.journey.obstacles[0].x,0.25,accuracy:1e-9); XCTAssertEqual(recorder.journey.obstacles[0].y,0.05,accuracy:1e-9)
        XCTAssertEqual(recorder.journey.obstacles[1].x,-0.35,accuracy:1e-9); XCTAssertEqual(recorder.journey.obstacles[1].y,1.95,accuracy:1e-9)
        recorder.noteBlocked(worldCentres:[Vector3(0.25,0,-2.95)],cellSize:0)
        XCTAssertEqual(recorder.journey.obstacles.count,2)
    }
    func testTheEndKeepsTheDistanceLeftToTheTarget() {
        var recorder=makeRecorder(target:Vector3(0.3,0,1.4))
        recorder.record(pose:cameraAt(0,1),now:100)
        XCTAssertFalse(recorder.journey.arrived); XCTAssertNil(recorder.journey.arrivalDistanceM)
        recorder.end(pose:cameraAt(0,4),now:103,arrivedAt:startedAt.addingTimeInterval(3))
        XCTAssertTrue(recorder.journey.arrived)
        XCTAssertEqual(recorder.journey.arrivedAt,startedAt.addingTimeInterval(3))
        XCTAssertEqual(recorder.journey.arrivalDistanceM ?? 0,0.5,accuracy:1e-9)
        XCTAssertEqual(recorder.journey.steps.count,2,"the end pose is the last step")
        var empty=makeRecorder()
        empty.end(pose:nil,now:100,arrivedAt:nil)
        XCTAssertNil(empty.journey.arrivalDistanceM,"no steps, no distance")
    }
}

final class ProgressPointsTests: XCTestCase {
    func testAShortPathHasOnlyItsEnd() {
        XCTAssertEqual(ProgressPoints.split(polyline:[FloorPoint(0,0),FloorPoint(0,4)]),[FloorPoint(0,4)])
        XCTAssertEqual(ProgressPoints.split(polyline:[FloorPoint(2,3)]),[FloorPoint(2,3)])
        XCTAssertEqual(ProgressPoints.split(polyline:[]),[])
        XCTAssertEqual(ProgressPoints.split(polyline:[FloorPoint(0,0),FloorPoint(0,4)],spacing:0),[])
    }
    func testPointsLieEverySpacingAlongTheSegments() {
        let points=ProgressPoints.split(polyline:[FloorPoint(0,0),FloorPoint(0,15)],spacing:6)
        XCTAssertEqual(points,[FloorPoint(0,6),FloorPoint(0,12),FloorPoint(0,15)])
        let corner=ProgressPoints.split(polyline:[FloorPoint(0,0),FloorPoint(0,4),FloorPoint(4,4)],spacing:6)
        XCTAssertEqual(corner.count,2)
        XCTAssertEqual(corner[0].x,2,accuracy:1e-9); XCTAssertEqual(corner[0].y,4,accuracy:1e-9)
        XCTAssertEqual(corner[1],FloorPoint(4,4))
    }
    func testAPointOnTheEndIsNotRepeated() {
        XCTAssertEqual(ProgressPoints.split(polyline:[FloorPoint(0,0),FloorPoint(0,12)],spacing:6),[FloorPoint(0,6),FloorPoint(0,12)])
    }
}

final class WaypointFollowerTests: XCTestCase {
    private let points=[FloorPoint(0,7),FloorPoint(4,9),FloorPoint(8,9)]

    func testTheNextPointIsTheTargetUntilTheUserIsWithinAMetre() {
        var follower=WaypointFollower(points:points)!
        XCTAssertEqual(follower.next,FloorPoint(0,7)); XCTAssertEqual(follower.remaining,3)
        XCTAssertEqual(follower.update(position:FloorPoint(0,1)), .keep)
        XCTAssertEqual(follower.update(position:FloorPoint(0,5.9)), .keep,"1.1 m away")
        XCTAssertEqual(follower.update(position:FloorPoint(0.3,6.2)), .advanced(1))
        XCTAssertEqual(follower.next,FloorPoint(4,9))
        XCTAssertEqual(follower.update(position:FloorPoint(3.5,9)), .advanced(2))
        XCTAssertEqual(follower.update(position:FloorPoint(7.5,9)), .arrived)
        XCTAssertTrue(follower.arrived); XCTAssertNil(follower.next); XCTAssertEqual(follower.remaining,0)
        XCTAssertEqual(follower.update(position:FloorPoint(0,0)), .keep,"arrival is final")
    }
    func testACornerCutSkipsThePointsWithinReach() {
        var follower=WaypointFollower(points:[FloorPoint(0,6),FloorPoint(0,6.5),FloorPoint(0,12)])!
        XCTAssertEqual(follower.update(position:FloorPoint(0,6.3)), .advanced(2))
        XCTAssertEqual(follower.next,FloorPoint(0,12))
    }
    func testTheFollowerNeedsPointsAndAReach() {
        XCTAssertNil(WaypointFollower(points:[]))
        XCTAssertNil(WaypointFollower(points:[FloorPoint(.nan,0)]))
        XCTAssertNil(WaypointFollower(points:points,reachRadius:0))
        XCTAssertEqual(WaypointFollower.reachRadius,1.0)
    }
    func testTheNextPointBecomesAHeldTargetInTheWorld() throws {
        let follower=WaypointFollower(points:points)!
        let target=try XCTUnwrap(follower.target(frame:tagFrame,label:"exit",worldEpoch:3,now:12))
        XCTAssertEqual(target,HeldTarget(position:Vector3(0,0,4),label:"exit",worldEpoch:3,setAt:12),"(0, 7) in the tag frame is 7 m out from the wall at z = −3")
        XCTAssertEqual(FloorPoint(pose:cameraAt(2,5),in:tagFrame),FloorPoint(2,5))
        XCTAssertEqual(FloorPoint(pose:CameraPose(position:Vector3(2,1.2,-5)),in: .worldFloor),FloorPoint(2,-5))
        XCTAssertNotNil(RoomFrame.worldFloor.levelled); XCTAssertTrue(RoomFrame.worldFloor.isValid)
    }
}
