import XCTest
@testable import Lantern

final class VoiceControlTests: XCTestCase {
    func testAuthorizationCannotTurnACompletedOrCanceledAttemptIntoListening() {
        var attempt = VoiceAttempt()
        let old = attempt.begin()
        XCTAssertTrue(attempt.authorizing(old))
        attempt.cancel()
        XCTAssertFalse(attempt.authorizing(old))
        XCTAssertFalse(attempt.listen(old))
        let current = attempt.begin()
        XCTAssertNotEqual(current, old)
        XCTAssertFalse(attempt.listen(old))
        XCTAssertTrue(attempt.listen(current))
        XCTAssertTrue(attempt.acceptsResult(current))
    }

    func testFinishKeepsCurrentFinalEligibleAndCompletesOnlyOnce() {
        var attempt = VoiceAttempt()
        let token = attempt.begin()
        XCTAssertFalse(attempt.complete(token))
        XCTAssertFalse(attempt.finish(token))
        XCTAssertTrue(attempt.listen(token))
        XCTAssertTrue(attempt.finish(token))
        XCTAssertEqual(attempt.phase, .finishing)
        XCTAssertFalse(attempt.finish(token))
        XCTAssertTrue(attempt.acceptsResult(token))
        XCTAssertTrue(attempt.complete(token))
        XCTAssertFalse(attempt.complete(token))
        XCTAssertFalse(attempt.acceptsResult(token))
        XCTAssertEqual(attempt.phase, .idle)
    }

    func testCancelWhileFinishingRejectsLateFinalAndOldTimeouts() {
        var attempt = VoiceAttempt()
        let old = attempt.begin()
        XCTAssertTrue(attempt.listen(old)); XCTAssertTrue(attempt.finish(old))
        attempt.cancel()
        let current = attempt.begin()
        XCTAssertTrue(attempt.listen(current))
        XCTAssertFalse(attempt.acceptsResult(old))
        XCTAssertFalse(attempt.complete(old))
        XCTAssertFalse(attempt.finish(old))
        XCTAssertTrue(attempt.acceptsResult(current))
        XCTAssertEqual(attempt.phase, .listening)
    }

    func testRestartDuringAuthorizationInvalidatesTheFirstPermissionReply() {
        var attempt = VoiceAttempt()
        let old = attempt.begin(), current = attempt.begin()
        XCTAssertFalse(attempt.authorizing(old))
        XCTAssertTrue(attempt.authorizing(current))
        XCTAssertFalse(attempt.listen(old))
        XCTAssertTrue(attempt.listen(current))
    }

    func testFinalTranscriptBoundsRejectTheWholeOverlongCommand() {
        let limit = String(repeating: "a", count: 160)
        XCTAssertEqual(VoiceTranscriptPolicy.final(limit), limit)
        XCTAssertNil(VoiceTranscriptPolicy.final(limit + "b"))
        XCTAssertEqual(VoiceTranscriptPolicy.display(limit + "b"), limit)
        let unicodeLimit = String(repeating: "é", count: 160)
        XCTAssertEqual(VoiceTranscriptPolicy.final(unicodeLimit), unicodeLimit)
        XCTAssertNil(VoiceTranscriptPolicy.final(unicodeLimit + "é"))
    }

    func testEmptyAndControlTextCannotBecomeACommand() {
        XCTAssertEqual(VoiceTranscriptPolicy.final("  remember Desk  "), "remember Desk")
        for value in ["", "   ", "stop\u{0}", "recall\nDesk", "recall\u{202E}Desk"] {
            XCTAssertNil(VoiceTranscriptPolicy.final(value), value)
        }
        XCTAssertEqual(VoiceTranscriptPolicy.display("stop\u{0}\u{202E}"), "stop")
    }

    func testCombiningScalarsCannotBypassTheTranscriptAndReadbackLimit() {
        let limit = "e" + String(repeating: "\u{0301}", count: 159)
        let overlong = limit + "\u{0301}"
        XCTAssertEqual(overlong.count, 1) // One grapheme, but 161 scalars.
        XCTAssertEqual(VoiceTranscriptPolicy.final(limit), limit)
        XCTAssertNil(VoiceTranscriptPolicy.final(overlong))
        XCTAssertFalse(VoiceTranscriptPolicy.isWithinLimit(overlong))
        XCTAssertEqual(VoiceTranscriptPolicy.display(overlong).unicodeScalars.count, 160)
        XCTAssertEqual(VoiceTranscriptPolicy.display(overlong), limit)
    }

    @MainActor
    func testConstructionAndCancelDoNotStartListeningOrDeliverACommand() {
        let voice = VoiceControl()
        var delivered = false
        voice.onFinalTranscript = { _ in delivered = true }
        XCTAssertFalse(voice.isListening)
        XCTAssertFalse(voice.canFinish)
        XCTAssertEqual(voice.transcript, "")
        voice.finish(); voice.cancel(); voice.cancel()
        XCTAssertFalse(voice.isListening)
        XCTAssertFalse(voice.canFinish)
        XCTAssertFalse(delivered)
    }
}
