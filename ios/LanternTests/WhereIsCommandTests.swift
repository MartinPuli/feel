import XCTest
import FeelCore
@testable import Lantern

final class MemoryChalkStore: ChalkConfigurationStoring {
    var stored: ChalkConfiguration?
    func loadForLaunch() -> ChalkConfiguration? { stored }
    func save(_ configuration: ChalkConfiguration) throws { stored = configuration }
    func clear() { stored = nil }
}

final class WhereIsCommandTests: XCTestCase {
    private let held = HeldTarget(position: Vector3(0, 0, -2), label: "desk", worldEpoch: 1, setAt: 0)
    private let local = StubLocalFinder()

    private func makeModel(configured: Bool = true) -> (LanternModel, StubChatGateway) {
        let gateway = StubChatGateway()
        let store = MemoryChalkStore()
        if configured {
            store.stored = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost, routerApiKey: String(repeating: "k", count: 16), environmentId: "env", model: "m")
        }
        let voice = RealtimeVoiceSession(configuration: nil, speaksLocally: false)
        let model = LanternModel(voice: voice, chalkStore: store, gatewayFactory: { _ in gateway }, localFinder: local)
        return (model, gateway)
    }

    func testWhereIsCommandDecoding() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "where_is", arguments: #"{"thing":" registration desk "}"#), .whereIs("registration desk"))
        for arguments in ["{}", #"{"thing":""}"#, #"{"thing":"   "}"#, #"{"thing":"\#(String(repeating: "x", count: 61))"}"#,
                          #"{"thing":"desk\u0007"}"#, #"{"thing":"desk","extra":1}"#, #"{"thing":7}"#] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: "where_is", arguments: arguments), arguments)
        }
        XCTAssertTrue(VoiceCommand.tools.contains { ($0["name"] as? String) == "where_is" })
        XCTAssertTrue(VoiceCommand.instructions.contains("where_is"))
    }

    func testWhereIsRefusedUnlessLive() {
        let (model, gateway) = makeModel()
        XCTAssertNotNil(model.performVoiceCommand(.whereIs("desk"))["error"])
        model.startSimulation()
        XCTAssertNotNil(model.performVoiceCommand(.whereIs("desk"))["error"])
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertNil(model.heldTarget)
        model.stop()
    }

    func testRefusalReasonsFollowTheSpecOrder() {
        XCTAssertEqual(LanternModel.whereIsRefusal(mode: .stopped, guidance: .live), "Camera is not live. Ask the user whether to start it.")
        XCTAssertEqual(LanternModel.whereIsRefusal(mode: .live, guidance: .staleDepth), "Sensing isn't ready. Calibrate or wait for tracking, then try again.")
        XCTAssertNil(LanternModel.whereIsRefusal(mode: .live, guidance: .live), "Chalk setup is optional: the on-device finder answers without it")
    }

    func testWhereIsNeedsNoChalkSetup() {
        let (model, gateway) = makeModel(configured: false)
        XCTAssertFalse(model.whereIsAvailable, "Stopped camera")
        XCTAssertEqual(model.voiceSnapshot()["where_is_available"] as? Bool, false)
        var pending: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { pending.append($0) }
        local.outcome = .placed(held)
        model.beginWhereIs("desk")
        pending[0](makeSnapshot())
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertEqual(local.things, ["desk"])
        XCTAssertEqual(model.heldTarget, held)
    }

    func testNewAskClearsThePreviousTargetAndWaitsForItsOwnPhoto() throws {
        let (model, gateway) = makeModel()
        var pending: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { pending.append($0) }
        model.finder = .chair
        model.handleWhereIs(.placed(held), thing: "desk")
        model.beginWhereIs("chair")
        XCTAssertNil(model.heldTarget, "The old target must stop driving the pins at once")
        XCTAssertNil(model.whereIsNotice)
        XCTAssertEqual(model.finder, .none, "A finder target must not shadow the answer")
        model.beginWhereIs("exit")
        pending[0](makeSnapshot())   // the chair photo arrives after the exit ask: dropped
        XCTAssertEqual(gateway.calls, 0)
        pending[1](makeSnapshot())
        XCTAssertEqual(gateway.calls, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(gateway.bodies.first)) as? [String: Any])
        let parts = try XCTUnwrap((body["messages"] as? [[String: Any]])?[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts[0]["text"] as? String, "Where is the exit?")
    }

    func testMemoryRecallCancelsPendingWhereIsPhoto() {
        let (model, gateway) = makeModel()
        defer { model.stop() }
        model.startSimulation(memory: true)
        model.placeName = "Entrance"
        model.remember()
        let place = model.spatialMemory.bookmarks[0].id
        var pending: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { pending.append($0) }
        model.beginWhereIs("desk")
        model.recall()
        pending[0](makeSnapshot())
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertNil(model.heldTarget)
        XCTAssertEqual(model.spatialMemory.activeID, place)
    }

    func testPlacedInAnotherWorldIsNotHeld() {
        let (model, _) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame(worldEpoch: 2))
        XCTAssertNil(model.heldTarget)
        XCTAssertEqual(model.whereIsNotice, "Lost tracking. Say it again.")
    }

    func testPlacedOutsideThePinsFieldSaysWhereItIs() {
        let (model, _) = makeModel()
        let behind = HeldTarget(position: Vector3(0, 0, 3), label: "desk", worldEpoch: 1, setAt: 0)
        model.handleWhereIs(.placed(behind), thing: "desk", frame: makeFrame())
        XCTAssertEqual(model.heldTarget, behind)
        XCTAssertEqual(model.whereIsNotice, "desk is behind you.")
        model.handleWhereIs(.placed(held), thing: "desk", frame: makeFrame())
        XCTAssertEqual(model.whereIsNotice, "The desk was 2 meters ahead.")
    }

    func testUnsupportedThingExplainsTheLocalVocabulary() {
        let (model, _) = makeModel()
        model.handleWhereIs(.unsupported, thing: "unicorn")
        XCTAssertEqual(model.whereIsNotice, "I can only look for the exit, a door, a person, a chair or common objects right now.")
        XCTAssertNil(model.heldTarget)
    }

    func testResultLineIsRetriedOnceTheAssistantIsFree() {
        let (voice, transport) = VoiceTestDoubles.activeSession()
        let model = LanternModel(voice: voice, chalkStore: MemoryChalkStore(), gatewayFactory: { _ in StubChatGateway() }, localFinder: StubLocalFinder())
        model.startSimulation()
        transport.emit(["type": "response.created", "response": ["id": "r1"]])   // the assistant is mid-reply: announce() refuses
        model.handleWhereIs(.notVisible, thing: "desk")
        XCTAssertFalse(transport.json.contains("I couldn't see a desk"))
        transport.emit(["type": "response.done", "response": ["id": "r1"]])
        // The session also allows one announcement per five seconds; the result line must still arrive, once.
        let spoken = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in transport.json.contains("I couldn't see a desk") }, object: nil)
        wait(for: [spoken], timeout: 8)
        XCTAssertEqual(transport.json.components(separatedBy: "I couldn't see a desk").count - 1, 1, "Spoken exactly once")
        model.stop()
    }

    func testPlacedOutcomeHoldsTargetAndSnapshotReportsIt() {
        let (model, _) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk")
        XCTAssertEqual(model.heldTarget, held)
        XCTAssertEqual(model.voiceSnapshot()["held_target"] as? String, "desk")
    }

    func testNotVisibleKeepsNoticeWhenAnnounceCannotSpeak() {
        let (model, _) = makeModel()
        model.handleWhereIs(.notVisible, thing: "desk")
        XCTAssertEqual(model.whereIsNotice, "I couldn't see a desk in the photo.")
        XCTAssertEqual(model.voiceSnapshot()["where_is"] as? String, "I couldn't see a desk in the photo.")
        model.handleWhereIs(.noDepth, thing: "desk")
        XCTAssertEqual(model.whereIsNotice, "I see the desk, but it's too far to point at.")
        model.handleWhereIs(.failed, thing: "desk")
        XCTAssertEqual(model.whereIsNotice, "I couldn't look just now. Try again.")
        XCTAssertNil(model.heldTarget)
    }

    func testStopClearsHeldTarget() {
        let (model, _) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk")
        model.stop()
        XCTAssertNil(model.heldTarget)
    }

    func testFindClearsHeldTarget() {
        let (model, _) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk")
        _ = model.performVoiceCommand(.find(.door))
        XCTAssertNil(model.heldTarget)
    }

    func testWorldEpochChangeClearsHeldTarget() {
        let (model, _) = makeModel()
        model.handleWhereIs(.placed(held), thing: "desk")
        model.perception.onInvalidated?(0)
        XCTAssertNil(model.heldTarget)
        XCTAssertEqual(model.whereIsNotice, "Lost tracking. Say it again.")
    }

    func testSaveAndForgetChalkConfiguration() throws {
        let (model, _) = makeModel(configured: false)
        let configuration = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost, routerApiKey: String(repeating: "k", count: 16), environmentId: "env", model: "m")
        try model.saveChalkConfiguration(configuration)
        XCTAssertEqual(model.chalkConfiguration, configuration)
        XCTAssertThrowsError(try model.saveChalkConfiguration(ChalkConfiguration(apiHost: "http://x", routerApiKey: "k", environmentId: "e", model: "m")))
        model.forgetChalkConfiguration()
        XCTAssertNil(model.chalkConfiguration)
    }

    func testNamedObservationPhrase() {
        XCTAssertEqual(VoicePhrasing.observation(TargetObservation(bearingDegrees: 30, distance: 3, timestamp: 1), named: "desk", now: 1), "The desk was 3 meters to your right.")
        XCTAssertEqual(VoicePhrasing.observation(TargetObservation(bearingDegrees: -30, distance: 1, timestamp: 1), named: "water fountain", now: 1), "The water fountain was 1 meter to your left.")
        XCTAssertEqual(VoicePhrasing.observation(TargetObservation(bearingDegrees: 2, distance: 2.5, timestamp: 1), named: "desk", now: 1), "The desk was 2.5 meters ahead.")
        XCTAssertNil(VoicePhrasing.observation(TargetObservation(bearingDegrees: 0, distance: 2, timestamp: 1), named: "desk", now: 9))
    }
}
