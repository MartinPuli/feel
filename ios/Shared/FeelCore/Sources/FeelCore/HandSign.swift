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
    public static let extendedRatio = 1.45
    public static let foldedRatio = 1.35
    /// Angle between the index and middle fingers, and their tip gap relative to palm length.
    public static let minSpreadDegrees = 12.0
    public static let minTipGapOfPalm = 0.3
    /// Palm length (wrist to middle MCP) of an adult hand, used for a size-based range estimate.
    public static let palmLengthMeters = 0.095
    /// Only hands this close count, so bystanders' hands cannot request guidance.
    public static let maxDistanceMeters = 0.9

    /// Knuckle spacing (index to middle MCP) is about this fraction of the palm length; it stands in for
    /// the palm when the wrist is out of frame, which is the normal case for a hand close to the lens.
    public static let knuckleSpanOfPalm = 0.22

    public static func isVSign(_ hand: HandJoints) -> Bool {
        guard let middleMCP=hand.middle.mcp, let indexMCP=hand.index.mcp else { return false }
        let palm: Double
        if let wrist=hand.wrist { palm=wrist.distance(to:middleMCP) } else { palm=indexMCP.distance(to:middleMCP)/knuckleSpanOfPalm }
        guard palm.isFinite, palm>1 else { return false }
        // With the wrist in frame, the original wrist-relative ratios. Without it, each finger is judged
        // from its own joints: straight when the tip is well beyond the PIP, folded when the tip stays near the PIP.
        func ratio(_ f: HandJoints.Finger) -> Double? {
            guard let mcp=f.mcp, let tip=f.tip else { return nil }
            if let wrist=hand.wrist {
                let base=wrist.distance(to:mcp)
                return base>0 ? wrist.distance(to:tip)/base : nil
            }
            guard let pip=f.pip else { return nil }
            let base=mcp.distance(to:pip)
            // Map onto the same scale as the wrist ratios: a straight finger reads about 1.9, a folded one about 1.1.
            return base>0 ? 1+mcp.distance(to:tip)/base*0.45 : nil
        }
        // A hand close to the lens often has its folded fingers out of frame: a missing ring or little
        // finger counts as folded. The two extended fingers must still be fully visible.
        guard let index=ratio(hand.index), let middle=ratio(hand.middle),
              index>=extendedRatio, middle>=extendedRatio,
              (ratio(hand.ring) ?? 0)<=foldedRatio, (ratio(hand.little) ?? 0)<=foldedRatio else { return false }
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
        guard focalPixels.isFinite, focalPixels>0 else { return nil }
        if let w=hand.wrist, let m=hand.middle.mcp {
            let pixels=w.distance(to:m)
            return pixels>1 ? focalPixels*palmLengthMeters/pixels : nil
        }
        // Wrist out of frame: range from the knuckle spacing instead.
        guard let i=hand.index.mcp, let m=hand.middle.mcp else { return nil }
        let pixels=i.distance(to:m)
        return pixels>1 ? focalPixels*palmLengthMeters*knuckleSpanOfPalm/pixels : nil
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
    public var holdSeconds = 0.4
    public var minDetections = 2
    /// A gap longer than this between detections restarts the hold. The detector shares a queue with the
    /// pointing detector and runs every 0.15 to 0.5 s on a phone, and the pose can flicker for a frame.
    public var maxGapSeconds = 0.7
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
