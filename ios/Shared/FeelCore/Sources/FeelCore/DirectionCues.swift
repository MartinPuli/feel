import Foundation

/// One-shot tactile arrows, drawn on the 7×4 pins at 100 ms per frame using ordinary
/// nine-byte packets (no firmware or protocol change). Rows: 1 wrist … 4 fingers, so
/// "forward" runs toward the fingers. Each frame raises at most one pin per column.
/// Untested on hardware: pin return speed decides whether a cue feels like motion.
public enum DirectionCue: Equatable, Sendable {
    case straight
    /// Slight turn toward a column (0…6, never the centre).
    case bear(column: Int)
    case turnLeft, turnRight, turnAround, arrived

    public static let center = 3
    /// Within this straight-line distance of the target the cue is "arrived".
    public static let arriveMeters = 1.0

    /// Classifies a route bearing. Thresholds widen by 5° in favour of `previous`, so a
    /// bearing sitting on a boundary does not flip between two cues.
    public static func classify(_ hint: RouteHint, previous: DirectionCue?) -> DirectionCue? {
        guard hint.status == .route, hint.bearingDegrees.isFinite, hint.targetDistance.isFinite else { return nil }
        if hint.targetDistance <= arriveMeters { return .arrived }
        var straightMax=15.0, bearMax=50.0, turnMax=135.0
        switch previous {
        case .straight?: straightMax += 5
        case .bear?: straightMax -= 5; bearMax += 5
        case .turnLeft?, .turnRight?: bearMax -= 5; turnMax += 5
        case .turnAround?: turnMax -= 5
        default: break
        }
        let b=hint.bearingDegrees, m=abs(b)
        if m<=straightMax { return .straight }
        if m<=bearMax {
            let column=TactileGeometry.column(bearingDegrees:max(-45,min(45,b))) ?? center
            return .bear(column: column != center ? column : (b>0 ? center+1 : center-1))
        }
        if m<=turnMax { return b>0 ? .turnRight : .turnLeft }
        return .turnAround
    }

    /// True when replaying would tell the wearer something new. Small drifts of a slight turn are not.
    public func noticeablyDifferent(from other: DirectionCue?) -> Bool {
        guard let other else { return true }
        if case .bear(let a)=self, case .bear(let b)=other { return abs(a-b)>=2 || (a<Self.center) != (b<Self.center) }
        return self != other
    }

    public var spoken: String {
        switch self {
        case .straight: return "Straight ahead"
        case .bear(let c): return c>Self.center ? "Bear right" : "Bear left"
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .turnAround: return "Turn around"
        case .arrived: return "You're there"
        }
    }

    public var frames: [[UInt8]] {
        func frame(_ raised: [Int: UInt8]) -> [UInt8] { (0..<7).map { raised[$0] ?? 0 } }
        /// A dot runs along the finger row, each pin up for two frames.
        func sweep(to column: Int) -> [[UInt8]] {
            let path=Array(stride(from:Self.center,through:column,by:column>Self.center ? 1 : -1))
            return (0...path.count).map { k in
                var raised: [Int: UInt8]=[:]
                if k<path.count { raised[path[k]]=4 }
                if k>=1 { raised[path[k-1]]=4 }
                return frame(raised)
            }
        }
        let c=Self.center
        switch self {
        case .straight:
            // A V that grows outward, tip toward the fingers: 1 2 3 4 3 2 1.
            let grow=(0...3).map { k in frame(Dictionary(uniqueKeysWithValues:(0..<7).filter { abs($0-c)<=k }.map { ($0,UInt8(4-abs($0-c))) })) }
            return grow+[grow[3]]
        case .bear(let column):
            return sweep(to:column)
        case .turnLeft, .turnRight:
            // ↰ / ↱: the centre pin climbs wrist to fingers, then runs sideways.
            let stem=(UInt8(1)...4).map { frame([c:$0]) }
            return stem+sweep(to:self == .turnRight ? 6 : 0).dropFirst()
        case .turnAround:
            // The middle columns step back from fingers to wrist.
            return (UInt8(1)...4).reversed().map { b in frame([c-1:b,c:b,c+1:b]) }
        case .arrived:
            // Two short pulses of the middle columns.
            let up=frame([c-1:4,c:4,c+1:4]), down=frame([:])
            return [up,down,up,down]
        }
    }
}

/// Plays one cue once over the normal packets. An obstacle within 0.9 m (band 1) holds the cue
/// back; it restarts from the beginning if the obstacle clears within `holdSeconds`, else it is dropped.
public struct CuePlayer: Sendable {
    public var frameSeconds = 0.1
    public var holdSeconds = 2.0
    public private(set) var playing: DirectionCue?
    private var frames: [[UInt8]]=[]
    private var start: Double?
    private var heldSince: Double?
    public init() {}

