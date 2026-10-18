import XCTest
import AVFoundation
import UIKit
@testable import Lantern

final class RealtimeVoiceTests: XCTestCase {
    func testBuildConfigSeedsTheVoiceServiceOnlyWhenComplete() {
        let token = String(repeating: "a", count: 40)
        let good = VoiceConfigurationStore.configuration(fromInfo: ["FEEL_VOICE_ENDPOINT": "https://feel-v1-voice.vercel.app/session", "FEEL_VOICE_ACCESS_TOKEN": token])
        XCTAssertEqual(good?.endpoint, "https://feel-v1-voice.vercel.app/session")
        XCTAssertNil(VoiceConfigurationStore.configuration(fromInfo: ["FEEL_VOICE_ENDPOINT": "$(FEEL_VOICE_ENDPOINT)", "FEEL_VOICE_ACCESS_TOKEN": "$(FEEL_VOICE_ACCESS_TOKEN)"]), "an unexpanded build setting is not a configuration")
        XCTAssertNil(VoiceConfigurationStore.configuration(fromInfo: ["FEEL_VOICE_ENDPOINT": "https://feel-v1-voice.vercel.app/session"]))
        XCTAssertNil(VoiceConfigurationStore.configuration(fromInfo: ["FEEL_VOICE_ENDPOINT": "http://insecure/session", "FEEL_VOICE_ACCESS_TOKEN": token]))
        XCTAssertNil(VoiceConfigurationStore.configuration(fromInfo: ["FEEL_VOICE_ENDPOINT": "https://feel-v1-voice.vercel.app/session", "FEEL_VOICE_ACCESS_TOKEN": "sk-short"]))
    }

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

