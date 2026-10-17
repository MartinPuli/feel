import XCTest
import FeelCore

final class OpenSideTests: XCTestCase {
    func testOpenOrUnknownWayAheadSaysNothing() {
        var finder = OpenSideFinder()
        XCTAssertNil(finder.update(distances: [3, 3, 3, 3, 3, 3, 3], now: 0))
        XCTAssertNil(finder.update(distances: [nil, nil, 1.7, 1.8, 1.7, nil, nil], now: 0.1))
        XCTAssertNil(finder.update(distances: [nil, nil, nil, nil, nil, nil, nil], now: 0.2), "unknown ahead is unknown, not blocked")
    }

    func testWallAheadNamesTheSideWithRoomForAWholePerson() throws {
        var finder = OpenSideFinder()
        // Room on the far left; the right has one narrow gap a body would not fit through.
        let open = try XCTUnwrap(finder.update(distances: [3, 3, 0.8, 0.8, 0.8, 3, 0.8], now: 0))
        XCTAssertEqual(open.side, .left)
        XCTAssertEqual(open.column, 0)
        XCTAssertEqual(open.aheadRange, 0.8)
        XCTAssertEqual(open.urgency, pow((1.6 - 0.8) / 1.3, 0.6), accuracy: 1e-9)
        XCTAssertEqual(open.advantage, 2.2, accuracy: 1e-9)
        XCTAssertEqual(open.spoken, "More room to your left.")
        XCTAssertEqual(finder.update(distances: [3, 3, 0.2, 0.2, 0.2, 3, 0.8], now: 0.1)?.urgency, 1)
    }

    func testUnknownSectorsAreNeverRoom() throws {
        var finder = OpenSideFinder()
        XCTAssertEqual(try XCTUnwrap(finder.update(distances: [2.5, 2.5, 0.7, 0.7, 0.7, nil, nil], now: 0)).side, .left)
        var boxed = OpenSideFinder()
        let open = try XCTUnwrap(boxed.update(distances: [nil, nil, 0.5, 0.5, 0.5, nil, nil], now: 0))
        XCTAssertEqual(open.side, .ahead)
        XCTAssertEqual(open.column, 3)
        XCTAssertEqual(open.advantage, 0)
        XCTAssertEqual(open.spoken, "No more room to either side.")
    }

    func testSideHoldsUntilAnotherColumnIsClearlyBetter() throws {
        var finder = OpenSideFinder()
        var open = try XCTUnwrap(finder.update(distances: [2.0, 2.0, 0.8, 0.8, 0.8, 2.2, 2.2], now: 0))
        XCTAssertEqual(open.side, .right)
        for tick in 1...30 { open = try XCTUnwrap(finder.update(distances: [2.0, 2.0, 0.8, 0.8, 0.8, 1.9, 1.9], now: Double(tick) * 0.1)) }
        XCTAssertEqual(open.side, .right, "a small loss on the right is inside the switch margin")
        for tick in 31...60 { open = try XCTUnwrap(finder.update(distances: [2.0, 2.0, 0.8, 0.8, 0.8, 1.4, 1.4], now: Double(tick) * 0.1)) }
        XCTAssertEqual(open.side, .left)
    }

    func testASingleNoisyFrameDoesNotFlipTheSide() throws {
        var finder = OpenSideFinder()
        var open: OpenSide?
        for tick in 0..<30 { open = finder.update(distances: [2.4, 2.4, 0.8, 0.8, 0.8, 2.0, 2.0], now: Double(tick) * 0.1) }
        XCTAssertEqual(open?.side, .left)
        open = finder.update(distances: [1.0, 1.0, 0.8, 0.8, 0.8, 4.0, 4.0], now: 3.0)
        XCTAssertEqual(open?.side, .left)
    }

    func testResetsWhenTimeGoesBackwardsOrInputIsMalformed() {
        var finder = OpenSideFinder()
        XCTAssertEqual(finder.update(distances: [3, 3, 0.8, 0.8, 0.8, 1, 1], now: 5)?.side, .left)
        XCTAssertNil(finder.update(distances: [3, 3, 3], now: 6))
        XCTAssertEqual(finder.update(distances: [1, 1, 0.8, 0.8, 0.8, 3, 3], now: 4)?.side, .right, "an earlier time starts over without hysteresis")
    }
}
