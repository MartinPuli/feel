import XCTest
import FeelCore
@testable import Lantern

/// The journey loop on the phone: a walk toward a chosen target is recorded in the room tag's frame and kept as JSON,
/// and the route to a remembered target is followed one progress point at a time. The pins show live depth throughout;
/// a journey only chooses where they point.
final class JourneyTests: XCTestCase {
    private var directory: URL!
    private var journeys: URL!
    private var exportFile: URL!
    private var store: RoomMemoryStore!
    private let local = StubLocalFinder()
    private let seenAt = ISO8601DateFormatter().date(from: "2026-10-17T20:00:00Z")!
    /// The tag upright on the wall 3 m ahead of the identity camera: out of the tag is world +z, down is −y, right along it is +x.
    private let tagFrame = RoomFrame(origin: Vector3(0, 0, -3), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 0, 1), zAxis: Vector3(0, -1, 0))
    private let held = HeldTarget(position: Vector3(0, 0, -2), label: "desk", worldEpoch: 1, setAt: 0)
    /// A route from 10 m behind the camera's origin to the remembered exit at (−1, 0, −2): 13 m, so three progress points.
    private let route = [Vector3(0, 0, 10), Vector3(0, 0, -2), Vector3(-1, 0, -2)]
    /// The model stamps a journey's start with the system uptime; ticks are timed after it.
    private let t0 = ProcessInfo.processInfo.systemUptime + 1

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        journeys = directory.appendingPathComponent("Journeys"); exportFile = directory.appendingPathComponent("Documents/journeys.json")
        store = RoomMemoryStore(directory: directory.appendingPathComponent("RoomMemory"))
        // Remembered on an earlier visit: the exit 1 m out from the tag and 1 m to the tag's left, i.e. 2 m ahead-left of the camera now.
        try store.append(RoomAnchor(label: "exit", position: Vector3(-1, 1, 0), confidence: 0.9, seenAt: seenAt), tagId: "feel-tag-01")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func sighting(worldEpoch: Int = 1) -> TagSighting { TagSighting(tagId: "feel-tag-01", frame: tagFrame, worldEpoch: worldEpoch, timestamp: 1) }
    private func makeModel() -> (LanternModel, RoomMemory, JourneyLog) {
        let memory = RoomMemory(store: store, now: { self.seenAt.addingTimeInterval(3600) })
        let log = JourneyLog(directory: journeys, exportFile: exportFile, now: { self.seenAt.addingTimeInterval(3600) })
        let model = LanternModel(voice: RealtimeVoiceSession(configuration: nil, speaksLocally: false), chalkStore: MemoryChalkStore(),
                                 gatewayFactory: { _ in StubChatGateway() }, localFinder: local, roomMemory: memory, journeyLog: log)
        model.arrowsEnabled = true   // the route planner is what the progress points come from
        model.snapshotProvider = { _ in }   // a photo ask never answers here
        return (model, memory, log)
    }
    private func frame(at position: Vector3, worldEpoch: Int = 1, path: [Vector3]? = nil, blocked: [Vector3]? = nil) -> PerceptionFrame {
        var frame = makeFrame(worldEpoch: worldEpoch, pose: CameraPose(position: position))
        frame.routePath = path; frame.blockedCells = blocked
        return frame
    }
    private let shown = EncoderOutput(packet: .neutral(sequence: 1), state: .live, targetColumns: 3...3)
    private let neutral = EncoderOutput(packet: .neutral(sequence: 1), state: .live)
    private func journeyStatus(_ model: LanternModel) throws -> [String: Any] {
        try XCTUnwrap((model.voiceSnapshot()["room_memory"] as? [String: Any])?["journey"] as? [String: Any])
    }
    /// Two ticks half a metre apart: the smallest walk the log keeps.
    private func walk(_ model: LanternModel, from now: Double) {
        model.recordJourney(frame: frame(at: Vector3(0, 0, 0)), output: neutral, now: now)
        model.recordJourney(frame: frame(at: Vector3(0, 0, -1)), output: neutral, now: now + 1)
    }

    // MARK: The log

    func testAJourneyStartsWithATargetWhileTheTagIsSeenAndNotOtherwise() {
        let (model, memory, log) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        XCTAssertFalse(log.isRecording, "no tag seen in this world: nothing to record in")
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
        XCTAssertTrue(log.isRecording)
        XCTAssertEqual(log.current?.journey.targetLabel, "exit")
        XCTAssertEqual(log.current?.journey.tagId, "feel-tag-01")
        XCTAssertEqual(log.current?.journey.sessionId, log.sessionId)
        XCTAssertEqual(log.current?.journey.startedAt, seenAt.addingTimeInterval(3600))
        XCTAssertEqual(log.current?.target, FloorPoint(-1, 1), "the exit on the tag floor")
        memory.forgetTag()
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        XCTAssertFalse(log.isRecording, "the target change ended the walk and the new one has no tag frame")
    }
    func testTheWalkIsRecordedFromTheTickAndKeptOnArrival() throws {
        let (model, memory, log) = makeModel()
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: frame(at: Vector3(0, 0, 10))))
        model.recordJourney(frame: frame(at: Vector3(0, 0, 10)), output: neutral, now: t0)
        model.recordJourney(frame: frame(at: Vector3(0, 0, 9.4), blocked: [Vector3(0.55, 0, 3.05), Vector3(0.55, 0, 3.05)]), output: shown, now: t0 + 0.3)
        model.recordJourney(frame: frame(at: Vector3(0, 0, 9.4)), output: shown, now: t0 + 0.4)
        let journey = try XCTUnwrap(log.current?.journey)
        XCTAssertEqual(journey.steps.count, 2, "one step per half metre")
        XCTAssertEqual(journey.steps.last?.x ?? -1, 0, accuracy: 1e-9); XCTAssertEqual(journey.steps.last?.y ?? 0, 12.4, accuracy: 1e-9)
        XCTAssertEqual(journey.steps.last?.headingDeg ?? 0, 180, accuracy: 1e-9, "facing the tag")
        XCTAssertEqual(journey.obstacles.count, 1, "the blocked cell, once, in the tag frame")
        XCTAssertEqual(journey.obstacles.first?.x ?? 0, 0.55, accuracy: 1e-9); XCTAssertEqual(journey.obstacles.first?.y ?? 0, 6.05, accuracy: 1e-9)
        XCTAssertEqual(journey.cueLatencyMs.count, 1, "the first packet that showed the target closed the latency")
        var status = try journeyStatus(model)
        XCTAssertEqual(status["active"] as? Bool, true); XCTAssertEqual(status["target"] as? String, "exit")
        XCTAssertEqual(status["steps"] as? Int, 2); XCTAssertEqual(status["obstacles"] as? Int, 1); XCTAssertEqual(status["stored"] as? Int, 0)
        let target = try XCTUnwrap(model.heldTarget)
        model.handleHeldEvent(.reached, target: target, now: t0 + 1, pose: CameraPose(position: Vector3(-0.7, 0, -2)))
        XCTAssertFalse(log.isRecording); XCTAssertNil(model.heldTarget)
        let kept = try XCTUnwrap(log.journeys.last)
        XCTAssertTrue(kept.arrived)
        XCTAssertEqual(kept.arrivalDistanceM ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(kept.steps.count, 3, "the arrival pose is the last step")
        let file = log.file(for: kept)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Journey.decoder.decode(Journey.self, from: Data(contentsOf: file)), kept)
        XCTAssertEqual(file.lastPathComponent, "20261017T210000Z-\(log.sessionId.prefix(8)).json")
        status = try journeyStatus(model)
        XCTAssertEqual(status["active"] as? Bool, false); XCTAssertEqual(status["stored"] as? Int, 1); XCTAssertEqual(status["next_point"] as? String, "none")
    }
    func testATargetChangeAStopOrLostTrackingEndsTheWalkUnarrived() throws {
        let (model, memory, log) = makeModel()
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
        walk(model, from: t0)
        XCTAssertNil(model.beginWhereIs("chair", frame: makeFrame()), "the camera looks for the chair")
        XCTAssertEqual(log.journeys.count, 1)
        let first = try XCTUnwrap(log.journeys.last)
        XCTAssertFalse(first.arrived)
        XCTAssertEqual(first.arrivalDistanceM ?? 0, 1.414, accuracy: 1e-3, "from the last step (0, 2) to the exit (−1, 1) on the tag floor")
        XCTAssertFalse(log.isRecording, "the chair is not held until the photo answers")
        XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
        walk(model, from: t0 + 10)
        model.perception.onInvalidated?(0)
        XCTAssertEqual(log.journeys.count, 2, "lost tracking ends the walk")
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
        walk(model, from: t0 + 20)
        model.stop()
        XCTAssertEqual(log.journeys.count, 3, "stop ends the walk")
        XCTAssertEqual(log.journeys.map(\.arrived), [false, false, false])
        XCTAssertEqual(log.dropped, 0)
    }
    func testAWalkOfOneStepIsDroppedNotStored() throws {
        let (model, memory, log) = makeModel()
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
        model.recordJourney(frame: frame(at: Vector3(0, 0, 0)), output: neutral, now: t0)
        model.stop()
        XCTAssertEqual(log.journeys.count, 0); XCTAssertEqual(log.dropped, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journeys.path))
    }
    func testStoredJourneysLoadAgainAndExportAsOneArray() throws {
        let (model, memory, log) = makeModel()
        memory.sawTag(sighting())
        for k in 0..<2 {
            XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
            walk(model, from: t0 + Double(k) * 10)
            model.stop(); memory.sawTag(sighting())
        }
        XCTAssertEqual(log.journeys.count, 2)
        let again = JourneyLog(directory: journeys, exportFile: exportFile)
        XCTAssertEqual(again.journeys.count, 1, "both walks started at the same stamped second: the file was replaced")
        let url = try again.export()
        XCTAssertEqual(url, exportFile)
        let exported = try Journey.decoder.decode([Journey].self, from: Data(contentsOf: url))
        XCTAssertEqual(exported, again.journeys)
        XCTAssertEqual(JourneyLog.exportFile.lastPathComponent, "journeys.json")
        XCTAssertEqual(JourneyLog.exportFile.deletingLastPathComponent(), FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
        XCTAssertEqual(JourneyLog.directory.lastPathComponent, "Journeys")
        XCTAssertEqual(JourneyLog.directory.deletingLastPathComponent(), RoomMemory.directory.deletingLastPathComponent(), "beside RoomMemory")
    }
    func testEveryKeptJourneyLeavesThroughTheUploader() throws {
        let uploader = RecordingUploader()
        let log = JourneyLog(directory: journeys, exportFile: exportFile)
        log.uploader = uploader
        log.begin(targetLabel: "exit", target: Vector3(-1, 0, -2), sighting: sighting(), startUptime: 1)
        log.record(pose: CameraPose(position: Vector3(0, 0, 0)), now: 1)
        log.record(pose: CameraPose(position: Vector3(0, 0, -1)), now: 2)
        let kept = try XCTUnwrap(log.end(arrived: false, pose: nil, now: 3))
        XCTAssertEqual(uploader.journeys, [kept], "the journey kept on the phone is the one uploaded")
        log.begin(targetLabel: "exit", target: Vector3(-1, 0, -2), sighting: sighting(), startUptime: 4)
        XCTAssertNil(log.end(arrived: false, pose: nil, now: 4.1))
        XCTAssertEqual(uploader.journeys.count, 1, "a walk too short to keep is not uploaded either")
    }

    // MARK: Following

    func testTheRouteIsSplitOnceAndThePinsPointToTheNextPointUntilArrival() throws {
        let (model, memory, log) = makeModel()
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: frame(at: Vector3(0, 0, 10))))
        let exit = try XCTUnwrap(model.heldTarget)
        XCTAssertEqual(exit.position, Vector3(-1, 0, -2))
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 10)), now: t0)
        XCTAssertNil(model.waypoint, "no route yet: the straight bearing to the target shows")
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 10), path: route), now: t0 + 0.4)
        XCTAssertEqual(model.waypoint?.position, Vector3(0, 0, 4), "6 m along the route")
        XCTAssertEqual(model.waypoint?.label, "exit")
        var status = try journeyStatus(model)
        XCTAssertEqual(status["next_point"] as? String, "0"); XCTAssertEqual(status["points"] as? Int, 3)
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 7), path: [Vector3(0, 0, 7), Vector3(-1, 0, -2)]), now: t0 + 1)
        XCTAssertEqual(model.waypoint?.position, Vector3(0, 0, 4), "a later route does not move the points")
        model.followWaypoints(frame: frame(at: Vector3(0.2, 0, 4.5)), now: t0 + 2)
        XCTAssertEqual(model.waypoint?.position, Vector3(0, 0, -2), "within a metre: the next point")
        XCTAssertEqual(model.whereIsNotice, "Next point.")
        XCTAssertEqual(try journeyStatus(model)["next_point"] as? String, "1")
        model.recordJourney(frame: frame(at: Vector3(0.2, 0, 4.5)), output: shown, now: t0 + 2.1)
        model.followWaypoints(frame: frame(at: Vector3(0, 0, -1.5)), now: t0 + 3)
        XCTAssertEqual(model.waypoint?.position, Vector3(-1, 0, -2), "the last point is the target")
        model.recordJourney(frame: frame(at: Vector3(0, 0, -1.5)), output: shown, now: t0 + 3.1)
        XCTAssertEqual(log.current?.journey.cueLatencyMs.count, 2, "each progress point change is a latency once shown")
        model.followWaypoints(frame: frame(at: Vector3(-0.5, 0, -2)), now: t0 + 4)
        XCTAssertNil(model.heldTarget); XCTAssertNil(model.waypoint)
        XCTAssertEqual(model.whereIsNotice, "You're there, at the exit.")
        let kept = try XCTUnwrap(log.journeys.last)
        XCTAssertTrue(kept.arrived); XCTAssertEqual(kept.arrivalDistanceM ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(store.anchors(for: "feel-tag-01").count, 2, "arrival is remembered like reaching the target")
        status = try journeyStatus(model)
        XCTAssertEqual(status["active"] as? Bool, false); XCTAssertEqual(status["next_point"] as? String, "none")
    }
    func testFollowingNeedsTheTargetsWorldAndWorksWithoutATagOnTheWorldFloor() {
        let (model, _, log) = makeModel()
        model.handleWhereIs(.placed(HeldTarget(position: Vector3(-1, 0, -2), label: "exit", worldEpoch: 1, setAt: 0)), thing: "exit", frame: frame(at: Vector3(0, 0, 10)))
        XCTAssertFalse(log.isRecording, "no tag: no journey")
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 10), worldEpoch: 2, path: route), now: t0)
        XCTAssertNil(model.waypoint, "a route from another world is ignored")
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 10), path: route), now: t0 + 0.4)
        XCTAssertEqual(model.waypoint?.position, Vector3(0, 0, 4), "the world floor is the frame when no tag was seen")
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 4.2)), now: t0 + 1)
        XCTAssertEqual(model.waypoint?.position, Vector3(0, 0, -2))
    }
    func testAShortRouteArrivesAtOnce() {
        let (model, _, _) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        model.followWaypoints(frame: frame(at: Vector3(0, 0, -1.2), path: [Vector3(0, 0, -1.2), Vector3(0, 0, -2)]), now: t0)
        XCTAssertNil(model.heldTarget)
        XCTAssertEqual(model.whereIsNotice, "You're there, at the desk.")
    }
    func testArrowsOffMeansNoRouteAndTheStraightBearing() {
        let (model, _, _) = makeModel()
        model.arrowsEnabled = false
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        model.followWaypoints(frame: frame(at: Vector3(0, 0, 10), path: route), now: t0)
        XCTAssertNil(model.waypoint)
        XCTAssertNotNil(model.heldTarget)
    }

    // MARK: lead_me

    func testLeadMeHoldsARememberedPlaceAndStartsAJourney() throws {
        let (model, memory, log) = makeModel()
        XCTAssertNil(model.beginLeading("exit", frame: makeFrame()), "no tag seen")
        memory.sawTag(sighting())
        XCTAssertNil(model.beginLeading("chair", frame: makeFrame()), "not remembered")
        XCTAssertEqual(memory.misses, 0, "the check does not count")
        let line = model.beginLeading("Exit", frame: makeFrame())
        XCTAssertEqual(line, "Leading you to the exit. Last time it was about 2 meters ahead to your left. Pins point the way, one point at a time.")
        XCTAssertEqual(model.whereIsNotice, line)
        XCTAssertEqual(model.heldTarget?.position, Vector3(-1, 0, -2))
        XCTAssertTrue(log.isRecording); XCTAssertEqual(memory.hits, 1)
        XCTAssertNil(model.beginLeading("chair", frame: makeFrame()))
        XCTAssertNotNil(model.heldTarget, "a failed lead_me leaves the held target alone")
        XCTAssertNotNil(model.performVoiceCommand(.leadMe("exit"))["error"], "the camera is not live in a test")
    }
    func testLeadMeDecodesAndIsDescribedToTheAssistant() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "lead_me", arguments: #"{"label":"exit"}"#), .leadMe("exit"))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "lead_me", arguments: "{}"))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "lead_me", arguments: #"{"label":"exit","photo":true}"#))
        let tool = try XCTUnwrap(VoiceCommand.tools.first { ($0["name"] as? String) == "lead_me" })
        XCTAssertNotNil(((tool["parameters"] as? [String: Any])?["properties"] as? [String: Any])?["label"])
        XCTAssertTrue(VoiceCommand.instructions.contains("lead_me"))
        XCTAssertTrue((tool["description"] as? String)?.contains("never a clear or safe path") == true)
    }
}
