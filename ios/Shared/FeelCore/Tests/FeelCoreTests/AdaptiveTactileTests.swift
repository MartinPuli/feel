import XCTest
@testable import FeelCore

final class AdaptiveTactileTests: XCTestCase {
    private func packet(_ sequence: UInt8 = 0, bands: [UInt8] = [0, 2, 3, 2, 4, 0, 0], highlight: UInt8 = 3) throws -> FeelPacket {
        try FeelPacket(sequence: sequence, bands: bands, highlight: highlight)
    }
    private func apply(_ controller: inout AdaptiveTactileController, _ packet: FeelPacket,
                       _ time: Double, _ profile: AdaptiveProfile = .reduced, session: String = "one") -> FeelPacket {
        controller.apply(packet: packet, profile: profile, session: session, now: time)
    }

    func testStandardPreservesEffectiveHighlightAndEveryBand() throws {
        var c = AdaptiveTactileController()
        for sequence in UInt8.min...UInt8.max {
            let input = try packet(sequence)
            XCTAssertEqual(apply(&c, input, Double(sequence), .standard), input)
        }
        let empty = try packet(0, highlight: 6)
        let output = apply(&c, empty, 256, .standard)
        XCTAssertEqual(output.sequence, empty.sequence)
        XCTAssertEqual(output.bands, empty.bands)
        XCTAssertEqual(output.highlight, 255)
    }

    func testReducedQuietFirstAndExactRepeatedWindowBoundaries() throws {
        var c = AdaptiveTactileController()
        let input = try packet()
        let times: [(Double, UInt8)] = [(0, 255), (0.1, 255), (0.6, 255), (1.2, 255),
            (1.799999, 255), (1.8, 3), (2.399999, 3), (2.4, 255), (4.199999, 255),
            (4.2, 3), (4.8, 255), (6.6, 3), (7.2, 255)]
        for (time, highlight) in times {
            XCTAssertEqual(apply(&c, input, time).highlight, highlight, "time \(time)")
        }
    }

    func testNonzeroEpochsDoNotMoveDecimalBoundaries() throws {
        let input = try packet()
        for epoch in [0.1, 10, 100.4, 10_000] {
            var c = AdaptiveTactileController()
            XCTAssertEqual(apply(&c, input, epoch).highlight, 255)
            XCTAssertEqual(apply(&c, input, epoch + 1.8).highlight, 3)
            XCTAssertEqual(apply(&c, input, epoch + 2.4).highlight, 255)
        }
    }

    func testColumnAndHighlightedBandChangesStartQuiet() throws {
        for changed in [try packet(highlight: 2), try packet(bands: [0, 2, 3, 4, 4, 0, 0])] {
            var c = AdaptiveTactileController()
            let input = try packet()
            _ = apply(&c, input, 0)
            XCTAssertEqual(apply(&c, input, 1.8).highlight, 3)
            XCTAssertEqual(apply(&c, changed, 1.9).highlight, 255)
            XCTAssertEqual(apply(&c, changed, 3.699999).highlight, 255)
            XCTAssertEqual(apply(&c, changed, 3.7).highlight, changed.highlight)
        }
    }

    func testTargetLossAndReacquisitionCannotRestartAnImmediateTap() throws {
        var c = AdaptiveTactileController()
        let input = try packet(), lost = try packet(highlight: 255)
        _ = apply(&c, input, 0)
        XCTAssertEqual(apply(&c, input, 1.8).highlight, 3)
        XCTAssertEqual(apply(&c, lost, 1.9).highlight, 255)
        XCTAssertEqual(apply(&c, input, 2).highlight, 255)
        XCTAssertEqual(apply(&c, input, 3.8).highlight, 3)
        for step in 0..<40 {
            let alternating = step.isMultiple(of: 2) ? lost : input
            XCTAssertEqual(apply(&c, alternating, 4 + Double(step) / 10).highlight, 255)
        }
    }

    func testOtherColumnChangesAndSequenceRolloverDoNotRestartWindow() throws {
        var c = AdaptiveTactileController()
        _ = apply(&c, try packet(254), 0)
        XCTAssertEqual(apply(&c, try packet(255), 1.8).highlight, 3)
        let wrapped = try packet(0, bands: [1, 4, 0, 2, 2, 1, 4])
        let output = apply(&c, wrapped, 1.9)
        XCTAssertEqual(output, wrapped)
    }

