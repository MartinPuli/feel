import XCTest
@testable import Lantern

final class VoiceNewCommandTests: XCTestCase {
    func testRecordingRequiresExplicitVideoChoiceOnEveryStart() throws {
        XCTAssertEqual(try VoiceCommand.decode(name:"start_recording",arguments:"{\"include_video\":false}"),.startRecording(false))
        XCTAssertEqual(try VoiceCommand.decode(name:"start_recording",arguments:"{\"include_video\":true}"),.startRecording(true))
        for invalid in ["{}", "{\"enabled\":true}", "{\"include_video\":1}", "{\"include_video\":null}"] {
            XCTAssertThrowsError(try VoiceCommand.decode(name:"start_recording",arguments:invalid))
        }
        XCTAssertThrowsError(try VoiceCommand.decode(name:"set_recording",arguments:"{\"enabled\":true}"))
    }

    func testMutedAssistantDoesNotQueueAnInaudibleChoiceQuestion() {
        let (voice, transport) = VoiceTestDoubles.activeSession()
        defer { voice.disconnect() }
        voice.setSpokenOutput(false)
        let before = transport.sent.count
        XCTAssertFalse(voice.ask("Which chair?"))
        XCTAssertEqual(transport.sent.count, before)
        XCTAssertTrue(voice.isActive)
    }

    func testNewControlsRejectCoercionAndExtraArguments() throws {
        let flags: [(String, (Bool) -> VoiceCommand)] = [
            ("set_direction_arrows", VoiceCommand.setDirectionArrows),
            ("set_recording_video", VoiceCommand.setRecordingVideo)
        ]
        for (name, command) in flags {
            XCTAssertEqual(try VoiceCommand.decode(name:name,arguments:"{\"enabled\":true}"),command(true))
            XCTAssertEqual(try VoiceCommand.decode(name:name,arguments:"{\"enabled\":false}"),command(false))
            for invalid in ["{}", "{\"enabled\":1}", "{\"enabled\":\"true\"}", "{\"enabled\":true,\"extra\":0}"] {
                XCTAssertThrowsError(try VoiceCommand.decode(name:name,arguments:invalid),name)
            }
        }
        for (name, command) in [("start_directions",VoiceCommand.startDirections),
                                ("stop_directions",.stopDirections),
                                ("stop_recording",.stopRecording),
                                ("simulate_direction_sign",.simulateDirectionSign)] {
            XCTAssertEqual(try VoiceCommand.decode(name:name,arguments:"{}"),command)
            XCTAssertThrowsError(try VoiceCommand.decode(name:name,arguments:"{\"enabled\":true}"))
        }
    }
}