    public var isAnimating: Bool { playing != nil && start != nil }
    public mutating func reset() { playing=nil; frames=[]; start=nil; heldSince=nil }
    public mutating func play(_ cue: DirectionCue, now: Double) {
        playing=cue; frames=cue.frames; start=now.isFinite ? now : nil; heldSince=nil
    }

    public mutating func apply(to output: EncoderOutput, now: Double) -> EncoderOutput {
        guard playing != nil else { return output }
        guard output.state == .live || output.state == .simulation, now.isFinite else { reset(); return output }
        if output.packet.bands.contains(1) {
            if heldSince==nil { heldSince=now }
            start=nil
            if now-heldSince!>holdSeconds { reset() }
            return output
        }
        if start==nil || now<start! { start=now; heldSince=nil }
        // Round so 10 Hz timer jitter neither repeats nor skips frames.
        let index=Int(((now-start!)/frameSeconds).rounded())
        guard index<frames.count else { reset(); return output }
        return EncoderOutput(packet:try! FeelPacket(sequence:output.packet.sequence,bands:frames[index]),state:output.state)
    }
}

public enum GuideEvent: Equatable, Sendable {
    /// The sign started guidance and this cue plays.
    case started(DirectionCue)
    /// The route changed noticeably.
    case changed(DirectionCue)
    /// The sign was made again during guidance.
    case repeated(DirectionCue)
    case arrived
    /// The sign was made but no target is in view.
    case noTarget
    /// A target is in view but the mapped area has no way through.
    case noRoute
    /// The target has been out of view too long; guidance ended.
    case lost
}

/// Decides when a cue plays: when the wearer makes the sign, and afterwards only when the
/// route changes noticeably and the new direction has held for `stableSeconds`. Never repeats
/// a cue on its own. Ends on arrival or when no fresh route has arrived for `lostSeconds`.
public struct DirectionGuide: Sendable {
    public var stableSeconds = 0.8
    public var minIntervalSeconds = 1.5
    public var lostSeconds = 3.0
    public var hintMaxAge = 1.0
    public private(set) var active = false
    public private(set) var lastPlayed: DirectionCue?
    private var lastPlayAt = -Double.infinity
    private var candidate: DirectionCue?
    private var candidateSince = 0.0
    private var lastFresh = 0.0
    private var reportedBlocked = false
    public init() {}

    public mutating func reset() {
        active=false; lastPlayed=nil; lastPlayAt = -.infinity; candidate=nil; reportedBlocked=false
    }

    public mutating func update(now: Double, sign: Bool, hint: RouteHint?) -> (play: DirectionCue?, events: [GuideEvent]) {
        guard now.isFinite else { return (nil,[]) }
        let fresh=hint.flatMap { now>=$0.timestamp && now-$0.timestamp<=hintMaxAge ? $0 : nil }
        let cue=fresh.flatMap { DirectionCue.classify($0,previous:candidate ?? lastPlayed) }
        func playNow(_ c: DirectionCue, _ event: GuideEvent) -> (DirectionCue?,[GuideEvent]) {
            lastPlayed=c; lastPlayAt=now; candidate=c; candidateSince=now
            if c == .arrived { active=false; return (c,[.arrived]) }
            return (c,[event])
        }
        if sign {
            if let cue {
                let wasActive=active; active=true; lastFresh=now; reportedBlocked=false
                return playNow(cue,wasActive ? .repeated(cue) : .started(cue))
            }
            if fresh?.status == .blocked { active=true; lastFresh=now; reportedBlocked=true; candidate=nil; return (nil,[.noRoute]) }
            return (nil,[.noTarget])
        }
        guard active else { return (nil,[]) }
        guard fresh != nil else {
            if now-lastFresh>=lostSeconds-1e-6 { reset(); return (nil,[.lost]) }
            return (nil,[])
        }
        lastFresh=now
        guard let cue else {
            if !reportedBlocked { reportedBlocked=true; candidate=nil; return (nil,[.noRoute]) }
            return (nil,[])
        }
        if cue.noticeablyDifferent(from:candidate) { candidate=cue; candidateSince=now }
        // A route that reappears after being blocked is news even if the direction is the same.
        let news=candidate!.noticeablyDifferent(from:lastPlayed) || reportedBlocked
        // Small tolerance so 10 Hz ticks landing exactly on a threshold count.
        if news, now-candidateSince>=stableSeconds-1e-6, now-lastPlayAt>=minIntervalSeconds-1e-6 {
            reportedBlocked=false
            return playNow(candidate!,.changed(candidate!))
        }
        return (nil,[])
    }
}
