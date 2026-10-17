import Foundation

/// 2D hand joints in image pixels (any orientation). Missing or low-confidence joints are nil.
public struct HandJoints: Equatable, Sendable {
    public struct Finger: Equatable, Sendable {
        public var mcp: PlanePoint?, pip: PlanePoint?, tip: PlanePoint?
        public init(mcp: PlanePoint?, pip: PlanePoint?, tip: PlanePoint?) { self.mcp=mcp; self.pip=pip; self.tip=tip }
    }
    public var wrist: PlanePoint?
    public var index: Finger, middle: Finger, ring: Finger, little: Finger
    public init(wrist: PlanePoint?, index: Finger, middle: Finger, ring: Finger, little: Finger) {
        self.wrist=wrist; self.index=index; self.middle=middle; self.ring=ring; self.little=little
    }
}

/// The "V" request sign: index and middle fingers straight and spread, ring and little
/// fingers folded. Uses only distances and angles between joints, so it works with the
/// hand upright, sideways or upside down. Fingers pointing at the lens look short and are
/// rejected, which fails safe (no request).
public enum HandSign {
    /// Tip-to-wrist over MCP-to-wrist. A straight finger is about 1.8–2.0, a folded one below 1.1.
    public static let extendedRatio = 1.55
    public static let foldedRatio = 1.25
    /// Angle between the index and middle fingers, and their tip gap relative to palm length.
    public static let minSpreadDegrees = 12.0
    public static let minTipGapOfPalm = 0.3
    /// Palm length (wrist to middle MCP) of an adult hand, used for a size-based range estimate.
    public static let palmLengthMeters = 0.095
    /// Only hands this close count, so bystanders' hands cannot request guidance.
    public static let maxDistanceMeters = 0.55

    public static func isVSign(_ hand: HandJoints) -> Bool {
        guard let wrist=hand.wrist, let middleMCP=hand.middle.mcp else { return false }
        let palm=wrist.distance(to:middleMCP)
        guard palm.isFinite, palm>1 else { return false }
        func ratio(_ f: HandJoints.Finger) -> Double? {
            guard let mcp=f.mcp, let tip=f.tip else { return nil }
            let base=wrist.distance(to:mcp)
            return base>0 ? wrist.distance(to:tip)/base : nil
        }
        guard let index=ratio(hand.index), let middle=ratio(hand.middle),
              let ring=ratio(hand.ring), let little=ratio(hand.little),
              index>=extendedRatio, middle>=extendedRatio, ring<=foldedRatio, little<=foldedRatio else { return false }
        // Both extended fingers must be straight: tip beyond the PIP, away from the MCP.
        for f in [hand.index, hand.middle] {
            guard let mcp=f.mcp, let pip=f.pip, let tip=f.tip, mcp.distance(to:tip)>mcp.distance(to:pip)*1.3 else { return false }
        }
        guard let im=hand.index.mcp, let it=hand.index.tip, let mm=hand.middle.mcp, let mt=hand.middle.tip else { return false }
        let a=atan2(it.y-im.y,it.x-im.x), b=atan2(mt.y-mm.y,mt.x-mm.x)
        var spread=abs(a-b)*180 / .pi; if spread>180 { spread=360-spread }
        return spread>=minSpreadDegrees && spread<=70 && it.distance(to:mt)>=minTipGapOfPalm*palm
    }

    /// Range from apparent palm size: focal length in pixels times real size over pixel size.
    public static func estimatedDistance(_ hand: HandJoints, focalPixels: Double) -> Double? {
        guard let w=hand.wrist, let m=hand.middle.mcp, focalPixels.isFinite, focalPixels>0 else { return nil }
        let pixels=w.distance(to:m)
        return pixels>1 ? focalPixels*palmLengthMeters/pixels : nil
    }
}

/// One hand-sign check of one camera frame.
public struct HandSignObservation: Equatable, Sendable {
    public let timestamp: Double
    public let vSign: Bool
    public let distance: Double?
    public init(timestamp: Double, vSign: Bool, distance: Double?) { self.timestamp=timestamp; self.vSign=vSign; self.distance=distance }
    /// A V sign close enough to be the wearer's own hand.
    public var counts: Bool { vSign && (distance.map { $0>0 && $0<=HandSign.maxDistanceMeters } ?? false) }
}

/// Fires once when the sign is held, then waits for the hand to go away before it can fire again.
public struct HandSignTrigger: Sendable {
    public var holdSeconds = 0.5
    public var minDetections = 3
    /// A gap longer than this between detections restarts the hold.
    public var maxGapSeconds = 0.4
    /// The sign must be absent this long before it can fire again.
    public var releaseSeconds = 0.8
    public private(set) var holding = false
    private var holdStart: Double?
    private var lastSeen: Double?
    private var detections = 0
    private var fired = false
    public init() {}

    public mutating func reset() { holdStart=nil; lastSeen=nil; detections=0; fired=false; holding=false }

    /// Returns true exactly once per deliberate hold.
    public mutating func update(_ o: HandSignObservation) -> Bool {
        let t=o.timestamp
        guard t.isFinite else { return false }
        if let last=lastSeen, t<last { reset() }
        if o.counts {
            if let last=lastSeen, t-last>maxGapSeconds { holdStart=nil; detections=0 }
            if holdStart==nil { holdStart=t }
            lastSeen=t; detections += 1; holding=true
            if !fired, detections>=minDetections, t-holdStart!>=holdSeconds { fired=true; return true }
            return false
        }
        holding=false
        if let last=lastSeen, t-last>=releaseSeconds { holdStart=nil; lastSeen=nil; detections=0; fired=false }
        else if !fired, let last=lastSeen, t-last>maxGapSeconds { holdStart=nil; detections=0 }
        return false
    }
}
