import Foundation

/// Which way has the most room, from the six active sector ranges in seven wire slots the pins already show. The finder
/// prefers the side with the widest clearance over fleeing the nearest obstacle, so a wall dead
/// ahead gives one steady "more room to your left" instead of a cue that flips with range jitter.
/// It never calls a direction clear: unknown sectors count as no room, and the result is relative.
public struct OpenSide: Equatable, Sendable {
    public enum Side: String, Equatable, Sendable { case left, ahead, right }
    /// Column with the most room, 1 (left) … 6 (right), after the width filter.
    public let column: Int
    public let side: Side
    /// Nearest range in the centre two columns, metres.
    public let aheadRange: Double
    /// 0 while the way ahead is open; 1 with something at or inside `OpenSideFinder.nearLimit`.
    public let urgency: Double
    /// How much more room the best column has than the centre, metres.
    public let advantage: Double

    public init(column: Int, side: Side, aheadRange: Double, urgency: Double, advantage: Double) {
        self.column = column; self.side = side; self.aheadRange = aheadRange; self.urgency = urgency; self.advantage = advantage
    }

    /// A short relative statement; never "clear" or "safe".
    public var spoken: String {
        switch side {
        case .ahead: return "No more room to either side."
        case .left: return "More room to your left."
        case .right: return "More room to your right."
        }
    }
}

public struct OpenSideFinder: Sendable {
    /// Something nearer than this ahead makes the finder speak; the pins' second row ends here too.
    public var aheadLimit = 1.6
    /// Urgency reaches 1 here.
    public var nearLimit = 0.3
    /// A side must have at least this much more room than the centre to be named.
    public var minAdvantage = 0.5
    /// Another column must beat the current one by this much before the side changes.
    public var switchMargin = 0.4
    /// Time constant of the per-column smoothing, seconds.
    public var smoothingSeconds = 0.6
    /// Ranges beyond the pins' reach count as this much room.
    public var farRange = 4.0

    private var smoothed: [Double] = []
    private var lastTime: Double?
    private var currentColumn: Int?

    public init() {}

    public mutating func reset() { smoothed = []; lastTime = nil; currentColumn = nil }

    /// Call once per live frame with the six active sector ranges in seven wire slots (nil means unknown, never room).
    /// Returns nil while the way ahead is open beyond `aheadLimit` or unknown.
    public mutating func update(distances: [Double?], now: Double) -> OpenSide? {
        guard distances.count == 7, now.isFinite else { reset(); return nil }
        if let lastTime, now < lastTime { reset() }
        let raw = distances.map { range -> Double in
            guard let range, range.isFinite, range > 0 else { return 0 }
            return min(range, farRange)
        }
        // A person is wider than one sector: a column has only as much room as its neighbours.
        let room = (0..<7).map { column -> Double in
            guard PuckLayout.activeColumns.contains(column) else { return 0 }
            var value = raw[column]
            if column > 1 { value = min(value, raw[column - 1]) }
            if column < 6 { value = min(value, raw[column + 1]) }
            return value
        }
        if let lastTime, smoothed.count == 7, now - lastTime <= 1 {
            let alpha = 1 - exp(-(now - lastTime) / smoothingSeconds)
            smoothed = zip(smoothed, room).map { $0 + ($1 - $0) * alpha }
        } else {
            smoothed = room
        }
        lastTime = now
        guard let ahead = (3...4).compactMap({ distances[$0] }).filter({ $0.isFinite && $0 > 0 }).min(),
              ahead < aheadLimit else { currentColumn = nil; return nil }
        let linear = min(1, max(0, (aheadLimit - ahead) / (aheadLimit - nearLimit)))
        var best = 3
        for column in [3, 4, 2, 5, 1, 6] where smoothed[column] > smoothed[best] { best = column }
        if let current = currentColumn, current != best, smoothed[best] - smoothed[current] < switchMargin { best = current }
        let advantage = max(0, smoothed[best] - max(smoothed[3], smoothed[4]))
        let side: OpenSide.Side = (best == 3 || best == 4) || advantage < minAdvantage ? .ahead : best < 3 ? .left : .right
        if side == .ahead { best = 3 }
        currentColumn = best
        return OpenSide(column: best, side: side, aheadRange: ahead, urgency: pow(linear, 0.6), advantage: side == .ahead ? 0 : advantage)
    }
}
