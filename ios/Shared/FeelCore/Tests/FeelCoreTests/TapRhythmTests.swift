import XCTest
@testable import FeelCore

/// Pins that stay the same stop being felt, so steady obstacle pins drop for one frame once a second, timed by the
/// phone within what the servo can do, while target columns keep their own faster taps.
final class TapRhythmTests: XCTestCase {
    private func output(_ bands: [UInt8], target: ClosedRange<Int>? = nil, state: GuidanceState = .live, sequence: UInt8 = 1, highlight: UInt8 = 255) -> EncoderOutput {
        EncoderOutput(packet: try! FeelPacket(sequence: sequence, bands: bands, highlight: highlight), state: state, targetColumns: target)
    }
    /// The 1-based frames, out of `frames` identical ones, on which `column` was dropped.
    private func drops(of column: Int, _ bands: [UInt8], target: ClosedRange<Int>? = nil, highlight: UInt8 = 255, frames: Int, rhythm: inout TapRhythm, animating: Bool = false) -> [Int] {
        var dropped: [Int] = []
        for frame in 1...frames where rhythm.apply(to: output(bands, target: target, highlight: highlight), animating: animating).packet.bands[column] == 0 { dropped.append(frame) }
        return dropped
    }

    func testSteadyObstaclePinsDropTogetherOnceASecondAfterSettling() {
        var rhythm = TapRhythm()
        let scene: [UInt8] = [0, 2, 0, 3, 0, 0, 1]
        var frames: [EncoderOutput] = []
        for _ in 1...40 { frames.append(rhythm.apply(to: output(scene))) }
        let dropped = frames.indices.filter { frames[$0].packet.bands != scene }.map { $0 + 1 }
        XCTAssertEqual(dropped, [20, 30, 40], "one second to settle, then on the beat; a drop lasts one frame")
        XCTAssertEqual(frames[19].packet.bands, [0, 0, 0, 0, 0, 0, 0], "every steady pin drops on the same frame")
        XCTAssertEqual(frames[20].packet.bands, scene, "and is back on the next")
        XCTAssertEqual(frames[0].packet.bands, scene, "a pin that just rose is its own transient")
        XCTAssertEqual(rhythm.frameCount, 40)
    }

    func testAChangedPinSettlesAgainOnItsOwnWhileTheOthersKeepTheBeat() {
        var rhythm = TapRhythm()
        let before: [UInt8] = [0, 2, 0, 3, 0, 0, 0], after: [UInt8] = [0, 3, 0, 3, 0, 0, 0]
        for _ in 1...25 { _ = rhythm.apply(to: output(before)) }
        var column1: [Int] = [], column3: [Int] = []
        for frame in 26...50 {
            let shown = rhythm.apply(to: output(after)).packet.bands
            if shown[1] == 0 { column1.append(frame) }
            if shown[3] == 0 { column3.append(frame) }
        }
        XCTAssertEqual(column3, [30, 40, 50], "unchanged: on the beat throughout")
        XCTAssertEqual(column1, [40, 50], "changed at frame 26: its own rise was felt; it rejoins after settling")
        XCTAssertEqual(rhythm.steadyFrames(column: 1), 24)
    }

    func testTargetColumnsAndTheHighlightedColumnKeepTheirOwnTaps() {
        var rhythm = TapRhythm()
        let scene: [UInt8] = [0, 2, 0, 3, 3, 3, 0]
        for frame in 1...40 {
            let shown = rhythm.apply(to: output(scene, target: 3...5)).packet.bands
            XCTAssertEqual(Array(shown[3...5]), [3, 3, 3], "frame \(frame): the span is the encoder's to tap")
            XCTAssertEqual(shown[1], frame % 10 == 0 && frame >= 20 ? 0 : 2, "frame \(frame): the wall keeps the presence beat")
        }
        var single = TapRhythm()
        XCTAssertEqual(drops(of: 4, [0, 2, 0, 0, 3, 0, 0], highlight: 4, frames: 40, rhythm: &single), [], "the firmware taps the highlighted column")
        var again = TapRhythm()
        XCTAssertEqual(drops(of: 1, [0, 2, 0, 0, 3, 0, 0], highlight: 4, frames: 40, rhythm: &again), [20, 30, 40])
    }

    func testEmptyColumnsAndTheReservedSlotNeverDrop() {
        var rhythm = TapRhythm()
        for frame in 1...40 {
            let shown = rhythm.apply(to: output([0, 0, 0, 0, 0, 0, 0]))
            XCTAssertEqual(shown.packet.bands, [0, 0, 0, 0, 0, 0, 0], "frame \(frame)")
        }
    }

