import XCTest
import AVFoundation
import UIKit
@testable import Lantern

final class GrokVoiceTests: XCTestCase {
    private let config = VoiceConfiguration(endpoint: "https://voice.example/session", accessToken: String(repeating: "a", count: 32))

    func testCommandAllowlistRejectsMalformedAndUnsafeArguments() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "find_target", arguments: "{\"target\":\"door\"}"), .find(.door))
        XCTAssertEqual(try VoiceCommand.decode(name: "calibrate_floor", arguments: "{\"measured_height_meters\":1.25}"), .calibrate(1.25))
        for (name, args) in [("flash_firmware", "{}"), ("stop", "{\"extra\":true}"),
                             ("calibrate_floor", "{\"measured_height_meters\":true}"),
                             ("calibrate_floor", "{\"measured_height_meters\":5}"),
                             ("calibrate_floor", "{}"), ("find_target", "{\"target\":\"stairs\"}"),
                             ("connect_puck", "{\"device_id\":\"not-a-uuid\"}"), ("stop", "[]")] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: name, arguments: args))
        }
    }

    func testConfigurationRequiresHTTPSAndNoURLCredentialsOrQuery() {
        XCTAssertTrue(config.isValid)
        for url in ["http://voice.example/session", "https://user:password@voice.example/session",
                    "https://voice.example/session?key=secret", "https://voice.example/session#token", "invalid"] {
            XCTAssertFalse(VoiceConfiguration(endpoint: url, accessToken: config.accessToken).isValid)
        }
        XCTAssertFalse(VoiceConfiguration(endpoint: config.endpoint, accessToken: "short").isValid)
    }

    #if DEBUG
    func testDeveloperProvisioningRequiresOptInAndPersistsValidatedServiceCredential() throws {
        var environment = ["FEEL_VOICE_ENDPOINT": config.endpoint, "FEEL_VOICE_ACCESS_TOKEN": config.accessToken]
        var saved: VoiceConfiguration?
        XCTAssertNil(try VoiceConfigurationStore.provision(environment: environment, arguments: [], save: { saved = $0 }))
        XCTAssertNil(saved)
        environment["FEEL_PROVISION_VOICE"] = "1"
        XCTAssertEqual(try VoiceConfigurationStore.provision(environment: environment, arguments: [], save: { saved = $0 }), config)
        XCTAssertEqual(saved, config)
        saved = nil
        XCTAssertNil(try VoiceConfigurationStore.provision(environment: environment, arguments: ["--uitesting"], save: { saved = $0 }))
        XCTAssertNil(saved)
        for invalid in ["short", "grok_" + String(repeating: "x", count: 40), "xai-" + String(repeating: "x", count: 40),
                        String(repeating: "x", count: 32) + "\u{01}", String(repeating: "x", count: 4097)] {
            environment["FEEL_VOICE_ACCESS_TOKEN"] = invalid
            XCTAssertThrowsError(try VoiceConfigurationStore.provision(environment: environment, arguments: [], save: { saved = $0 }))
            XCTAssertNil(saved)
        }
        environment["FEEL_VOICE_ACCESS_TOKEN"] = config.accessToken
        environment["FEEL_VOICE_ENDPOINT"] = "http://voice.example/session"
        XCTAssertThrowsError(try VoiceConfigurationStore.provision(environment: environment, arguments: [], save: { saved = $0 }))
        XCTAssertNil(saved)
        environment["FEEL_VOICE_ENDPOINT"] = config.endpoint
        XCTAssertThrowsError(try VoiceConfigurationStore.provision(environment: environment, arguments: [], save: { _ in throw VoiceConfigurationStore.StoreError.unavailable }))
    }
    #endif

    func testStopCancelsPermissionAndTokenCallbacks() {
        var permission: ((Bool) -> Void)?
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio) { permission = $0 }
        voice.start(); voice.disconnect(); permission?(true)
        XCTAssertEqual(token.fetchCount, 0)
        voice.start(); permission?(true)
        XCTAssertEqual(token.fetchCount, 1)
        voice.disconnect(); token.complete(.success("expired-session"))
        XCTAssertEqual(transport.openCount, 0)
        XCTAssertEqual(audio.startCount, 0)
        XCTAssertEqual(voice.phase, .idle)
    }

    func testPermissionDeniedDoesNotConnectOrCapture() {
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio) { $0(false) }
        voice.start()
        XCTAssertEqual(token.fetchCount, 0)
        XCTAssertEqual(audio.startCount, 0)
        XCTAssertTrue(voice.needsMicrophoneSettings)
        XCTAssertEqual(voice.phase, .failed)
    }

    func testAudioStartsOnlyAfterConfigurationAcknowledgement() {
        let (voice, transport, audio) = connected()
        XCTAssertEqual(audio.startCount, 0)
        transport.emit(["type": "session.created"])
        XCTAssertEqual(audio.startCount, 0)
        XCTAssertEqual(transport.sent.last?["type"] as? String, "session.update")
        transport.emit(["type": "session.updated"])
        XCTAssertEqual(audio.startCount, 1)
        transport.emit(["type": "session.updated"])
        XCTAssertEqual(audio.startCount, 1)
        audio.onInput?(Data([1, 0]))
        XCTAssertTrue(transport.sent.contains { $0["type"] as? String == "input_audio_buffer.append" })
        voice.disconnect()
    }

    func testInterruptDiscardsLateAudioAndToolsAndRepairsHistory() {
        let (voice, transport, audio) = ready()
        var actions: [VoiceCommand] = []
        voice.onCommand = { actions.append($0); return ["ok": true] }
        transport.emit(["type": "response.created", "response": ["id": "old"]])
        transport.emit(audioEvent("old"))
        XCTAssertEqual(audio.playCount, 1)
        audio.playedMilliseconds = 120
        transport.emit(["type": "input_audio_buffer.speech_started"])
        XCTAssertFalse(audio.pendingPlayback)
        XCTAssertTrue(transport.sent.contains { $0["type"] as? String == "conversation.item.truncate" && $0["audio_end_ms"] as? Int == 120 })
        transport.emit(audioEvent("old"))
        transport.emit(toolEvent("old", id: "late", name: "start_camera"))
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(audio.playCount, 1)
        XCTAssertFalse(voice.announce("An unsolicited update", automatic: false))
        voice.disconnect()
    }

    func testSpeechBeforeResponseIDRejectsDelayedAudioAndActions() {
        let (voice, transport, audio) = ready()
        var actions = 0
        voice.onCommand = { _ in actions += 1; return [:] }
        transport.emit(["type": "input_audio_buffer.speech_started"])
        transport.emit(["type": "response.created", "response": ["id": "late-greeting"]])
        transport.emit(audioEvent("late-greeting"))
        transport.emit(toolEvent("late-greeting", id: "late-action", name: "start_camera"))
        XCTAssertEqual(audio.playCount, 0)
        XCTAssertEqual(actions, 0)
        transport.emit(["type": "input_audio_buffer.speech_stopped"])
        transport.emit(["type": "response.created", "response": ["id": "fresh-answer"]])
        transport.emit(audioEvent("fresh-answer"))
        XCTAssertEqual(audio.playCount, 1)
        voice.disconnect()
    }

    func testSceneInvalidationDiscardsPendingAndPlayingObservation() {
        for invalidateBeforeResponse in [true, false] {
            let (voice, transport, audio) = ready()
            // A scene-grounded tool result owns the following response.
            voice.onCommand = { _ in ["target": "Door, 1.2 m", "scene_observation": true] }
            transport.emit(["type": "response.created", "response": ["id": "status"]])
            transport.emit(toolEvent("status", id: "status-call", name: "get_status"))
            transport.emit(["type": "response.done", "response": ["id": "status"]])
            if invalidateBeforeResponse { voice.invalidateSceneSpeech() }
            transport.emit(["type": "response.created", "response": ["id": "observation"]])
            transport.emit(audioEvent("observation"))
            if !invalidateBeforeResponse { voice.invalidateSceneSpeech() }
            let playedBeforeLatePacket = audio.playCount
            transport.emit(audioEvent("observation"))
            XCTAssertEqual(audio.playCount, playedBeforeLatePacket)
            XCTAssertFalse(audio.pendingPlayback)
            XCTAssertEqual(playedBeforeLatePacket, invalidateBeforeResponse ? 0 : 1)
            XCTAssertTrue(voice.isActive)
            voice.disconnect()
        }
    }

    func testQueueFailureDuringSceneCancellationRemainsFailed() {
        let (voice, transport, audio) = ready()
        voice.onCommand = { _ in ["target": "Door, 1.2 m", "scene_observation": true] }
        transport.emit(["type": "response.created", "response": ["id": "status"]])
        transport.emit(toolEvent("status", id: "status-call", name: "get_status"))
        transport.emit(["type": "response.done", "response": ["id": "status"]])
        transport.emit(["type": "response.created", "response": ["id": "observation"]])
        transport.holdSends = true
        for _ in 0..<9 { audio.onInput?(Data([0, 0])) }
        XCTAssertTrue(voice.isActive)
        voice.invalidateSceneSpeech()
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertFalse(voice.isActive)
        XCTAssertFalse(audio.running)
    }

    func testStatusWithoutObservationSurvivesNextModelTick() {
        let (voice, transport, audio) = ready()
        let model = LanternModel(voice: voice)
        transport.emit(["type": "response.created", "response": ["id": "status"]])
        transport.emit(toolEvent("status", id: "status-call", name: "get_status"))
        transport.emit(["type": "response.done", "response": ["id": "status"]])
        _ = model.voiceSnapshot()
        transport.emit(["type": "response.created", "response": ["id": "recovery"]])
        transport.emit(audioEvent("recovery"))
        XCTAssertEqual(audio.playCount, 1)
        XCTAssertTrue(audio.pendingPlayback)
        model.stop()
    }

    func testSceneExpiryStopsPlaybackWithoutAnotherCameraFrame() {
        let (voice, transport, audio) = ready()
        voice.onCommand = { _ in ["target": "Door, 1.2 m", "scene_observation": true] }
        transport.emit(["type": "response.created", "response": ["id": "status"]])
        transport.emit(toolEvent("status", id: "status-call", name: "get_status"))
        transport.emit(["type": "response.done", "response": ["id": "status"]])
        transport.emit(["type": "response.created", "response": ["id": "observation"]])
        transport.emit(audioEvent("observation"))
        let expired = expectation(description: "Observation expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { expired.fulfill() }
        wait(for: [expired], timeout: 4)
        XCTAssertFalse(audio.pendingPlayback)
        transport.emit(audioEvent("observation"))
        XCTAssertEqual(audio.playCount, 1)
        voice.disconnect()
    }

    func testToolDeduplicationAndContinuationWaitsForPlayedAudio() {
        let (voice, transport, audio) = ready()
        var actions = 0
        voice.onCommand = { _ in actions += 1; return ["status": "actual result"] }
        transport.emit(["type": "response.created", "response": ["id": "response-1"]])
        transport.emit(audioEvent("response-1"))
        let event = toolEvent("response-1", id: "call-1", name: "get_status")
        transport.emit(event); transport.emit(event)
        XCTAssertEqual(actions, 1)
        transport.emit(["type": "response.done", "response": ["id": "response-1"]])
        XCTAssertEqual(transport.sent.filter { $0["type"] as? String == "response.create" }.count, 0)
        audio.drain()
        XCTAssertEqual(transport.sent.filter { $0["type"] as? String == "response.create" }.count, 1)
        audio.drain()
        XCTAssertEqual(transport.sent.filter { $0["type"] as? String == "response.create" }.count, 1)
        voice.disconnect()
    }

    func testRemoteFailureAndOldCallbacksCannotRestartMicrophone() {
        let (voice, transport, audio) = ready()
        let callback = transport.onEvent
        transport.onFailure?()
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertFalse(audio.running)
        callback?(["type": "session.updated"])
        XCTAssertFalse(audio.running)
        XCTAssertEqual(audio.startCount, 1)
    }

    func testHeadphoneRemovalStopsSessionWithoutAutomaticSpeakerResume() {
        let (voice, _, audio) = ready()
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertFalse(audio.running)
        XCTAssertTrue(voice.caption.contains("paused"))
    }

    func testBackgroundEndsVoiceAndRejectsCommands() {
        let (voice, transport, audio) = ready()
        var actions = 0
        voice.onCommand = { _ in actions += 1; return [:] }
        let callback = transport.onEvent
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        callback?(toolEvent("response", id: "late", name: "start_camera"))
        XCTAssertEqual(actions, 0)
        XCTAssertFalse(audio.running)
        XCTAssertEqual(voice.phase, .idle)
    }

    func testStopCommandStopsCameraButKeepsAssistantListening() {
        let (voice, transport, audio) = ready()
        let model = LanternModel(voice: voice)
        model.startSimulation()
        transport.emit(["type": "response.created", "response": ["id": "stop-response"]])
        transport.emit(toolEvent("stop-response", id: "stop-call", name: "stop"))
        XCTAssertEqual(model.mode, .stopped)
        XCTAssertTrue(model.packet.bands.allSatisfy { $0 == 0 })
        XCTAssertTrue(audio.running)
        XCTAssertTrue(voice.isActive)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        voice.disconnect()
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testPauseAssistantCommandStopsMicrophone() {
        let (voice, transport, audio) = ready()
        let model = LanternModel(voice: voice)
        transport.emit(["type": "response.created", "response": ["id": "pause"]])
        transport.emit(toolEvent("pause", id: "pause-call", name: "pause_assistant"))
        XCTAssertFalse(audio.running)
        XCTAssertTrue(voice.isPausedByUser)
        voice.enterForeground()
        XCTAssertFalse(voice.isActive)
        model.stop()
    }

    func testAutomaticAssistantStartsOnOpenAndResumesAfterBackground() {
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio)
        voice.enterForeground()
        XCTAssertEqual(token.fetchCount, 1)
        token.complete(.success("test-token"))
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        XCTAssertTrue(audio.running)
        voice.enterBackground()
        XCTAssertFalse(audio.running)
        voice.enterForeground()
        XCTAssertEqual(token.fetchCount, 2)
        voice.pauseAssistant()
        voice.enterBackground(); voice.enterForeground()
        XCTAssertEqual(token.fetchCount, 2)
        voice.resumeAssistant()
        XCTAssertEqual(token.fetchCount, 3)
        voice.disconnect()
    }

    func testAutomaticAssistantWaitsForHeadphoneReconnection() {
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio)
        voice.enterForeground(); token.complete(.success("test-token"))
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        XCTAssertFalse(audio.running)
        voice.enterForeground()
        XCTAssertEqual(token.fetchCount, 1)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        XCTAssertEqual(token.fetchCount, 2)
        voice.disconnect()
    }

    func testSimulationSnapshotNeverReportsLiveObservation() {
        let model = LanternModel()
        model.startSimulation()
        let snapshot = model.voiceSnapshot()
        XCTAssertEqual(snapshot["simulation"] as? Bool, true)
        XCTAssertEqual(snapshot["target"] as? String, "No current live target observation")
        XCTAssertNotNil(model.performVoiceCommand(.find(.door))["error"])
        XCTAssertNotNil(model.performVoiceCommand(.connectPuck(UUID()))["error"])
        model.stop()
    }

    private func makeVoice(_ token: FakeVoiceToken, _ transport: FakeVoiceTransport, _ audio: FakeVoiceAudio,
                           permission: @escaping (@escaping (Bool) -> Void) -> Void = { $0(true) }) -> GrokVoiceSession {
        GrokVoiceSession(tokenClient: token, audio: audio, transportFactory: { transport },
                         configuration: config, speaksLocally: false, requestPermission: permission)
    }
    private func connected() -> (GrokVoiceSession, FakeVoiceTransport, FakeVoiceAudio) {
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio)
        voice.start(); token.complete(.success("ephemeral-test-token"))
        return (voice, transport, audio)
    }
    private func ready() -> (GrokVoiceSession, FakeVoiceTransport, FakeVoiceAudio) {
        let (voice, transport, audio) = connected()
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        return (voice, transport, audio)
    }
    private func audioEvent(_ response: String) -> [String: Any] {
        ["type": "response.output_audio.delta", "response_id": response, "item_id": "item-1", "delta": Data([1, 0]).base64EncodedString()]
    }
    private func toolEvent(_ response: String, id: String, name: String) -> [String: Any] {
        ["type": "response.function_call_arguments.done", "response_id": response, "call_id": id, "name": name, "arguments": "{}"]
    }
}

