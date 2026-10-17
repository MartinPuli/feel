import XCTest
@testable import FeelCore

final class TargetWordTests: XCTestCase {
    func testMatches() {
        let cases: [(String, TargetWord?)] = [
            ("exit", .exit), ("Exit.", .exit), ("the exit sign", .exit), ("way out", .exit), ("exits", .exit),
            ("door", .door), ("a doorway please", .door), ("chair", .chair), ("somewhere to sit, a seat", .chair),
            ("person", .person), ("someone", .person), ("my teammate", .teammate),
            ("", nil), ("hello there", nil), ("indoors", nil), ("exiting", nil), ("outdoor", nil)]
        for (text, word) in cases { XCTAssertEqual(TargetWord.match(text), word, text) }
    }
    func testEarliestWordWins() {
        XCTAssertEqual(TargetWord.match("door no exit"), .door)
        XCTAssertEqual(TargetWord.match("exit not the door"), .exit)
    }
    func testQuestion() {
        let q = TargetChoice.question([TargetChoice(bearingDegrees: -30, distance: 3.1), TargetChoice(bearingDegrees: 20, distance: 5.2)], word: .exit)
        XCTAssertEqual(q, "I see 2 exits. 1: left, about 3 meters. 2: slightly right, about 5 meters. Which one?")
        XCTAssertEqual(TargetChoice(bearingDegrees: 2, distance: 1.7).spokenPlace, "ahead, about 1.5 meters")
    }
}

final class DirectionRequestTests: XCTestCase {
    private let one = [TargetChoice(bearingDegrees: 10, distance: 3)]
    private let two = [TargetChoice(bearingDegrees: -30, distance: 3), TargetChoice(bearingDegrees: 5, distance: 4)]

