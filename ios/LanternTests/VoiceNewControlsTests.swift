import XCTest
import FeelCore
@testable import Lantern

final class VoiceNewControlsTests: XCTestCase {
    private func makeModel(voice: RealtimeVoiceSession? = nil) -> (LanternModel, StubChatGateway) {
        let gateway = StubChatGateway()
        let store = MemoryChalkStore()
        store.stored = ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost,
                                         routerApiKey: String(repeating: "k", count: 16),
                                         environmentId: "test", model: "test")
        let model = LanternModel(voice: voice ?? RealtimeVoiceSession(configuration: nil, speaksLocally: false),
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

    func testDescriptionReplacementDropsDelayedPhotoAndAnswer() throws {
        let (model, gateway) = makeModel()
        defer { model.stop() }
        let configuration = try XCTUnwrap(model.chalkConfiguration)
        var photos: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { photos.append($0) }

        model.startDescribeAhead(configuration)
        model.startDescribeAhead(configuration)
        XCTAssertTrue(model.descriptionPending)
        photos[0](makeSnapshot())
        XCTAssertEqual(gateway.calls, 0, "A replaced capture must not send a photo")
        photos[1](makeSnapshot())
        XCTAssertEqual(gateway.calls, 1)

        model.startDescribeAhead(configuration)
        photos[2](makeSnapshot())
        gateway.reply(1, .success("A chair is ahead."))
        drainMainQueue()
        XCTAssertEqual(model.describeNotice, "A chair is ahead.")
        XCTAssertFalse(model.descriptionPending)
        gateway.reply(0, .success("An old door is ahead."))
        drainMainQueue()
        XCTAssertEqual(model.describeNotice, "A chair is ahead.", "An old completion cannot replace the current result")
    }

    func testStopDropsDescriptionCaptureAndQueuedCompletion() throws {
        let (model, gateway) = makeModel()
        let configuration = try XCTUnwrap(model.chalkConfiguration)
        var photos: [(FrameSnapshot?) -> Void] = []
        model.snapshotProvider = { photos.append($0) }

        model.startDescribeAhead(configuration)
        XCTAssertTrue(model.descriptionPending)
        model.stop()
        XCTAssertFalse(model.descriptionPending)
        photos[0](makeSnapshot())
        XCTAssertEqual(gateway.calls, 0)

        model.startDescribeAhead(configuration)
        photos[1](makeSnapshot())
        gateway.reply(0, .success("An old chair is ahead."))
        model.stop() // The network callback is already queued on main, so cancelling transport alone is insufficient.
        drainMainQueue()
        XCTAssertNil(model.describeNotice)
    }

    func testStopClearsDescriptionAndPreventsQueuedSpeechRetry() throws {
        let (voice, transport) = descriptionVoice()
        let (model, gateway) = makeModel(voice: voice)
        defer { model.stop(stopVoice: true) }
        voice.setSpokenOutput(false)
        model.snapshotProvider = { $0(makeSnapshot()) }
        model.startDescribeAhead(try XCTUnwrap(model.chalkConfiguration))
        gateway.reply(0, .success("An old chair is ahead."))
        drainMainQueue()
        XCTAssertEqual(model.describeNotice, "An old chair is ahead.")

        model.stop()
        XCTAssertNil(model.describeNotice)
        voice.setSpokenOutput(true)
        waitThroughDescriptionRetry()
        XCTAssertNil(model.describeNotice, "A queued retry must not republish a stopped scene")
        XCTAssertFalse(transport.json.contains("An old chair is ahead."), "A queued retry must not speak after Stop")
    }

    func testReplacementClearsDescriptionAndPreventsQueuedSpeechRetry() throws {
        let (voice, transport) = descriptionVoice()
        let (model, gateway) = makeModel(voice: voice)
        defer { model.stop(stopVoice: true) }
        let configuration = try XCTUnwrap(model.chalkConfiguration)
        voice.setSpokenOutput(false)
        model.snapshotProvider = { $0(makeSnapshot()) }
        model.startDescribeAhead(configuration)
        gateway.reply(0, .success("An old chair is ahead."))
        drainMainQueue()
        XCTAssertNotNil(model.describeNotice)

        model.startDescribeAhead(configuration)
        XCTAssertNil(model.describeNotice)
        voice.setSpokenOutput(true)
        waitThroughDescriptionRetry()
        XCTAssertNil(model.describeNotice)
        XCTAssertFalse(transport.json.contains("An old chair is ahead."))

        gateway.reply(1, .success("A new door is ahead."))
        drainMainQueue()
        XCTAssertEqual(model.describeNotice, "A new door is ahead.")
        XCTAssertTrue(transport.json.contains("A new door is ahead."), "The replacement still produces speech")
    }

    func testDescriptionInvalidationOnTrackingResetOrConfigurationChange() throws {
        let invalidations: [(LanternModel) throws -> Void] = [
            { $0.perception.onInvalidated?(0) },
            { $0.forgetChalkConfiguration() },
            { try $0.saveChalkConfiguration(ChalkConfiguration(apiHost: ChalkConfiguration.defaultHost,
                                                              routerApiKey: String(repeating: "n", count: 16),
                                                              environmentId: "replacement", model: "replacement")) }
        ]
        for invalidate in invalidations {
            let (model, gateway) = makeModel()
            defer { model.stop() }
            let configuration = try XCTUnwrap(model.chalkConfiguration)
            var photos: [(FrameSnapshot?) -> Void] = []
            model.snapshotProvider = { photos.append($0) }
            model.startDescribeAhead(configuration)
            try invalidate(model)
            XCTAssertFalse(model.descriptionPending)
            photos[0](makeSnapshot())
            XCTAssertEqual(gateway.calls, 0)

            model.startDescribeAhead(configuration)
            photos[1](makeSnapshot())
            try invalidate(model)
            gateway.reply(0, .success("An invalidated scene is ahead."))
            drainMainQueue()
            XCTAssertNil(model.describeNotice)
        }
    }

    func testDescriptionSpeechIsSceneBoundAndRejectsResponseAfterStop() throws {
        let (voice, transport) = descriptionVoice()
        let (model, gateway) = makeModel(voice: voice)
        defer { model.stop(stopVoice: true) }
        model.snapshotProvider = { $0(makeSnapshot()) }
        model.startDescribeAhead(try XCTUnwrap(model.chalkConfiguration))
        gateway.reply(0, .success("A chair is ahead."))
        drainMainQueue()
        XCTAssertTrue(transport.json.contains("A chair is ahead."))
        let response = try XCTUnwrap(transport.sent.last { $0["type"] as? String == "response.create" }?["response"] as? [String: Any])
        let metadata = try XCTUnwrap(response["metadata"] as? [String: Any])
        XCTAssertNotNil(metadata["feel_request_id"])

        model.stop()
        XCTAssertTrue(voice.isActive, "Stop sensing must not silently disconnect the microphone")
        transport.emit(["type": "response.created", "response": ["id": "old-description", "metadata": metadata]])
        XCTAssertTrue(transport.sent.contains { $0["type"] as? String == "response.cancel" && $0["response_id"] as? String == "old-description" },
                      "Scene-bound speech must reject a delayed provider response after Stop")
        XCTAssertNil(model.describeNotice)
        XCTAssertEqual(voice.phase, .listening)
    }

    /// Skip the greeting while muted so description speech can be inspected without a five-second rate-limit wait.
    private func descriptionVoice() -> (RealtimeVoiceSession, ScriptedVoiceTransport) {
        let token = ScriptedVoiceToken(), transport = ScriptedVoiceTransport()
        let configuration = VoiceConfiguration(endpoint: "https://voice.example/session", accessToken: String(repeating: "a", count: 32))
        let voice = RealtimeVoiceSession(tokenClient: token, audio: SilentVoiceAudio(), transportFactory: { transport },
                                         configuration: configuration, speaksLocally: false, requestPermission: { $0(true) })
        voice.setSpokenOutput(false)
        voice.start(); token.complete(.success("ephemeral"))
        transport.emit(["type": "session.created"]); transport.emit(["type": "session.updated"])
        voice.setSpokenOutput(true)
        XCTAssertEqual(voice.phase, .listening)
        return (voice, transport)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Queued description completion finished")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    private func waitThroughDescriptionRetry() {
        let elapsed = expectation(description: "Scheduled description retry passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 2)
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
        let (voice, _) = VoiceTestDoubles.activeSession(diagnosticsAllowed: true)
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
