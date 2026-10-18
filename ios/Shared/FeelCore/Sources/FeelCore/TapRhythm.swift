import Foundation

/// Why steady pins tap. A pin is felt when it rises, then fades: steady skin pressure is carried by slowly adapting
/// afferents whose firing, and the felt intensity with it, decay exponentially within seconds. What keeps being
/// felt is change. So an obstacle pin that has stayed the same drops to its gap for one frame and comes back, all
/// steady pins together, once a second: a reminder rather than a buzz (the presence tap). Target columns are left
/// alone here: a one-column target is tapped by the firmware (the highlight byte, 13° toward the gap for 100 ms of
/// every 600 ms) and a span by the encoder (every span column dropped for one packet in six), so what points at
/// something already beats faster than the presence tap, and the arrows (DirectionCue) move every 100 ms.
///
/// Servo budget: a FEETECH FS0307 turns 60° in about 0.10 s with no load, and a drop commands the nearest gap,
/// 29° away, so one drop is about 50 ms each way unloaded and up to twice that under the cam: a dropped frame is
/// back up within about 200 ms. The shortest period allowed leaves every pin at rest for two frames between drops.
/// Pure and deterministic; the phone applies it to the final packet of every 100 ms tick, after cues and highlights.
public struct TapRhythm: Equatable, Sendable {
    /// One packet per frame, 100 ms.
    public static let frameSeconds = 0.1
    /// The dip frame plus two frames for the servo to come back and settle.
    public static let minimumPeriod = 3
    /// A pin whose band has not changed for this many frames (1 s) has faded: it joins the presence taps.
    public let settleFrames: Int
    /// Every steady obstacle pin drops for one frame, all together, every this many frames (1 Hz).
    public let period: Int

    private var frame = 0
    /// Frames each column has shown its current band; 0 on the frame it changed.
    private var steady = [Int](repeating: 0, count: 7)
    private var lastBands = [UInt8](repeating: 0, count: 7)

    public init(settleFrames: Int = 10, period: Int = 10) {
        self.settleFrames = max(0, settleFrames)
        self.period = max(Self.minimumPeriod, period)
    }

    /// Frames since the rhythm started or restarted; drops fall on multiples of `period`.
    public var frameCount: Int { frame }
    /// Frames column `column` has shown its current band.
    public func steadyFrames(column: Int) -> Int { steady.indices.contains(column) ? steady[column] : 0 }

    public mutating func reset() {
        frame = 0; steady = [Int](repeating: 0, count: 7); lastBands = [UInt8](repeating: 0, count: 7)
    }

    /// The packet to send this frame. `output` is the tick's final output (obstacles, target columns, highlight);
    /// `animating` is true while a cue plays, whose frames are motion already. Anything but live sensing or the
    /// simulation, or a playing cue, restarts the rhythm, so pins settle again afterwards. Target columns and the
    /// highlighted column are never dropped here: their own taps are faster.
    public mutating func apply(to output: EncoderOutput, animating: Bool = false) -> EncoderOutput {
        guard output.state == .live || output.state == .simulation, !animating else { reset(); return output }
        let bands = output.packet.bands
        frame += 1
        for column in bands.indices { steady[column] = bands[column] == lastBands[column] ? steady[column] + 1 : 0 }
        lastBands = bands
        guard frame % period == 0 else { return output }
        let targets = output.targetColumns.map { Set($0) } ?? []
        let highlighted = Int(output.packet.effectiveHighlight)
        var dropped = bands
        for column in bands.indices where bands[column] > 0 && PuckLayout.activeColumns.contains(column)
            && !targets.contains(column) && column != highlighted && steady[column] >= settleFrames {
            dropped[column] = 0
        }
        guard dropped != bands else { return output }
        let packet = try! FeelPacket(sequence: output.packet.sequence, bands: dropped, highlight: output.packet.highlight)
        return EncoderOutput(packet: packet, state: output.state, targetColumns: output.targetColumns)
    }
}