    func testExpandedAppCommandsDecodeOnlyTheirDeclaredArguments() throws {
        let valid: [(String, String, VoiceCommand)] = [
            ("set_spoken_output", "{\"enabled\":false}", .setSpokenOutput(false)),
            ("set_spoken_output", "{\"enabled\":true}", .setSpokenOutput(true)),
            ("set_proactive_updates", "{\"enabled\":false}", .setProactiveUpdates(false)),
            ("set_controls_expanded", "{\"expanded\":true}", .setControlsExpanded(true)),
            ("start_simulation", "{}", .startSimulation),
            ("disconnect_puck", "{}", .disconnectPuck),
            ("set_camera_height", "{\"measured_height_meters\":0.6}", .setCameraHeight(0.6)),
            ("set_camera_height", "{\"measured_height_meters\":2.1}", .setCameraHeight(2.1)),
            ("open_panel", "{\"panel\":\"settings\"}", .openPanel("settings")),
            ("open_panel", "{\"panel\":\"connection\"}", .openPanel("connection")),
            ("open_panel", "{\"panel\":\"assistant\"}", .openPanel("assistant")),
            ("close_panel", "{}", .closePanel),
            ("scan_teammates", "{}", .scanTeammates),
            ("list_teammates", "{}", .listTeammates),
            ("find_teammate", "{\"device_id\":\"opaque-peer-7\"}", .findTeammate("opaque-peer-7")),
            ("stop_finding_teammate", "{}", .stopFindingTeammate),
            ("open_system_settings", "{}", .openSystemSettings),
            ("forget_voice_connection", "{\"confirmed\":true}", .forgetVoiceConnection),
        ]
        for (name, arguments, expected) in valid {
            XCTAssertEqual(try VoiceCommand.decode(name: name, arguments: arguments), expected, name)
        }
        let malformed = [
            ("set_spoken_output", "{\"enabled\":1}"),
            ("set_spoken_output", "{\"enabled\":\"false\"}"),
            ("set_spoken_output", "{\"enabled\":null}"),
            ("set_proactive_updates", "{\"enabled\":0}"),
            ("set_controls_expanded", "{\"expanded\":true,\"extra\":1}"),
            ("set_camera_height", "{\"measured_height_meters\":true}"),
            ("set_camera_height", "{\"measured_height_meters\":0.59}"),
            ("set_camera_height", "{\"measured_height_meters\":2.11}"),
            ("set_camera_height", "{\"measured_height_meters\":\"1.2\"}"),
            ("open_panel", "{\"panel\":\"billing\"}"),
            ("open_panel", "{\"panel\":\"settings\",\"extra\":true}"),
            ("find_teammate", "{\"device_id\":\"\"}"),
            ("find_teammate", "{\"device_id\":\"a b\"}"),
            ("find_teammate", "{\"device_id\":\"bad\\npeer\"}"),
            ("find_teammate", "{\"device_id\":7}"),
            ("find_teammate", "{\"device_id\":\"" + String(repeating: "a", count: 129) + "\"}"),
            ("forget_voice_connection", "{\"confirmed\":false}"),
            ("forget_voice_connection", "{\"confirmed\":1}"),
            ("forget_voice_connection", "{}"),
        ]
        for (name, arguments) in malformed {
            XCTAssertThrowsError(try VoiceCommand.decode(name: name, arguments: arguments), name)
        }
        for name in ["start_simulation", "disconnect_puck", "close_panel", "scan_teammates",
                     "list_teammates", "stop_finding_teammate", "open_system_settings"] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: name, arguments: "{\"extra\":true}"), name)
        }
    }

    func testVoiceMuteStopsPlaybackButPreservesCaptureCaptionsToolsAndUnmute() {
        let (voice, transport, audio) = ready()
        var actions: [VoiceCommand] = []
        voice.onCommand = { [weak voice] command in
            actions.append(command)
            if case .setSpokenOutput(let enabled) = command { voice?.setSpokenOutput(enabled) }
            return ["ok": true]
        }
        transport.emit(["type": "response.created", "response": ["id": "mute"]])
        transport.emit(audioEvent("mute"))
        XCTAssertTrue(audio.pendingPlayback)
        transport.emit(toolEvent("mute", id: "mute-call", name: "set_spoken_output", arguments: "{\"enabled\":false}"))
        XCTAssertFalse(voice.spokenOutputEnabled)
        XCTAssertFalse(audio.pendingPlayback)
        XCTAssertTrue(audio.running)
        XCTAssertTrue(voice.isActive)
        transport.emit(audioEvent("mute"))
        XCTAssertEqual(audio.playCount, 1)
        transport.emit(["type": "response.done", "response": ["id": "mute"]])
        transport.emit(manualResponseCreated(transport, id: "silent-confirmation"))
        transport.emit(audioEvent("silent-confirmation"))
        transport.emit(["type": "response.output_audio_transcript.delta", "response_id": "silent-confirmation", "delta": "Voice muted."])
        XCTAssertEqual(voice.caption, "Voice muted.")
        transport.emit(["type": "response.done", "response": ["id": "silent-confirmation"]])
        XCTAssertEqual(voice.phase, .listening)
        XCTAssertEqual(audio.playCount, 1)
        audio.onInput?(Data([1, 0]))
        XCTAssertTrue(transport.sent.contains { $0["type"] as? String == "input_audio_buffer.append" })

        transport.emit(["type": "response.created", "response": ["id": "quiet-command"]])
        transport.emit(toolEvent("quiet-command", id: "camera-call", name: "start_camera"))
        transport.emit(audioEvent("quiet-command"))
        XCTAssertEqual(actions, [.setSpokenOutput(false), .startCamera])
        XCTAssertEqual(audio.playCount, 1)
        XCTAssertTrue(transport.sent.contains {
            ($0["item"] as? [String: Any])?["call_id"] as? String == "camera-call"
        })

        transport.emit(["type": "input_audio_buffer.speech_started"])
        transport.emit(["type": "input_audio_buffer.speech_stopped"])
        transport.emit(["type": "response.created", "response": ["id": "unmute"]])
        transport.emit(toolEvent("unmute", id: "unmute-call", name: "set_spoken_output", arguments: "{\"enabled\":true}"))
        transport.emit(audioEvent("unmute"))
        XCTAssertTrue(voice.spokenOutputEnabled)
        XCTAssertTrue(audio.running)
        XCTAssertEqual(audio.playCount, 2)
        XCTAssertTrue(audio.pendingPlayback)
        voice.disconnect()
    }

    func testMutedAnnouncementsDoNotGenerateResponsesAndMalformedMuteDoesNotChangeState() {
        let (voice, transport, audio) = ready()
        var actions = 0
        voice.onCommand = { _ in actions += 1; return [:] }
        transport.emit(["type": "response.created", "response": ["id": "bad-mute"]])
        transport.emit(toolEvent("bad-mute", id: "bad-mute-call", name: "set_spoken_output", arguments: "{\"enabled\":0}"))
        XCTAssertEqual(actions, 0)
        XCTAssertTrue(voice.spokenOutputEnabled)
        let output = (transport.sent.last?["item"] as? [String: Any])?["output"] as? String
        XCTAssertTrue(output?.contains("invalid arguments") == true)
        voice.setSpokenOutput(false)
        let requests = transport.sent.count
        XCTAssertFalse(voice.announce("The puck disconnected."))
        XCTAssertFalse(voice.announce("I'm here.", automatic: false))
        XCTAssertEqual(transport.sent.count, requests)
        XCTAssertTrue(audio.running)
        voice.disconnect()
        XCTAssertFalse(voice.spokenOutputEnabled)
    }

    func testMutedSessionStartsListeningWithoutGreetingOrProactiveSpeech() {
        let (voice, transport, audio) = connected()
        voice.setSpokenOutput(false)
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        XCTAssertTrue(audio.running)
        XCTAssertEqual(voice.phase, .listening)
        XCTAssertEqual(voice.label, "Listening quietly")
        XCTAssertFalse(voice.announce("The puck disconnected."))
        XCTAssertFalse(voice.announce("I'm here.", automatic: false))
        XCTAssertFalse(transport.sent.contains { $0["type"] as? String == "response.create" })
        voice.setSpokenOutput(true)
        XCTAssertTrue(voice.announce("Voice is on.", automatic: false))
        XCTAssertTrue(transport.sent.contains { $0["type"] as? String == "response.create" })
        voice.disconnect()
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
        for invalid in ["short", "grok_" + String(repeating: "x", count: 40), "xai-" + String(repeating: "x", count: 40), "sk-proj-" + String(repeating: "x", count: 40),
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
        let session = transport.sent.last?["session"] as? [String: Any]
        XCTAssertEqual(session?["type"] as? String, "realtime")
        XCTAssertNil(session?["voice"])
        XCTAssertNil(session?["turn_detection"])
        let configurationAudio = session?["audio"] as? [String: Any]
        XCTAssertEqual((configurationAudio?["output"] as? [String: Any])?["voice"] as? String, "cedar")
        transport.emit(["type": "session.updated"])
        XCTAssertEqual(audio.startCount, 1)
        XCTAssertEqual(transport.sent.last?["type"] as? String, "response.create")
        let announcement = transport.sent.last?["response"] as? [String: Any]
        XCTAssertEqual(announcement?["conversation"] as? String, "none")
        XCTAssertEqual((announcement?["tools"] as? [Any])?.count, 0)
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
        let (voice, transport, audio) = ready(finishGreeting: false)
        let greeting = manualResponseCreated(transport, id: "late-greeting")
        var actions = 0
        voice.onCommand = { _ in actions += 1; return [:] }
        transport.emit(["type": "input_audio_buffer.speech_started"])
        transport.emit(greeting)
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

    func testInterruptedAnnouncementNeverDiscardsUserStopInEitherArrivalOrder() {
        for noticeArrivesFirst in [true, false] {
            let (voice, transport, audio) = ready(finishGreeting: false)
            let notice = manualResponseCreated(transport, id: "late-notice")
            var actions: [VoiceCommand] = []
            voice.onCommand = { actions.append($0); return ["status": "Camera stopped"] }
            transport.emit(["type": "input_audio_buffer.speech_started"])
            transport.emit(["type": "input_audio_buffer.speech_stopped"])
            if noticeArrivesFirst { transport.emit(notice) }
            transport.emit(["type": "response.created", "response": ["id": "user-stop"]])
            if !noticeArrivesFirst { transport.emit(notice) }
            transport.emit(audioEvent("late-notice"))
            transport.emit(toolEvent("late-notice", id: "stale-action", name: "start_camera"))
            transport.emit(toolEvent("user-stop", id: "stop-command", name: "stop"))
            transport.emit(audioEvent("user-stop"))
            XCTAssertEqual(actions, [.stop])
            XCTAssertEqual(audio.playCount, 1)
            XCTAssertTrue(audio.pendingPlayback)
            XCTAssertTrue(voice.isActive)
            XCTAssertTrue(transport.sent.contains { $0["type"] as? String == "response.cancel" && $0["response_id"] as? String == "late-notice" })
            XCTAssertFalse(transport.sent.contains { $0["type"] as? String == "response.cancel" && $0["response_id"] as? String == "user-stop" })
            voice.disconnect()
        }
    }

    func testUnannouncedUserResponsePreemptsPendingNoticeWithoutBeingOverwritten() {
        let (voice, transport, audio) = ready(finishGreeting: false)
        let notice = manualResponseCreated(transport, id: "late-notice")
        var actions: [VoiceCommand] = []
        voice.onCommand = { actions.append($0); return [:] }
        transport.emit(["type": "response.created", "response": ["id": "user-stop"]])
        transport.emit(notice)
        transport.emit(toolEvent("user-stop", id: "stop-command", name: "stop"))
        transport.emit(audioEvent("late-notice"))
        XCTAssertEqual(actions, [.stop])
        XCTAssertEqual(audio.playCount, 0)
        voice.disconnect()
    }

    func testInterruptedToolContinuationCannotReplaceNewUserResponse() {
        let (voice, transport, audio) = ready()
        var actions: [VoiceCommand] = []
        voice.onCommand = { actions.append($0); return ["status": "Current state"] }
        transport.emit(["type": "response.created", "response": ["id": "status"]])
        transport.emit(toolEvent("status", id: "status-command", name: "get_status"))
        transport.emit(["type": "response.done", "response": ["id": "status"]])
        let continuation = manualResponseCreated(transport, id: "late-continuation")
        let requests = transport.sent.filter { $0["type"] as? String == "response.create" }
        let requestIDs = requests.compactMap { (($0["response"] as? [String: Any])?["metadata"] as? [String: String])?["feel_request_id"] }
        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(Set(requestIDs).count, 2)
        transport.emit(["type": "input_audio_buffer.speech_started"])
        transport.emit(["type": "input_audio_buffer.speech_stopped"])
        transport.emit(["type": "response.created", "response": ["id": "user-stop"]])
        transport.emit(continuation)
        transport.emit(toolEvent("late-continuation", id: "stale-command", name: "start_camera"))
        transport.emit(toolEvent("user-stop", id: "stop-command", name: "stop"))
        transport.emit(audioEvent("late-continuation"))
        XCTAssertEqual(actions, [.status, .stop])
        XCTAssertEqual(audio.playCount, 0)
        XCTAssertTrue(voice.isActive)
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
            let observation = manualResponseCreated(transport, id: "observation")
            if invalidateBeforeResponse { voice.invalidateSceneSpeech() }
            transport.emit(observation)
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

    func testInputQueueOverflowStopsCaptureRatherThanSendingStaleAudio() {
        let (voice, transport, audio) = ready()
        transport.holdSends = true
        audio.onInput?(Data([0, 0])) // In flight.
        audio.onInput?(Data(repeating: 0, count: 48_000))
        XCTAssertTrue(voice.isActive)
        audio.onInput?(Data([0, 0]))
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertFalse(voice.isActive)
        XCTAssertFalse(audio.running)
    }

    func testBriefSendStallCoalescesInputWithoutLosingAudioOrControls() {
        let (voice, transport, audio) = ready()
        transport.emit(["type": "response.created", "response": ["id": "greeting"]])
        transport.emit(audioEvent("greeting"))
        transport.holdSends = true
        audio.onInput?(Data([0, 0]))
        for _ in 0..<20 { audio.onInput?(Data(repeating: 1, count: 960)) }
        transport.emit(["type": "input_audio_buffer.speech_started"])
        XCTAssertTrue(voice.isActive)
        XCTAssertTrue(audio.running)
        transport.holdSends = false
        transport.heldCompletion?(true)
        let packets = transport.sent.filter { $0["type"] as? String == "input_audio_buffer.append" }
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(Data(base64Encoded: packets[1]["audio"] as! String)?.count, 19_200)
        XCTAssertEqual(transport.sent.last?["type"] as? String, "conversation.item.truncate")
        voice.disconnect()
    }

    func testNextUserTurnDoesNotTruncateFullyPlayedResponse() {
        let (voice, transport, audio) = ready()
        transport.emit(["type": "response.created", "response": ["id": "greeting"]])
        transport.emit(audioEvent("greeting"))
        transport.emit(["type": "response.done", "response": ["id": "greeting"]])
        audio.drain()
        transport.emit(["type": "input_audio_buffer.speech_started"])
        XCTAssertFalse(transport.sent.contains { $0["type"] as? String == "conversation.item.truncate" })
        XCTAssertTrue(voice.isActive)
        voice.disconnect()
    }

    func testAnnouncementCannotRunToolsOrTruncateMissingConversationItem() {
        let (voice, transport, audio) = ready(finishGreeting: false)
        var actions = 0
        voice.onCommand = { _ in actions += 1; return [:] }
        transport.emit(manualResponseCreated(transport, id: "notice"))
        transport.emit(audioEvent("notice"))
        transport.emit(toolEvent("notice", id: "unexpected", name: "start_camera"))
        XCTAssertEqual(actions, 0)
        transport.emit(["type": "input_audio_buffer.speech_started"])
        XCTAssertFalse(audio.pendingPlayback)
        XCTAssertFalse(transport.sent.contains { $0["type"] as? String == "conversation.item.truncate" })
        XCTAssertTrue(voice.isActive)
        voice.disconnect()
    }

    func testFailedProviderResponseDoesNotPretendToListen() {
        let (voice, transport, audio) = ready()
        transport.emit(["type": "response.created", "response": ["id": "failed"]])
        transport.emit(["type": "response.done", "response": ["id": "failed", "status": "failed"]])
        XCTAssertEqual(voice.phase, .failed)
        XCTAssertFalse(audio.running)
    }

    func testStatusWithoutObservationSurvivesNextModelTick() {
        let (voice, transport, audio) = ready()
        let model = LanternModel(voice: voice)
        transport.emit(["type": "response.created", "response": ["id": "status"]])
        transport.emit(toolEvent("status", id: "status-call", name: "get_status"))
        transport.emit(["type": "response.done", "response": ["id": "status"]])
        _ = model.voiceSnapshot()
        transport.emit(manualResponseCreated(transport, id: "recovery"))
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
        transport.emit(manualResponseCreated(transport, id: "observation"))
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
        let responseRequestsAfterGreeting = transport.sent.filter { $0["type"] as? String == "response.create" }.count
        var actions = 0
        voice.onCommand = { _ in actions += 1; return ["status": "actual result"] }
        transport.emit(["type": "response.created", "response": ["id": "response-1"]])
        transport.emit(audioEvent("response-1"))
        let event = toolEvent("response-1", id: "call-1", name: "get_status")
        transport.emit(event); transport.emit(event)
        XCTAssertEqual(actions, 1)
        transport.emit(["type": "response.done", "response": ["id": "response-1"]])
        XCTAssertEqual(transport.sent.filter { $0["type"] as? String == "response.create" }.count, responseRequestsAfterGreeting)
        audio.drain()
        XCTAssertEqual(transport.sent.filter { $0["type"] as? String == "response.create" }.count, responseRequestsAfterGreeting + 1)
        audio.drain()
        XCTAssertEqual(transport.sent.filter { $0["type"] as? String == "response.create" }.count, responseRequestsAfterGreeting + 1)
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

    private func deliveryReady() -> (RealtimeVoiceSession, FakeVoiceTransport, FakeVoiceAudio) {
        let (voice, transport, audio) = connected()
        // Skip the automatic greeting without waiting for its announcement throttle.
        voice.setSpokenOutput(false)
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        voice.setSpokenOutput(true)
        return (voice, transport, audio)
    }

    func testAnnouncementDeliveryWaitsForCompletionAndDrainInEitherOrder() {
        for drainFirst in [true, false] {
            let (voice, transport, audio) = deliveryReady()
            defer { voice.disconnect() }
            var deliveries = 0
            XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, onDelivered: { deliveries += 1 }))
            XCTAssertEqual(deliveries, 0)
            transport.emit(manualResponseCreated(transport, id: "notice"))
            transport.emit(audioEvent("notice"))
            if drainFirst { audio.drain() }
            XCTAssertEqual(deliveries, 0)
            transport.emit(["type": "response.done", "response": ["id": "notice", "status": "completed"]])
            XCTAssertEqual(deliveries, drainFirst ? 1 : 0)
            audio.drain()
            transport.emit(["type": "response.done", "response": ["id": "notice", "status": "completed"]])
            audio.drain()
            XCTAssertEqual(deliveries, 1)
        }
    }

    func testAnnouncementDeliveryRequiresFinalChunkToDrain() {
        let (voice, transport, audio) = deliveryReady()
        defer { voice.disconnect() }
        var deliveries = 0
        XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, onDelivered: { deliveries += 1 }))
        transport.emit(manualResponseCreated(transport, id: "notice"))
        transport.emit(audioEvent("notice")); audio.drain()
        transport.emit(audioEvent("notice"))
        transport.emit(["type": "response.done", "response": ["id": "notice", "status": "completed"]])
        XCTAssertEqual(deliveries, 0)
        audio.drain()
        XCTAssertEqual(deliveries, 1)
    }

    func testAnnouncementWithoutAudioOrSuccessfulCompletionIsNotDelivered() {
        for status in ["completed", "cancelled", "incomplete", "failed"] {
            let (voice, transport, audio) = deliveryReady()
            var deliveries = 0
            XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, onDelivered: { deliveries += 1 }))
            transport.emit(manualResponseCreated(transport, id: "notice"))
            // The completed case deliberately produces captions only; other cases have audio.
            if status != "completed" { transport.emit(audioEvent("notice")); audio.drain() }
            transport.emit(["type": "response.done", "response": ["id": "notice", "status": status]])
            audio.drain()
            XCTAssertEqual(deliveries, 0, status)
            voice.disconnect()
        }
    }

    func testDelayedAnnouncementCancelledBeforeAudioIsNotDelivered() {
        let (voice, transport, audio) = deliveryReady()
        defer { voice.disconnect() }
        var deliveries = 0
        XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, sceneBound: true, onDelivered: { deliveries += 1 }))
        let delayed = manualResponseCreated(transport, id: "delayed")
        voice.invalidateSceneSpeech()
        transport.emit(delayed)
        transport.emit(audioEvent("delayed"))
        transport.emit(["type": "response.done", "response": ["id": "delayed", "status": "completed"]])
        audio.drain()
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(audio.playCount, 0)
    }

    func testMuteDiscardsAnnouncementDeliveryWhileCaptureContinues() {
        let (voice, transport, audio) = deliveryReady()
        defer { voice.disconnect() }
        var deliveries = 0
        XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, onDelivered: { deliveries += 1 }))
        transport.emit(manualResponseCreated(transport, id: "notice"))
        transport.emit(audioEvent("notice"))
        voice.setSpokenOutput(false)
        voice.setSpokenOutput(true)
        transport.emit(audioEvent("notice"))
        transport.emit(["type": "response.done", "response": ["id": "notice", "status": "completed"]])
        audio.drain()
        XCTAssertEqual(deliveries, 0)
        XCTAssertTrue(audio.running)
        audio.onInput?(Data([1, 0]))
        XCTAssertEqual(transport.sent.last?["type"] as? String, "input_audio_buffer.append")
    }

    func testInterruptedOrReplacedAnnouncementCannotReportUserResponseAsDelivery() {
        for interrupt in [true, false] {
            let (voice, transport, audio) = deliveryReady()
            var deliveries = 0
            XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, onDelivered: { deliveries += 1 }))
            transport.emit(manualResponseCreated(transport, id: "notice"))
            transport.emit(audioEvent("notice"))
            if interrupt {
                transport.emit(["type": "input_audio_buffer.speech_started"])
                transport.emit(["type": "input_audio_buffer.speech_stopped"])
            }
            transport.emit(["type": "response.created", "response": ["id": "user-answer"]])
            transport.emit(["type": "response.done", "response": ["id": "notice", "status": "completed"]])
            transport.emit(audioEvent("user-answer"))
            transport.emit(["type": "response.done", "response": ["id": "user-answer", "status": "completed"]])
            audio.drain()
            XCTAssertEqual(deliveries, 0)
            voice.disconnect()
        }
    }

    func testOldResponseCannotConsumeNewAnnouncementDeliveryAfterReconnect() {
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio)
        defer { voice.disconnect() }
        func configure() {
            voice.setSpokenOutput(false)
            voice.start(); token.complete(.success("ephemeral-test-token"))
            transport.emit(["type": "session.created"])
            transport.emit(["type": "session.updated"])
            voice.setSpokenOutput(true)
        }
        configure()
        var oldDeliveries = 0, newDeliveries = 0
        XCTAssertTrue(voice.announce("Old observation.", automatic: false, onDelivered: { oldDeliveries += 1 }))
        let old = manualResponseCreated(transport, id: "old")
        XCTAssertTrue(voice.hasPendingAnnouncementDelivery)
        voice.disconnect()
        XCTAssertFalse(voice.hasPendingAnnouncementDelivery)
        configure()
        XCTAssertTrue(voice.announce("New observation.", automatic: false, onDelivered: {
            XCTAssertFalse(voice.hasPendingAnnouncementDelivery)
            newDeliveries += 1
        }))
        let fresh = manualResponseCreated(transport, id: "fresh")
        transport.emit(old)
        transport.emit(audioEvent("old"))
        transport.emit(["type": "response.done", "response": ["id": "old", "status": "completed"]])
        audio.drain()
        XCTAssertEqual(newDeliveries, 0)
        XCTAssertTrue(voice.hasPendingAnnouncementDelivery)
        transport.emit(fresh); transport.emit(audioEvent("fresh"))
        transport.emit(["type": "response.done", "response": ["id": "fresh", "status": "completed"]])
        audio.drain()
        XCTAssertEqual(newDeliveries, 1)
        XCTAssertEqual(oldDeliveries, 0)
    }

    func testSceneExpiryDiscardsUndeliveredAnnouncementCallback() {
        let (voice, transport, audio) = deliveryReady()
        defer { voice.disconnect() }
        var deliveries = 0
        XCTAssertTrue(voice.announce("A chair was ahead.", automatic: false, sceneBound: true, onDelivered: { deliveries += 1 }))
        transport.emit(manualResponseCreated(transport, id: "notice"))
        transport.emit(audioEvent("notice"))
        transport.emit(["type": "response.done", "response": ["id": "notice", "status": "completed"]])
        let expired = expectation(description: "Undelivered announcement expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { expired.fulfill() }
        wait(for: [expired], timeout: 4)
        XCTAssertFalse(voice.hasPendingAnnouncementDelivery)
        audio.drain()
        XCTAssertEqual(deliveries, 0)
    }

    private func makeVoice(_ token: FakeVoiceToken, _ transport: FakeVoiceTransport, _ audio: FakeVoiceAudio,
                           permission: @escaping (@escaping (Bool) -> Void) -> Void = { $0(true) }) -> RealtimeVoiceSession {
        RealtimeVoiceSession(tokenClient: token, audio: audio, transportFactory: { transport },
                         configuration: config, speaksLocally: false, requestPermission: permission)
    }
    private func connected() -> (RealtimeVoiceSession, FakeVoiceTransport, FakeVoiceAudio) {
        let token = FakeVoiceToken(), transport = FakeVoiceTransport(), audio = FakeVoiceAudio()
        let voice = makeVoice(token, transport, audio)
        voice.start(); token.complete(.success("ephemeral-test-token"))
        return (voice, transport, audio)
    }
    private func ready(finishGreeting: Bool = true) -> (RealtimeVoiceSession, FakeVoiceTransport, FakeVoiceAudio) {
        let (voice, transport, audio) = connected()
        transport.emit(["type": "session.created"])
        transport.emit(["type": "session.updated"])
        if finishGreeting {
            transport.emit(manualResponseCreated(transport, id: "initial-greeting"))
            transport.emit(["type": "response.done", "response": ["id": "initial-greeting", "status": "completed"]])
        }
        return (voice, transport, audio)
    }
    private func manualResponseCreated(_ transport: FakeVoiceTransport, id: String) -> [String: Any] {
        let request = transport.sent.last { $0["type"] as? String == "response.create" }?["response"] as? [String: Any]
        let metadata = request?["metadata"] as? [String: String] ?? [:]
        XCTAssertNotNil(metadata["feel_request_id"])
        return ["type": "response.created", "response": ["id": id, "metadata": metadata]]
    }
    private func audioEvent(_ response: String) -> [String: Any] {
        ["type": "response.output_audio.delta", "response_id": response, "item_id": "item-1", "delta": Data([1, 0]).base64EncodedString()]
    }
    private func toolEvent(_ response: String, id: String, name: String, arguments: String = "{}") -> [String: Any] {
        ["type": "response.function_call_arguments.done", "response_id": response, "call_id": id, "name": name, "arguments": arguments]
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
    var heldCompletion: ((Bool) -> Void)?
    func open(token: String) { openCount += 1 }
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) {
        sent.append(event)
        if holdSends { heldCompletion = completion } else { completion(true) }
    }
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

extension RealtimeVoiceTests {
    private func idle() -> (RealtimeVoiceSession, FakeVoiceTransport, FakeVoiceAudio) {
        let (voice, transport, audio) = ready()
        // Finish the "I'm here" greeting so the session is listening.
        transport.emit(["type": "response.created", "response": ["id": "greet"]])
        transport.emit(["type": "response.done", "response": ["id": "greet"]])
        XCTAssertEqual(voice.phase, .listening)
        return (voice, transport, audio)
    }

    func testChooseTargetCommand() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "choose_target", arguments: "{\"option\":2}"), .chooseTarget(2))
        for args in ["{\"option\":0}", "{\"option\":5}", "{\"option\":1.5}", "{\"option\":true}", "{\"option\":\"1\"}", "{}"] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: "choose_target", arguments: args), args)
        }
        XCTAssertTrue(VoiceCommand.tools.contains { $0["name"] as? String == "choose_target" })
    }

    func testBorrowedMicrophoneMutesUplink() {
        let (voice, transport, audio) = idle()
        let before = transport.sent.count
        XCTAssertTrue(voice.borrowMicrophone { _ in })
        audio.onInput?(Data([1, 0]))
        XCTAssertEqual(transport.sent.count, before, "the target word must not reach the assistant")
        voice.borrowMicrophone(nil)
        audio.onInput?(Data([1, 0]))
        XCTAssertEqual(transport.sent.last?["type"] as? String, "input_audio_buffer.append")
    }

    func testBorrowFailsWithoutRunningAssistant() {
        let voice = makeVoice(FakeVoiceToken(), FakeVoiceTransport(), FakeVoiceAudio())
        XCTAssertFalse(voice.borrowMicrophone { _ in })
    }

    func testAskSpeaksTheQuestionOnlyWhenIdle() {
        let (voice, transport, _) = idle()
        XCTAssertTrue(voice.ask("I see 2 exits. 1: left, about 3 meters. 2: right, about 5 meters. Which one?"))
        // OpenAI has no force_message: the question is an in-conversation response with verbatim instructions.
        XCTAssertEqual(transport.sent.last?["type"] as? String, "response.create")
        let response = transport.sent.last?["response"] as? [String: Any]
        XCTAssertTrue((response?["instructions"] as? String)?.contains("Which one?") == true)
        XCTAssertNil(response?["conversation"], "the answer must be matched in the conversation")
        XCTAssertFalse(voice.ask("again"), "a question already waiting for its response")
    }
}
