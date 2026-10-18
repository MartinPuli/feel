import XCTest
import FeelCore
@testable import Lantern

/// Uses synthetic poses and scripted network/audio adapters. No camera, microphone,
/// BLE device or paid service is started by these model-level integration checks.
@MainActor
final class VersionFeatureIntegrationTests: XCTestCase {
    private func fixture() -> (LanternModel, StubChatGateway, ScriptedVoiceTransport) {
        let (voice, transport) = VoiceTestDoubles.activeSession()
        let gateway = StubChatGateway(), store = MemoryChalkStore()
        store.stored = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost,
                                         routerApiKey: String(repeating: "k", count: 16), environmentId: "test", model: "test")
        let model = LanternModel(voice: voice, chalkStore: store, gatewayFactory: { _ in gateway }, localFinder: StubLocalFinder())
        voice.setSpokenOutput(false)
        return (model, gateway, transport)
    }

    private func observe(_ model: LanternModel, z: Double = 0, world: Int = 1, age: Double = 0) {
        model.places.observe(pose: CameraPose(position: Vector3(0, 1.2, z), right: Vector3(1, 0, 0),
                                             up: Vector3(0, 1, 0), back: Vector3(0, 0, 1)),
                             worldEpoch: world, timestamp: ProcessInfo.processInfo.systemUptime - age, tracking: true)
    }
    private func rememberAndRecall(_ model: LanternModel) throws -> String {
        observe(model, z: -2)
        XCTAssertNil(model.performLocalCommand("remember Entrance")["error"])
        let id = try XCTUnwrap(model.places.memory.bookmarks.first?.id)
        observe(model)
        XCTAssertNil(model.performLocalCommand("recall Entrance")["error"])
        XCTAssertEqual(model.places.memory.activeID, id)
        return id
    }

    func testMutedLocalRememberRecallAndStopDoNotUseCloudOrUnmute() throws {
        let (model, gateway, transport) = fixture()
        defer { model.stop(stopVoice: true) }
        let messages = transport.sent.count
        _ = try rememberAndRecall(model)
        XCTAssertFalse(model.voice.spokenOutputEnabled)
        XCTAssertTrue(model.voice.isActive, "Muted online listening is not disabled by a typed local command")
        XCTAssertNil(model.performLocalCommand("stop")["error"])
        XCTAssertEqual(model.mode, .stopped)
        XCTAssertFalse(model.places.active)
        XCTAssertTrue(model.places.memory.bookmarks.isEmpty)
        XCTAssertTrue(model.packet.bands.allSatisfy { $0 == 0 })
        XCTAssertEqual(model.packet.highlight, 255)
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertEqual(transport.sent.count, messages, "Local commands must not become cloud conversation messages")
        XCTAssertFalse(model.voice.spokenOutputEnabled)
    }

    func testLocalMuteAndUnmuteChangeOutputWithoutReopeningTransport() {
        let (model, gateway, transport) = fixture()
        defer { model.stop(stopVoice: true) }
        let messages = transport.sent.count
        XCTAssertNil(model.performLocalCommand("unmute")["error"])
        XCTAssertTrue(model.voice.spokenOutputEnabled)
        XCTAssertTrue(model.voice.isActive)
        XCTAssertNil(model.performLocalCommand("please be quiet")["error"])
        XCTAssertFalse(model.voice.spokenOutputEnabled)
        XCTAssertTrue(model.voice.isActive)
        XCTAssertEqual(gateway.calls, 0)
        XCTAssertEqual(transport.sent.count, messages)
    }

    func testRecallingPlaceCancelsLatePhotoAnswerAndItsRoute() throws {
        let (model, gateway, _) = fixture()
        defer { model.stop(stopVoice: true) }
        _ = try rememberAndRecall(model)
        var photograph: ((FrameSnapshot?) -> Void)?
        model.snapshotProvider = { photograph = $0 }
        model.beginWhereIs("desk")
        XCTAssertFalse(model.places.active, "A new photo request supersedes remembered-place guidance")
        photograph?(makeSnapshot())
        XCTAssertEqual(gateway.calls, 1)
        observe(model)
        XCTAssertNil(model.performLocalCommand("recall Entrance")["error"])
        gateway.reply(0, .success(#"{"found":true,"label":"desk","box":[0.4,0.4,0.6,0.6],"confidence":0.9}"#))
        XCTAssertTrue(model.places.active)
        XCTAssertNil(model.heldTarget, "The cancelled photo answer cannot become a competing target")
        XCTAssertFalse(model.routeGoalActive)
    }

    func testDirectFinderSelectionReleasesMemoryPacketOwnership() throws {
        let (model, gateway, _) = fixture()
        defer { model.stop(stopVoice: true) }
        _ = try rememberAndRecall(model)
        model.finder = .door // The settings picker writes this property without a voice command.
        XCTAssertFalse(model.places.active)
        XCTAssertNil(model.places.encode(sequence: 8, distances: Array(repeating: nil, count: 7),
                                        calibrated: true, at: ProcessInfo.processInfo.systemUptime))
        XCTAssertEqual(model.finder, .door)
        XCTAssertEqual(gateway.calls, 0)
    }

    func testTrackingInvalidationNeutralizesAndBlocksNewMemoryActions() throws {
        let (model, gateway, _) = fixture()
        defer { model.stop(stopVoice: true) }
        _ = try rememberAndRecall(model)
        model.perception.onInvalidated?(0)
        XCTAssertNotNil(model.performLocalCommand("remember Stale")["error"])
        XCTAssertNotNil(model.performLocalCommand("recall Entrance")["error"])
        let output = try XCTUnwrap(model.places.encode(sequence: 9, distances: Array(repeating: 2, count: 7),
                                                     calibrated: true, at: ProcessInfo.processInfo.systemUptime))
        XCTAssertEqual(output.packet, .neutral(sequence: 9))
        XCTAssertEqual(output.state, .trackingLost)
        XCTAssertEqual(model.places.memory.bookmarks.count, 1, "Temporary loss preserves names, never valid guidance")
        XCTAssertEqual(gateway.calls, 0)
    }

    func testNewWorldAndStopCannotReuseOldPlaceIdsOrReturnPoint() throws {
        let (model, gateway, _) = fixture()
        defer { model.stop(stopVoice: true) }
        let oldID = try rememberAndRecall(model)
        observe(model)
        XCTAssertNil(model.performVoiceCommand(.setReturnPoint)["error"])
        observe(model, world: 2)
        XCTAssertNotNil(model.performVoiceCommand(.recallPlace(oldID))["error"])
        XCTAssertNotNil(model.performLocalCommand("return")["error"])
        XCTAssertFalse(model.places.active)
        XCTAssertTrue(model.places.memory.bookmarks.isEmpty)
        XCTAssertNil(model.performLocalCommand("remember New room")["error"])
        model.stop()
        XCTAssertNil(model.places.memory.session)
        XCTAssertNotNil(model.performLocalCommand("remember After stop")["error"])
        XCTAssertTrue(model.packet.bands.allSatisfy { $0 == 0 })
        XCTAssertEqual(gateway.calls, 0)
    }

    func testCaptureOwnershipCallbackPausesOnlineVoiceWithoutStartingAnyInput() {
        let (model, gateway, _) = fixture()
        defer { model.stop(stopVoice: true) }
        XCTAssertTrue(model.voice.isActive)
        model.localVoice.onCaptureWillStart?() // Exercise coordinator wiring without requesting microphone permission.
        XCTAssertFalse(model.voice.isActive)
        XCTAssertTrue(model.voice.isPausedByUser)
        XCTAssertFalse(model.localVoice.isListening)
        XCTAssertFalse(model.voice.spokenOutputEnabled)
        XCTAssertEqual(gateway.calls, 0)
    }
    func testVoiceMemorySimulationMovesRecallsAndNeutralizesOnTrackingLoss() throws {
        let (model, gateway, _) = fixture()
        defer { model.stop(stopVoice: true) }
        XCTAssertNotNil(model.performVoiceCommand(.moveMemorySimulation(1))["error"])
        XCTAssertNil(model.performVoiceCommand(.startMemorySimulation)["error"])
        XCTAssertNil(model.performVoiceCommand(.rememberPlace("Entrance"))["error"])
        XCTAssertNil(model.performVoiceCommand(.moveMemorySimulation(-2))["error"])
        let id = try XCTUnwrap(model.places.memory.bookmarks.first?.id)
        XCTAssertNil(model.performVoiceCommand(.recallPlace(id))["error"])
        model.turnMemorySimulation(0)
        XCTAssertTrue(model.places.active)
        XCTAssertEqual(model.packet.bands[0], 0)
        XCTAssertNotEqual(model.packet.highlight, 255)
        XCTAssertNil(model.performVoiceCommand(.setMemorySimulationTracking(false))["error"])
        XCTAssertTrue(model.packet.bands.allSatisfy { $0 == 0 })
        XCTAssertEqual(model.packet.highlight, 255)
        XCTAssertNotNil(model.performVoiceCommand(.rememberPlace("Lost"))["error"])
        XCTAssertNil(model.performVoiceCommand(.setMemorySimulationTracking(true))["error"])
        XCTAssertTrue(model.simulatedMemoryTracking)
        XCTAssertNil(model.performVoiceCommand(.turnMemorySimulation(90))["error"])
        XCTAssertNotNil(model.performVoiceCommand(.moveMemorySimulation(.infinity))["error"])
        XCTAssertEqual(gateway.calls, 0)
    }

    func testSimulationToolsRejectBooleansOutOfRangeAndExtraFields() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "move_memory_simulation", arguments: #"{"meters":-2}"#), .moveMemorySimulation(-2))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "move_memory_simulation", arguments: #"{"meters":true}"#))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "move_memory_simulation", arguments: #"{"meters":6}"#))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "turn_memory_simulation", arguments: #"{"degrees":361}"#))
        XCTAssertThrowsError(try VoiceCommand.decode(name: "export_journeys", arguments: #"{"upload":true}"#))
    }

}
