import XCTest
import FeelCore
@testable import Lantern

/// Room memory on the phone: a printed tag seen this session plus anchors stored from earlier visits answer
/// "where is X?" at once; anything less goes to the camera. Memory shortcuts the question, never the pins.
final class RoomMemoryTests: XCTestCase {
    private var directory: URL!
    private var store: RoomMemoryStore!
    private let local = StubLocalFinder()
    private let seenAt = ISO8601DateFormatter().date(from: "2026-10-17T20:00:00Z")!
    private let held = HeldTarget(position: Vector3(0, 0, -2), label: "desk", worldEpoch: 1, setAt: 0)
    /// The tag upright on the wall 3 m ahead of the identity camera: out of the tag is world +z, down is −y, right along it is +x.
    private let tagFrame = RoomFrame(origin: Vector3(0, 0, -3), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 0, 1), zAxis: Vector3(0, -1, 0))

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RoomMemoryStore(directory: directory)
        // Remembered on an earlier visit: the exit 1 m out from the tag and 1 m to the tag's left, i.e. 2 m ahead-left of the camera now.
        try store.append(RoomAnchor(label: "exit", position: Vector3(-1, 1, 0), confidence: 0.9, seenAt: seenAt), tagId: "feel-tag-01")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func sighting(worldEpoch: Int = 1) -> TagSighting { TagSighting(tagId: "feel-tag-01", frame: tagFrame, worldEpoch: worldEpoch, timestamp: 1) }
    private func makeModel() -> (LanternModel, StubChatGateway, RoomMemory) {
        let gateway = StubChatGateway(), chalk = MemoryChalkStore()
        chalk.stored = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost, routerApiKey: String(repeating: "k", count: 16), environmentId: "env", model: "m")
        let memory = RoomMemory(store: store, now: { self.seenAt.addingTimeInterval(3600) })
        let model = LanternModel(voice: RealtimeVoiceSession(configuration: nil, speaksLocally: false), chalkStore: chalk,
                                 gatewayFactory: { _ in gateway }, localFinder: local, roomMemory: memory)
        return (model, gateway, memory)
    }

    func testRememberedTargetIsHeldAtOnceWithoutAPhoto() throws {
        let (model, gateway, memory) = makeModel()
        var pending: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { pending.append($0) }
        memory.sawTag(sighting())
        let line = model.beginWhereIs("Exit", frame: makeFrame())
        XCTAssertEqual(line, "Last time the exit was about 2 meters ahead to your left. Pins point there. Say photo to check again.")
        XCTAssertEqual(model.whereIsNotice, line)
        XCTAssertEqual(model.heldTarget, HeldTarget(position: Vector3(-1, 0, -2), label: "exit", worldEpoch: 1, setAt: try XCTUnwrap(model.heldTarget?.setAt)))
        XCTAssertTrue(pending.isEmpty, "No photo is taken when memory answers")
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertEqual(memory.hits, 1)
        XCTAssertEqual(memory.misses, 0)
    }

    func testPhotoRequestAndUnknownLabelsGoToTheCamera() {
        let (model, _, memory) = makeModel()
        var pending: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { pending.append($0) }
        memory.sawTag(sighting())
        XCTAssertNil(model.beginWhereIs("exit", photo: true, frame: makeFrame()), "Say photo: the camera looks even though memory has the exit")
        XCTAssertEqual(pending.count, 1)
        XCTAssertNil(model.heldTarget)
        XCTAssertNil(model.beginWhereIs("chair", frame: makeFrame()))
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(memory.hits, 0, "A photo request is neither a hit nor a miss")
        XCTAssertEqual(memory.misses, 1, "An unknown label is a miss")
    }

    func testMemoryNeedsATagFromThisWorld() {
        let (model, _, memory) = makeModel()
        XCTAssertNil(model.recallWhereIs("exit", frame: makeFrame()), "No tag seen this session")
        memory.sawTag(sighting(worldEpoch: 1))
        XCTAssertNil(model.recallWhereIs("exit", frame: makeFrame(worldEpoch: 2)), "The tag was seen in a world that has since reset")
        XCTAssertNil(model.recallWhereIs("exit", frame: nil), "No live frame, no memory answer")
        XCTAssertNil(model.heldTarget)
        XCTAssertEqual(memory.misses, 3)
    }

    func testTrackingResetAndStopForgetTheTagFrame() {
        let (model, _, memory) = makeModel()
        memory.sawTag(sighting())
        model.perception.onInvalidated?(0)
        XCTAssertNil(memory.sighting)
        XCTAssertNil(model.recallWhereIs("exit", frame: makeFrame()))
        memory.sawTag(sighting())
        model.stop()
        XCTAssertNil(memory.sighting)
        XCTAssertEqual(memory.anchors.map(\.label), ["exit"], "What was loaded for the tag stays until another tag is seen")
    }

    func testFoundItRemembersTheHeldTargetInTheTagFrame() {
        let (model, _, memory) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        XCTAssertEqual(model.performVoiceCommand(.foundIt)["remembered"] as? Bool, false, "No tag in view: nothing is kept, and the app says so")
        XCTAssertNil(model.heldTarget)
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        memory.sawTag(sighting())
        let reply = model.performVoiceCommand(.foundIt)
        XCTAssertEqual(reply["remembered"] as? Bool, true)
        XCTAssertEqual(reply["status"] as? String, "Noted. The desk is remembered for this room.")
        XCTAssertNil(model.heldTarget, "Found it ends the guidance")
        let desk = store.anchors(for: "feel-tag-01").last
        XCTAssertEqual(desk?.label, "desk")
        XCTAssertEqual(desk?.position, Vector3(0, 1, 0), "2 m ahead of the camera is 1 m out from the tag on the wall 3 m away")
        XCTAssertEqual(desk?.confidence, 0.9)
        XCTAssertEqual(desk?.seenAt, seenAt.addingTimeInterval(3600))
        XCTAssertNotNil(model.performVoiceCommand(.foundIt)["error"], "Nothing is held now")
    }

    func testReachingATargetRemembersItToo() {
        let (model, _, memory) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        memory.sawTag(sighting())
        model.handleHeldEvent(.reached, target: held, now: 5)
        XCTAssertEqual(model.whereIsNotice, "You're at the desk.")
        XCTAssertNil(model.heldTarget)
        XCTAssertEqual(store.anchors(for: "feel-tag-01").last?.confidence, 0.7, "Arrival is weaker evidence than the user's own found it")
        XCTAssertEqual(store.anchors(for: "feel-tag-01").count, 2)
    }

    func testRecalledTargetsReinforceMemoryAndSurviveARestart() throws {
        let (model, _, memory) = makeModel()
        memory.sawTag(sighting())
        XCTAssertNotNil(model.beginWhereIs("exit", frame: makeFrame()))
        _ = model.performVoiceCommand(.foundIt)
        XCTAssertEqual(store.anchors(for: "feel-tag-01").count, 2)
        let again = RoomMemory(store: RoomMemoryStore(directory: directory))
        again.sawTag(sighting())
        XCTAssertEqual(again.recall("exit", worldEpoch: 1, now: 9)?.position, Vector3(-1, 0, -2))
    }

    func testStatusReportsTheTagAndTheCounts() {
        let (model, _, memory) = makeModel()
        var status = model.voiceSnapshot()["room_memory"] as? [String: Any]
        XCTAssertEqual(status?["tag"] as? String, "none")
        XCTAssertEqual(status?["remembered"] as? [String], [])
        memory.sawTag(sighting())
        _ = model.recallWhereIs("exit", frame: makeFrame())
        _ = model.recallWhereIs("chair", frame: makeFrame())
        status = model.voiceSnapshot()["room_memory"] as? [String: Any]
        XCTAssertEqual(status?["tag"] as? String, "feel-tag-01")
        XCTAssertEqual(status?["remembered"] as? [String], ["exit"])
        XCTAssertEqual(status?["hits"] as? Int, 1)
        XCTAssertEqual(status?["misses"] as? Int, 1)
        XCTAssertTrue((status?["note"] as? String)?.contains("live depth") == true)
    }

    func testCommandsDecode() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "found_it", arguments: "{}"), .foundIt)
        XCTAssertThrowsError(try VoiceCommand.decode(name: "found_it", arguments: #"{"thing":"desk"}"#))
        XCTAssertEqual(try VoiceCommand.decode(name: "where_is", arguments: #"{"thing":"exit","photo":true}"#), .whereIs("exit", photo: true))
        XCTAssertEqual(try VoiceCommand.decode(name: "where_is", arguments: #"{"thing":"exit","photo":false}"#), .whereIs("exit"))
        for arguments in [#"{"thing":"exit","photo":1}"#, #"{"thing":"exit","photo":"yes"}"#, #"{"photo":true}"#] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: "where_is", arguments: arguments), arguments)
        }
        XCTAssertTrue(VoiceCommand.tools.contains { ($0["name"] as? String) == "found_it" })
        let whereIs = try XCTUnwrap(VoiceCommand.tools.first { ($0["name"] as? String) == "where_is" })
        XCTAssertNotNil(((whereIs["parameters"] as? [String: Any])?["properties"] as? [String: Any])?["photo"])
        XCTAssertTrue(VoiceCommand.instructions.contains("found_it"))
        XCTAssertTrue(VoiceCommand.instructions.contains("photo"))
    }

    func testRememberedPhraseIsPastTenseWithRoughDistanceAndSide() {
        XCTAssertEqual(VoicePhrasing.remembered("exit", bearingDegrees: 3, distance: 2.04), "Last time the exit was about 2 meters ahead. Pins point there. Say photo to check again.")
        XCTAssertEqual(VoicePhrasing.remembered("exit", bearingDegrees: -40, distance: 6.3), "Last time the exit was about 6 meters ahead to your left. Pins point there. Say photo to check again.")
        XCTAssertEqual(VoicePhrasing.remembered("water fountain", bearingDegrees: 100, distance: 3), "Last time the water fountain was about 3 meters to your right. Pins point there. Say photo to check again.")
        XCTAssertEqual(VoicePhrasing.remembered("desk", bearingDegrees: 170, distance: 1.2), "Last time the desk was about 1 meter behind you. Pins point there. Say photo to check again.")
        XCTAssertEqual(VoicePhrasing.remembered("desk", bearingDegrees: 0, distance: 0.3), "Last time the desk was about 1 meter ahead. Pins point there. Say photo to check again.")
    }

    func testPerceptionOffersATagCallback() {
        let perception = ARPerception()
        var seen: [TagSighting] = []
        perception.onTag = { _, sighting in seen.append(sighting) }
        perception.onTag?(0, sighting())
        XCTAssertEqual(seen.map(\.tagId), ["feel-tag-01"])
        XCTAssertEqual(ARPerception.roomTagWidthMetres, 0.20, "The printed tag must be 20 cm wide")
    }
}
