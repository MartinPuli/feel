import XCTest
@testable import Lantern

final class VoiceActionIntegrationTests: XCTestCase {
    private func makeModel() -> LanternModel {
        LanternModel(voice: RealtimeVoiceSession(speaksLocally: false))
    }

    func testVoiceCanMuteReplyAndControlProactiveSettingIndependently() {
        let model = makeModel()
        let original = model.voice.proactiveEnabled
        defer { model.voice.proactiveEnabled = original }
        _ = model.performVoiceCommand(.setSpokenOutput(false))
        XCTAssertFalse(model.voice.spokenOutputEnabled)
        _ = model.performVoiceCommand(.setProactiveUpdates(false))
        XCTAssertFalse(model.voice.proactiveEnabled)
        _ = model.performVoiceCommand(.setSpokenOutput(true))
        XCTAssertTrue(model.voice.spokenOutputEnabled)
        XCTAssertFalse(model.voice.proactiveEnabled)
    }

    func testPanelsAndDrawerCanBeControlledWithoutTouch() {
        let model = makeModel()
        for panel in ["settings", "connection", "assistant"] {
            _ = model.performVoiceCommand(.openPanel(panel))
            XCTAssertEqual(model.voicePanel?.rawValue, panel)
        }
        _ = model.performVoiceCommand(.closePanel)
        XCTAssertEqual(model.voicePanel, .closed)
        for expanded in [true, false] {
            _ = model.performVoiceCommand(.setControlsExpanded(expanded))
            XCTAssertEqual(model.voiceControlsExpanded, expanded)
            XCTAssertEqual(model.voicePanel, .closed)
        }
        XCTAssertNotNil(model.performVoiceCommand(.openPanel("invalid"))["error"])
    }

    func testSimulationAndStopKeepSyntheticMovementSeparate() {
        let model = makeModel()
        defer { model.stop() }
        let result = model.performVoiceCommand(.startSimulation)
        XCTAssertEqual(result["simulation"] as? Bool, true)
        XCTAssertEqual(model.mode, .simulation)
        _ = model.performVoiceCommand(.stop)
        XCTAssertEqual(model.mode, .stopped)
        XCTAssertTrue(model.packet.bands.allSatisfy { $0 == 0 })
    }

    func testSavedPlaceNeverBecomesALiveVoiceObservation() {
        let model = makeModel()
        defer { model.stop() }
        model.startSimulation(memory: true)
        model.placeName = "Desk"
        model.remember()
        model.simulateMove(metres: 1)
        model.recall()
        let snapshot = model.voiceSnapshot()
        XCTAssertEqual(snapshot["simulation"] as? Bool, true)
        XCTAssertEqual(snapshot["scene_observation"] as? Bool, false)
        XCTAssertEqual(snapshot["spoken_observation"] as? String, "No current target")
        _ = model.performVoiceCommand(.stop)
        XCTAssertTrue(model.spatialMemory.bookmarks.isEmpty)
    }

    func testHeightDoesNotCalibrateAndUnknownTeammateCannotBeInvited() {
        let model = makeModel()
        _ = model.performVoiceCommand(.setCameraHeight(1.45))
        XCTAssertEqual(model.cameraHeight, 1.45)
        XCTAssertFalse(model.calibrated)
        XCTAssertNotNil(model.performVoiceCommand(.setCameraHeight(.nan))["error"])
        XCTAssertEqual(model.cameraHeight, 1.45)
        XCTAssertNotNil(model.performVoiceCommand(.findTeammate("unknown"))["error"])
        XCTAssertFalse(model.peer.running)
        _ = model.performVoiceCommand(.stopFindingTeammate)
        XCTAssertFalse(model.peer.running)
    }
}