    func testSessionProfileAndExplicitResetRestartQuiet() throws {
        var c = AdaptiveTactileController()
        let input = try packet()
        _ = apply(&c, input, 0)
        XCTAssertEqual(apply(&c, input, 1.8).highlight, 3)
        XCTAssertEqual(apply(&c, input, 1.9, session: "two").highlight, 255)
        XCTAssertEqual(apply(&c, input, 3.7, session: "two").highlight, 3)
        XCTAssertEqual(apply(&c, input, 3.8, .standard, session: "two").highlight, 3)
        XCTAssertEqual(apply(&c, input, 3.9, session: "two").highlight, 255)
        XCTAssertEqual(apply(&c, input, 5.7, session: "two").highlight, 3)
        c.reset()
        XCTAssertEqual(apply(&c, input, 5.8, session: "two").highlight, 255)
        for step in 0..<30 {
            c.reset()
            XCTAssertEqual(apply(&c, input, 6 + Double(step) / 10).highlight, 255)
        }
    }

    func testInvalidAndBackwardClocksSuppressThenRecoverQuiet() throws {
        let input = try packet(255)
        for bad in [Double.nan, .infinity, -.infinity, -1, 9.999] {
            var c = AdaptiveTactileController()
            _ = apply(&c, input, 8.2)
            XCTAssertEqual(apply(&c, input, 10).highlight, 3)
            let invalid = apply(&c, input, bad)
            XCTAssertEqual(invalid.sequence, 255)
            XCTAssertEqual(invalid.bands, input.bands)
            XCTAssertEqual(invalid.highlight, 255)
            XCTAssertEqual(apply(&c, input, 11).highlight, 255)
            XCTAssertEqual(apply(&c, input, 12.8).highlight, 3)
        }
        var standard = AdaptiveTactileController()
        XCTAssertEqual(apply(&standard, input, .nan, .standard).highlight, 255)
        XCTAssertEqual(apply(&standard, input, 1, .standard).highlight, 3)
        XCTAssertEqual(apply(&standard, input, 1, .standard, session: "").highlight, 255)
    }

    func testAutomaticStartsStandardWhenFarAndEntersReducedOnAnyNearColumn() throws {
        let far = try packet()
        for index in 0..<7 {
            var c = AdaptiveTactileController(), bands = far.bands
            XCTAssertEqual(apply(&c, far, 0, .automatic).highlight, 3)
            bands[index] = 1
            let near = try packet(bands: bands)
            XCTAssertEqual(apply(&c, near, 0.1, .automatic).highlight, 255)
            XCTAssertEqual(apply(&c, near, 1.899999, .automatic).highlight, 255)
            XCTAssertEqual(apply(&c, near, 1.9, .automatic).highlight, 3)
        }
    }

    func testAutomaticRequiresContinuousFarHoldoff() throws {
        var c = AdaptiveTactileController()
        let far = try packet(), near = try packet(bands: [1, 2, 3, 2, 4, 0, 0])
        _ = apply(&c, near, 0, .automatic)
        XCTAssertEqual(apply(&c, far, 0.1, .automatic).highlight, 255)
        XCTAssertEqual(apply(&c, near, 0.2, .automatic).highlight, 255)
        XCTAssertEqual(apply(&c, far, 0.3, .automatic).highlight, 255)
        XCTAssertEqual(apply(&c, far, 1.8, .automatic).highlight, 3)
        XCTAssertEqual(apply(&c, far, 2.4, .automatic).highlight, 255)
        XCTAssertEqual(apply(&c, far, 2.699999, .automatic).highlight, 255)
        XCTAssertEqual(apply(&c, far, 2.7, .automatic).highlight, 3)
        XCTAssertEqual(apply(&c, near, 2.8, .automatic).highlight, 255)
    }

    func testNearFarFlickerCannotRestartTapAtEveryPacket() throws {
        var c = AdaptiveTactileController()
        let far = try packet(), near = try packet(bands: [1, 2, 3, 2, 4, 0, 0])
        for tick in 0...72 {
            let input = tick.isMultiple(of: 2) ? near : far
            let output = apply(&c, input, Double(tick) / 10, .automatic)
            let expected: UInt8 = tick % 24 >= 18 ? 3 : 255
            XCTAssertEqual(output.highlight, expected, "tick \(tick)")
            XCTAssertEqual(output.bands, input.bands)
        }
    }

    func testBandAndSequencePreservationAcrossProfilesAndLifecycle() throws {
        for profile in AdaptiveProfile.allCases {
            var c = AdaptiveTactileController()
            for index in 0..<1024 {
                let bands = (0..<7).map { UInt8((index / ($0 + 1) + $0) % 5) }
                let input = try packet(UInt8(truncatingIfNeeded: index), bands: bands, highlight: UInt8(index % 8 == 7 ? 255 : index % 8))
                let time = index.isMultiple(of: 97) ? Double.nan : Double(index) / 10
                let output = apply(&c, input, time, profile, session: index < 512 ? "one" : "two")
                XCTAssertEqual(output.sequence, input.sequence)
                XCTAssertEqual(output.bands, input.bands)
                XCTAssertTrue(output.highlight == 255 || output.highlight == input.effectiveHighlight)
            }
        }
    }
}