    func testSignWordSeenStarts() {
        var r = DirectionRequest()
        XCTAssertEqual(r.handBegan(now: 0), [.startListening])
        XCTAssertEqual(r.signFired(now: 0.5, selected: nil), [.sound(.listening)])
        XCTAssertEqual(r.heardWord(.exit, now: 1.2, selected: nil), [.stopListening, .select(.exit)])
        XCTAssertEqual(r.tick(now: 1.5, selected: .exit, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: false), [])
        XCTAssertEqual(r.tick(now: 2.0, selected: .exit, choices: one, hintTime: 1.9, lockedTarget: false, agentAvailable: false), [.startGuidance])
        XCTAssertFalse(r.isBusy)
    }
    func testWordDuringHoldResolvesOnFire() {
        var r = DirectionRequest()
        _ = r.handBegan(now: 0)
        XCTAssertEqual(r.heardWord(.door, now: 0.3, selected: nil), [])
        XCTAssertEqual(r.signFired(now: 0.5, selected: nil), [.stopListening, .select(.door)], "no listening sound: the word is already in")
    }
    func testSameWordAsSelectedDoesNotReselect() {
        var r = DirectionRequest(); _ = r.handBegan(now: 0); _ = r.signFired(now: 0.5, selected: .exit)
        XCTAssertEqual(r.heardWord(.exit, now: 1, selected: .exit), [.stopListening])
    }
    func testNoWordUsesSelectedTarget() {
        var r = DirectionRequest(); _ = r.handBegan(now: 0); _ = r.signFired(now: 0.5, selected: .door)
        XCTAssertEqual(r.tick(now: 3.0, selected: .door, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: false), [.stopListening])
        XCTAssertEqual(r.tick(now: 3.1, selected: .door, choices: one, hintTime: 3.1, lockedTarget: false, agentAvailable: false), [.startGuidance])
    }
    func testNoWordNoTargetFails() {
        var r = DirectionRequest(); _ = r.handBegan(now: 0); _ = r.signFired(now: 0.5, selected: nil)
        XCTAssertEqual(r.tick(now: 3.0, selected: nil, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: false), [.stopListening, .sound(.failure)])
    }
    func testTargetNeverSeenFails() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: nil); _ = r.heardWord(.chair, now: 1, selected: nil)
        XCTAssertEqual(r.tick(now: 3.9, selected: .chair, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: false), [])
        XCTAssertEqual(r.tick(now: 4.0, selected: .chair, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: false), [.sound(.failure)])
    }
    func testStaleHintIgnored() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: nil); _ = r.heardWord(.exit, now: 1, selected: nil)
        XCTAssertEqual(r.tick(now: 1.2, selected: .exit, choices: one, hintTime: 0.8, lockedTarget: false, agentAvailable: false), [], "hint predates the request")
    }
    func testBriefHandWithoutFireStopsListening() {
        var r = DirectionRequest(); _ = r.handBegan(now: 0)
        XCTAssertEqual(r.tick(now: 1.6, selected: nil, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: false), [.stopListening])
        XCTAssertFalse(r.isBusy)
    }
    func testTwoTargetsAskTheAssistant() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: nil); _ = r.heardWord(.exit, now: 1, selected: nil)
        XCTAssertEqual(r.tick(now: 1.5, selected: .exit, choices: two, hintTime: 1.5, lockedTarget: false, agentAvailable: true), [.ask(two)])
        XCTAssertEqual(r.tick(now: 5, selected: .exit, choices: two, hintTime: 5, lockedTarget: false, agentAvailable: true), [], "waits for the answer")
        XCTAssertEqual(r.chose(1, now: 6), [.lock(1)])
        XCTAssertEqual(r.tick(now: 6.1, selected: .exit, choices: two, hintTime: 5.9, lockedTarget: true, agentAvailable: true), [], "hint from before the choice")
        XCTAssertEqual(r.tick(now: 6.5, selected: .exit, choices: two, hintTime: 6.4, lockedTarget: true, agentAvailable: true), [.startGuidance])
    }
    func testChoiceTimesOut() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: .exit); _ = r.tick(now: 2.5, selected: .exit, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: true)
        _ = r.tick(now: 3, selected: .exit, choices: two, hintTime: 3, lockedTarget: false, agentAvailable: true)
        XCTAssertEqual(r.tick(now: 18.1, selected: .exit, choices: two, hintTime: 18, lockedTarget: false, agentAvailable: true), [.sound(.failure)])
        XCTAssertEqual(r.chose(0, now: 19), [], "late answers are ignored")
    }
    func testInvalidChoiceIgnored() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: .exit); _ = r.tick(now: 2.5, selected: .exit, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: true)
        _ = r.tick(now: 3, selected: .exit, choices: two, hintTime: 3, lockedTarget: false, agentAvailable: true)
        XCTAssertEqual(r.chose(5, now: 4), [])
    }
    func testWithoutAssistantTakesTheOneAhead() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: nil); _ = r.heardWord(.exit, now: 1, selected: nil)
        XCTAssertEqual(r.tick(now: 1.5, selected: .exit, choices: two, hintTime: 1.5, lockedTarget: false, agentAvailable: false), [.lock(1)])
        XCTAssertEqual(r.tick(now: 2.0, selected: .exit, choices: two, hintTime: 1.9, lockedTarget: true, agentAvailable: false), [.startGuidance])
    }
    func testAlreadyFollowingOneSkipsTheQuestion() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: .exit)
        _ = r.tick(now: 2.5, selected: .exit, choices: [], hintTime: nil, lockedTarget: true, agentAvailable: true)
        XCTAssertEqual(r.tick(now: 2.6, selected: .exit, choices: two, hintTime: 2.6, lockedTarget: true, agentAvailable: true), [.startGuidance])
    }
    func testNewSignRestarts() {
        var r = DirectionRequest(); _ = r.signFired(now: 0, selected: .exit); _ = r.tick(now: 2.5, selected: .exit, choices: [], hintTime: nil, lockedTarget: false, agentAvailable: true)
        _ = r.tick(now: 3, selected: .exit, choices: two, hintTime: 3, lockedTarget: false, agentAvailable: true)
        XCTAssertEqual(r.signFired(now: 4, selected: .exit), [.startListening, .sound(.listening)])
    }
}
