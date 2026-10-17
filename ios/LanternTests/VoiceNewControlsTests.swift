import XCTest
import FeelCore
@testable import Lantern

final class VoiceNewControlsTests: XCTestCase {
    private func makeModel() -> (LanternModel, StubChatGateway) {
        let gateway = StubChatGateway()
        let store = MemoryChalkStore()
        store.stored = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost,
                                         routerApiKey: String(repeating: "k", count: 16),
                                         environmentId: "test", model: "test")
        let model = LanternModel(voice: RealtimeVoiceSession(configuration: nil, speaksLocally: false),
                                 chalkStore: store, gatewayFactory: { _ in gateway }, localFinder: StubLocalFinder())
        return (model, gateway)
    }

    func testFinderChangeDropsBothDelayedPhotoAndDelayedAnswer() {
        let (model, gateway) = makeModel()
        var photos: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { photos.append($0) }
        model.beginWhereIs("desk")
        model.finder = .door
        photos[0](makeSnapshot())
        XCTAssertEqual(gateway.calls, 0)

        model.beginWhereIs("desk")
        photos[1](makeSnapshot())
        XCTAssertEqual(gateway.calls, 1)
        model.finder = .exit
        gateway.reply(0, .success(#"{"found":true,"label":"desk","box":[0.4,0.4,0.6,0.6],"confidence":0.9}"#))
        XCTAssertNil(model.heldTarget)
        XCTAssertNil(model.whereIsNotice)
        XCTAssertFalse(model.routeGoalActive)
        XCTAssertEqual(model.finder, .exit)
    }

    func testTrackingInvalidationDropsPhotoBeforeGatewayRequest() {
        let (model, gateway) = makeModel()
        var photo: ((FrameSnapshot?) -> Void)?
        model.snapshotProvider = { photo = $0 }
        model.beginWhereIs("desk")
        model.perception.onInvalidated?(0)
        photo?(makeSnapshot())
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertNil(model.heldTarget)
    }

    func testChangedSetupDropsPhotoFromPreviousConfiguration() throws {
        let (model, gateway) = makeModel()
        var photo: ((FrameSnapshot?) -> Void)?
        model.snapshotProvider = { photo = $0 }
        model.beginWhereIs("desk")
        model.forgetChalkConfiguration()
        photo?(makeSnapshot())
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertNil(model.whereIsNotice)
    }

    func testDirectionsRequireLiveFreshEnabledAndSelectedTarget() {
        XCTAssertNotNil(LanternModel.directionsRefusal(mode: .stopped, guidance: .live, arrowsEnabled: true, hasTarget: true))
        XCTAssertNotNil(LanternModel.directionsRefusal(mode: .simulation, guidance: .live, arrowsEnabled: true, hasTarget: true))
        for state in [GuidanceState.staleDepth, .trackingLost, .uncalibrated] {
            XCTAssertNotNil(LanternModel.directionsRefusal(mode: .live, guidance: state, arrowsEnabled: true, hasTarget: true))
        }
        XCTAssertNotNil(LanternModel.directionsRefusal(mode: .live, guidance: .live, arrowsEnabled: false, hasTarget: true))
        XCTAssertNotNil(LanternModel.directionsRefusal(mode: .live, guidance: .live, arrowsEnabled: true, hasTarget: false))
        XCTAssertNil(LanternModel.directionsRefusal(mode: .live, guidance: .live, arrowsEnabled: true, hasTarget: true))
    }

    func testDirectionControlsPreserveSensingAndListening() {
        let (voice, _) = VoiceTestDoubles.activeSession()
        let model = LanternModel(voice: voice, chalkStore: MemoryChalkStore(), localFinder: StubLocalFinder())
        let oldArrows = model.arrowsEnabled
        defer { model.arrowsEnabled = oldArrows; model.stop(stopVoice: true) }
        model.startSimulation()
        XCTAssertNotNil(model.performVoiceCommand(.startDirections)["error"])
        XCTAssertNil(model.performVoiceCommand(.setDirectionArrows(true))["error"])
        XCTAssertNil(model.performVoiceCommand(.simulateDirectionSign)["error"])
        XCTAssertNil(model.performVoiceCommand(.stopDirections)["error"])
        XCTAssertEqual(model.mode, .simulation)
        XCTAssertTrue(voice.isActive)
        XCTAssertFalse(model.guiding)
        XCTAssertEqual(model.voiceSnapshot()["directions_pending"] as? Bool, false)
        _ = model.performVoiceCommand(.setDirectionArrows(false))
        XCTAssertNotNil(model.performVoiceCommand(.simulateDirectionSign)["error"])
    }

    func testRecordingRejectsStoppedAndSyntheticCameraWithoutCreatingFiles() {
        let (model, _) = makeModel()
        defer { model.stop() }
        XCTAssertNotNil(model.performVoiceCommand(.startRecording(false))["error"])
        XCTAssertFalse(model.recordingDepth)
        model.startSimulation()
        XCTAssertNotNil(model.performVoiceCommand(.startRecording(false))["error"])
        XCTAssertFalse(model.recordingDepth)
        XCTAssertNil(model.performVoiceCommand(.stopRecording)["error"])
        XCTAssertEqual(model.voiceSnapshot()["recording_requested"] as? Bool, false)
    }

    func testVideoPreferenceReportsNextRecordingAndSnapshotState() {
        let (model, _) = makeModel()
        let previous = model.recordingVideo
        defer { model.recordingVideo = previous }
        for enabled in [false, true] {
            let result = model.performVoiceCommand(.setRecordingVideo(enabled))
            XCTAssertNil(result["error"])
            XCTAssertTrue((result["status"] as? String)?.contains("next recording") == true)
            XCTAssertEqual(model.voiceSnapshot()["recording_includes_video"] as? Bool, enabled)
            XCTAssertFalse(model.recordingDepth)
        }
    }
}