    func testNothingDropsWhileACuePlaysAndPinsSettleAgainAfterwards() {
        var rhythm = TapRhythm()
        let scene: [UInt8] = [0, 2, 0, 3, 0, 0, 0]
        for _ in 1...30 { _ = rhythm.apply(to: output(scene)) }
        XCTAssertEqual(drops(of: 1, scene, frames: 10, rhythm: &rhythm, animating: true), [], "the cue's frames are the motion")
        XCTAssertEqual(rhythm.frameCount, 0, "a cue restarts the rhythm")
        XCTAssertEqual(drops(of: 1, scene, frames: 30, rhythm: &rhythm), [20, 30], "then the pins settle again before tapping")
    }

    func testOnlyLiveAndSimulatedOutputTap() {
        var rhythm = TapRhythm()
        let scene: [UInt8] = [0, 2, 0, 3, 0, 0, 0]
        for state in [GuidanceState.trackingLost, .staleDepth, .stopped, .uncalibrated, .invalidFrame] {
            for _ in 1...30 { XCTAssertEqual(rhythm.apply(to: output(scene, state: state)).packet.bands, scene, "\(state)") }
            XCTAssertEqual(rhythm.frameCount, 0)
        }
        for _ in 1...19 { _ = rhythm.apply(to: output(scene, state: .simulation)) }
        XCTAssertEqual(rhythm.apply(to: output(scene, state: .simulation)).packet.bands, [0, 0, 0, 0, 0, 0, 0], "the simulator shows the taps too")
    }

    func testTheDroppedPacketKeepsSequenceHighlightStateAndTarget() {
        var rhythm = TapRhythm()
        let scene: [UInt8] = [0, 2, 0, 0, 3, 0, 0]
        var last: EncoderOutput?
        for sequence in 1...20 { last = rhythm.apply(to: output(scene, target: 4...4, sequence: UInt8(sequence), highlight: 4)) }
        XCTAssertEqual(last?.packet.bands, [0, 0, 0, 0, 3, 0, 0], "the wall dropped, the highlighted target did not")
        XCTAssertEqual(last?.packet.sequence, 20); XCTAssertEqual(last?.packet.highlight, 4)
        XCTAssertEqual(last?.state, .live); XCTAssertEqual(last?.targetColumns, 4...4)
    }

    func testTheBeatDoesNotSlipWhenTheWireSequenceWraps() {
        var rhythm = TapRhythm()
        let scene: [UInt8] = [0, 2, 0, 0, 0, 0, 0]
        var dropped: [Int] = []
        for frame in 1...300 where rhythm.apply(to: output(scene, sequence: UInt8((frame + 200) % 256))).packet.bands[1] == 0 { dropped.append(frame) }
        XCTAssertEqual(dropped, Array(stride(from: 20, through: 300, by: 10)))
    }

    func testThePeriodNeverGoesBelowWhatTheServoCanFollow() {
        let fast = TapRhythm(settleFrames: -1, period: 1)
        XCTAssertEqual(fast.period, TapRhythm.minimumPeriod); XCTAssertEqual(fast.settleFrames, 0)
        XCTAssertEqual(TapRhythm.minimumPeriod, 3, "a 29° drop and return takes up to about 200 ms under load: the dip frame plus two at rest")
        XCTAssertEqual(Double(TapRhythm().period) * TapRhythm.frameSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(Double(TactileEncoder.groupTapPeriod) * TapRhythm.frameSeconds, 0.6, accuracy: 1e-9, "a target span beats faster than the presence tap")
    }

    func testAnEncodedSpanKeepsTheEncodersBeatAndTheWallGetsThePresenceBeat() {
        let sector = 90.0 / 6
        let target = TargetObservation(bearingDegrees: 0, distance: 2, timestamp: 10, halfWidthDegrees: sector * 1.2)
        var rhythm = TapRhythm()
        var span: [Int] = [], wall: [Int] = []
        for frame in 1...30 {
            let encoded = TactileEncoder.encode(sequence: UInt8(frame), now: 10, frameTimestamp: 10, tracking: true, distances: [nil, 1.0, nil, nil, nil, nil, nil], target: target)
            let shown = rhythm.apply(to: encoded).packet.bands
            if shown[3] == 0 { span.append(frame) }
            if shown[1] == 0 { wall.append(frame) }
        }
        XCTAssertEqual(span, [6, 12, 18, 24, 30], "the encoder's group tap, untouched")
        XCTAssertEqual(wall, [20, 30], "the presence tap, after settling")
    }
}