private final class FakeVoiceToken: VoiceTokenFetching {
    var completion: ((Result<String, Error>) -> Void)?
    var fetchCount = 0
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void) { fetchCount += 1; self.completion = completion }
    func complete(_ result: Result<String, Error>) { completion?(result) }
    func cancel() {}
}
private final class FakeVoiceTransport: VoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?
    var openCount = 0
    var sent: [[String: Any]] = []
    var holdSends = false
    func open(token: String) { openCount += 1 }
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) { sent.append(event); if !holdSends { completion(true) } }
    func close() {}
    func emit(_ event: [String: Any]) { onEvent?(event) }
}
private final class FakeVoiceAudio: VoiceAudioIO {
    var running = false
    var pendingPlayback = false
    var playedMilliseconds = 0
    var startCount = 0
    var playCount = 0
    var onInput: ((Data) -> Void)?
    var onDrained: (() -> Void)?
    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws {
        running = true; startCount += 1; self.onInput = onInput; onDrained = onPlaybackDrained
    }
    func play(_ pcm: Data) throws { pendingPlayback = true; playCount += 1 }
    func interruptPlayback() { pendingPlayback = false; playedMilliseconds = 0 }
    func stop() { running = false; interruptPlayback() }
    func drain() { pendingPlayback = false; onDrained?() }
}
