import XCTest
@testable import Lantern

final class VoiceActionIntegrationTests: XCTestCase {
    private func makeModel(diagnosticsAllowed: Bool = false) -> LanternModel {
        LanternModel(voice: RealtimeVoiceSession(speaksLocally: false, diagnosticsAllowed: diagnosticsAllowed))
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
        let model = makeModel(diagnosticsAllowed: true)
        defer { model.stop() }
        let result = model.performVoiceCommand(.startSimulation)
        XCTAssertEqual(result["simulation"] as? Bool, true)
        XCTAssertEqual(model.mode, .simulation)
        _ = model.performVoiceCommand(.stop)
        XCTAssertEqual(model.mode, .stopped)
        XCTAssertTrue(model.packet.bands.allSatisfy { $0 == 0 })
    }

    func testNormalLaunchRejectsSyntheticCommandsWithoutChangingState() {
        let model = makeModel()
        defer { model.stop() }
        let status = model.status
        let commands: [VoiceCommand] = [.startSimulation, .startMemorySimulation, .moveMemorySimulation(1),
                                        .turnMemorySimulation(90), .setMemorySimulationTracking(false), .simulateDirectionSign]
        for command in commands {
            XCTAssertEqual(model.performVoiceCommand(command)["error"] as? String, VoiceCommand.diagnosticsUnavailable)
            XCTAssertEqual(model.mode, .stopped)
            XCTAssertFalse(model.memorySimulation)
            XCTAssertEqual(model.status, status)
        }
        XCTAssertNotNil(model.performLocalCommand("start simulation")["error"])
        XCTAssertEqual(model.mode, .stopped)
    }

    func testDirectSimulationFixtureDoesNotEnableSyntheticVoiceCommands() {
        let model = makeModel()
        defer { model.stop() }
        model.startMemorySimulation()
        XCTAssertEqual(model.mode, .simulation, "Direct simulation remains available to the deterministic test harness")
        XCTAssertEqual(model.performVoiceCommand(.moveMemorySimulation(1))["error"] as? String, VoiceCommand.diagnosticsUnavailable)
        XCTAssertEqual(model.performVoiceCommand(.setMemorySimulationTracking(false))["error"] as? String, VoiceCommand.diagnosticsUnavailable)
        XCTAssertTrue(model.simulatedMemoryTracking)
        XCTAssertEqual(model.performVoiceCommand(.startSimulation)["error"] as? String, VoiceCommand.diagnosticsUnavailable)
        XCTAssertTrue(model.memorySimulation)
    }

    func testVoiceSessionExposesSyntheticToolsOnlyWithDiagnosticAllowance() throws {
        let diagnosticNames: Set<String> = ["start_simulation", "start_memory_simulation", "move_memory_simulation",
                                             "turn_memory_simulation", "set_memory_simulation_tracking", "simulate_direction_sign"]
        var normalNames = Set<String>()
        for allowed in [false, true] {
            let (voice, transport) = VoiceTestDoubles.activeSession(diagnosticsAllowed: allowed)
            defer { voice.disconnect() }
            let update = try XCTUnwrap(transport.sent.first { $0["type"] as? String == "session.update" })
            let session = try XCTUnwrap(update["session"] as? [String: Any])
            let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
            let names = Set(tools.compactMap { $0["name"] as? String })
            XCTAssertTrue(names.contains("start_camera"))
            XCTAssertTrue(names.contains("stop"))
            if allowed {
                XCTAssertEqual(names.subtracting(normalNames), diagnosticNames)
            } else {
                XCTAssertTrue(names.isDisjoint(with: diagnosticNames))
                normalNames = names
            }
        }
    }

    func testVoiceTransportRejectsUnadvertisedSimulationStartsBeforeDispatch() throws {
        for allowed in [false, true] {
            let (voice, transport) = VoiceTestDoubles.activeSession(diagnosticsAllowed: allowed)
            defer { voice.disconnect() }
            var dispatched: [VoiceCommand] = []
            voice.onCommand = { command in dispatched.append(command); return ["status": "Test command received"] }
            transport.emit(["type": "response.created", "response": ["id": "request"]])
            for name in ["start_simulation", "start_memory_simulation"] {
                transport.emit(["type": "response.function_call_arguments.done", "response_id": "request",
                                "call_id": name, "name": name, "arguments": "{}"])
                let item = try XCTUnwrap(transport.sent.last?["item"] as? [String: Any])
                XCTAssertEqual(item["call_id"] as? String, name)
                let output = try XCTUnwrap(item["output"] as? String)
                let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
                if allowed { XCTAssertNil(result["error"]) }
                else { XCTAssertEqual(result["error"] as? String, VoiceCommand.diagnosticsUnavailable) }
            }
            XCTAssertEqual(dispatched, allowed ? [.startSimulation, .startMemorySimulation] : [])
        }
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
