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

    private func makeModel(configured: Bool = true) -> (LanternModel, StubChatGateway) {
        let gateway = StubChatGateway()
        let store = MemoryChalkStore()
        if configured {
            store.stored = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost, routerApiKey: String(repeating: "k", count: 16), environmentId: "env", model: "m")
        }
        let voice = RealtimeVoiceSession(configuration: nil, speaksLocally: false)
        let model = LanternModel(voice: voice, chalkStore: store, gatewayFactory: { _ in gateway })
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
        XCTAssertEqual(LanternModel.whereIsRefusal(mode: .stopped, configured: true, guidance: .live), "Camera is not live. Ask the user whether to start it.")
        XCTAssertEqual(LanternModel.whereIsRefusal(mode: .live, configured: false, guidance: .live), "Where-is needs Chalk setup in Assistant settings.")
        XCTAssertEqual(LanternModel.whereIsRefusal(mode: .live, configured: true, guidance: .staleDepth), "Sensing isn't ready. Calibrate or wait for tracking, then try again.")
        XCTAssertNil(LanternModel.whereIsRefusal(mode: .live, configured: true, guidance: .live))
    }

    func testWhereIsAvailableNeedsConfiguration() {
        XCTAssertFalse(makeModel(configured: false).0.whereIsAvailable)
        XCTAssertEqual(makeModel(configured: false).0.voiceSnapshot()["where_is_available"] as? Bool, false)
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
