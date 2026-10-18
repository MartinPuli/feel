import Foundation

public struct Vector3: Equatable, Codable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x=x; self.y=y; self.z=z }
    public static let zero = Vector3(0,0,0)
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public static func +(a: Self, b: Self) -> Self { Self(a.x+b.x,a.y+b.y,a.z+b.z) }
    public static func -(a: Self, b: Self) -> Self { Self(a.x-b.x,a.y-b.y,a.z-b.z) }
    public static func *(a: Self, b: Double) -> Self { Self(a.x*b,a.y*b,a.z*b) }
    public func dot(_ b: Self) -> Double { x*b.x+y*b.y+z*b.z }
}

public struct CameraPose: Equatable, Codable, Sendable {
    public var position: Vector3, right: Vector3, up: Vector3, back: Vector3
    public init(position: Vector3 = .zero, right: Vector3 = Vector3(1,0,0), up: Vector3 = Vector3(0,1,0), back: Vector3 = Vector3(0,0,1)) {
        self.position=position; self.right=right; self.up=up; self.back=back
    }
    public static let identity = CameraPose()
    public var isValid: Bool {
        position.isFinite && right.isFinite && up.isFinite && back.isFinite &&
        abs(right.dot(right)-1)<0.02 && abs(up.dot(up)-1)<0.02 && abs(back.dot(back)-1)<0.02 &&
        abs(right.dot(up))<0.02 && abs(right.dot(back))<0.02 && abs(up.dot(back))<0.02
    }
    public func worldPoint(camera point: Vector3) -> Vector3 { position + right*point.x + up*point.y + back*point.z }
    public func cameraPoint(world point: Vector3) -> Vector3 {
        let relative=point-position; return Vector3(relative.dot(right),relative.dot(up),relative.dot(back))
    }
}

public struct CameraIntrinsics: Equatable, Codable, Sendable {
    public let fx: Double, fy: Double, cx: Double, cy: Double
    public init(fx: Double, fy: Double, cx: Double, cy: Double) { self.fx=fx; self.fy=fy; self.cx=cx; self.cy=cy }
    public func scaled(x: Double, y: Double) -> Self { Self(fx: fx*x, fy: fy*y, cx: cx*x, cy: cy*y) }
    /// Pixel coordinates in native captured-image orientation, origin top-left.
    /// ARKit camera coordinates have +y up and -z forward.
    public func unproject(x: Double, y: Double, depth: Double) -> Vector3? {
        guard [fx,fy,cx,cy,x,y,depth].allSatisfy(\.isFinite), fx>0,fy>0,depth>0 else { return nil }
        return Vector3((x-cx)*depth/fx,-(y-cy)*depth/fy,-depth)
    }
}

public struct DepthSample: Equatable, Codable, Sendable {
    public let cameraPoint: Vector3
    public let confidence: UInt8
    public init(cameraPoint: Vector3, confidence: UInt8) { self.cameraPoint=cameraPoint; self.confidence=confidence }
}
public enum DepthProjector {
    /// A sector reports the `support`-th nearest confident point, not the nearest: one or two stray
    /// LiDAR pixels cannot raise a pin, while any real surface in the window, even a thin pole,
    /// leaves dozens of samples.
    public static let support = 3
    /// Nearest supported horizontal range per sector. Unknown remains nil, never "clear".
    /// Floor is explicitly calibrated, never assumed to be AR world's y=0.
    public static func sectors(samples: [DepthSample], pose: CameraPose, floorY: Double?, minHeight: Double = 0.6, maxHeight: Double = 2.1, support: Int = support) -> [Double?] {
        var result = [Double?](repeating: nil, count: 7)
        guard pose.isValid, let floorY, floorY.isFinite, minHeight.isFinite,maxHeight.isFinite,minHeight>=0,maxHeight>minHeight else { return result }
        var ranges = [[Double]](repeating: [], count: 7)
        for sample in samples {
            let p=sample.cameraPoint
            guard p.isFinite, sample.confidence >= 1, sample.confidence <= 2,
                  let angle=TactileGeometry.bearing(x:p.x,z:p.z), let column=TactileGeometry.column(bearingDegrees: angle) else { continue }
            let height=pose.worldPoint(camera:p).y-floorY
            guard height >= minHeight, height <= maxHeight else { continue }
            let distance=hypot(p.x,p.z)
            guard distance>0,distance<=4 else { continue }
            ranges[column].append(distance)
        }
        let k=max(1,support)
        for column in 0..<7 where ranges[column].count>=k {
            ranges[column].sort(); result[column]=ranges[column][k-1]
        }
        return result
    }
}

/// Steadies the seven sector ranges from frame to frame so the pins do not flutter with walking
/// bob and LiDAR noise, while staying current: a band change toward the wearer shows after
/// `nearFrames` frames of agreement (band 1, under 0.9 m, after one); a change away from the
/// wearer, or to unknown, needs `farFrames` frames and the range `marginMeters` past the band
/// boundary. Within a band the latest range passes through, so the encoder and replay see real
/// distances. Feed it one depth frame at a time; a repeated frame timestamp returns the last result.
public struct SectorFilter: Sendable {
    public var nearFrames = 2
    public var farFrames = 4
    public var marginMeters = 0.1
    private var shown = [Double?](repeating: nil, count: 7)
    private var candidate = [UInt8](repeating: 0, count: 7)
    private var agreement = [Int](repeating: 0, count: 7)
    private var lastFrame = -Double.infinity
    public init() {}

    public var current: [Double?] { shown }
    public mutating func reset() {
        shown=Array(repeating:nil,count:7); candidate=Array(repeating:0,count:7); agreement=Array(repeating:0,count:7); lastFrame = -.infinity
    }

    public mutating func update(_ distances: [Double?], frameTimestamp: Double) -> [Double?] {
        guard distances.count == 7, frameTimestamp.isFinite else { return shown }
        guard frameTimestamp>lastFrame else { return shown }
        lastFrame=frameTimestamp
        for c in 0..<7 {
            let raw=distances[c].flatMap { $0.isFinite && $0>0 ? $0 : nil }
            let shownBand=shown[c].map { TactileGeometry.band(distance:$0) } ?? 0
            var rawBand=raw.map { TactileGeometry.band(distance:$0) } ?? 0
            // A step away from the wearer must clear the boundary by the margin, or it is noise on the edge.
            if shownBand != 0, let raw, rawBand == 0 || rawBand>shownBand, TactileGeometry.band(distance:raw-marginMeters)<=shownBand, raw-marginMeters<=4 {
                rawBand=shownBand
            }
            if rawBand == shownBand {
                agreement[c]=0
                if let raw, TactileGeometry.band(distance:raw) == shownBand { shown[c]=raw } else if raw == nil, shownBand == 0 { shown[c]=nil }
                continue
            }
            if candidate[c] == rawBand { agreement[c] += 1 } else { candidate[c]=rawBand; agreement[c]=1 }
            let nearer = rawBand != 0 && (shownBand == 0 || rawBand<shownBand)
            let needed = nearer ? (rawBand == 1 ? 1 : nearFrames) : farFrames
            if agreement[c]>=needed { shown[c]=raw; agreement[c]=0 }
        }
        return shown
    }
}

public struct TargetObservation: Equatable, Codable, Sendable {
    public let bearingDegrees: Double, distance: Double, timestamp: Double, confidence: Double
    public let label: String
    /// Half the target's angular width (detection box edges). 0 = a point target, one column.
    public let halfWidthDegrees: Double
    /// A neighbouring column joins the span only if the target covers at least this much of it.
    public static let spanMinOverlapDegrees = 3.0
    public init(bearingDegrees: Double,distance: Double,timestamp: Double,confidence: Double=1,label: String="target",halfWidthDegrees: Double=0) {
        self.bearingDegrees=bearingDegrees; self.distance=distance; self.timestamp=timestamp; self.confidence=confidence; self.label=label
        self.halfWidthDegrees=halfWidthDegrees.isFinite ? max(0,halfWidthDegrees) : 0
    }
    enum CodingKeys: String, CodingKey { case bearingDegrees,distance,timestamp,confidence,label,halfWidthDegrees }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        self.init(bearingDegrees:try c.decode(Double.self,forKey:.bearingDegrees),distance:try c.decode(Double.self,forKey:.distance),
                  timestamp:try c.decode(Double.self,forKey:.timestamp),confidence:try c.decode(Double.self,forKey:.confidence),
                  label:try c.decode(String.self,forKey:.label),halfWidthDegrees:try c.decodeIfPresent(Double.self,forKey:.halfWidthDegrees) ?? 0)
    }
    public func valid(at now: Double) -> Bool {
        now.isFinite && timestamp.isFinite && now>=timestamp && now-timestamp<=0.5 && confidence.isFinite && confidence>=0.5 && confidence<=1 &&
        TactileGeometry.column(bearingDegrees:bearingDegrees) != nil && TactileGeometry.band(distance:distance)>0
    }
    /// Columns the target covers, clipped to the field. Always contains the centre column.
    public var columns: ClosedRange<Int>? {
        guard let center=TactileGeometry.column(bearingDegrees:bearingDegrees) else { return nil }
        let reach=halfWidthDegrees-Self.spanMinOverlapDegrees
        guard reach>0 else { return center...center }
        let low=TactileGeometry.column(bearingDegrees:max(-45,bearingDegrees-reach)) ?? center
        let high=TactileGeometry.column(bearingDegrees:min(45,bearingDegrees+reach)) ?? center
        return min(low,center)...max(high,center)
    }
}

public enum GuidanceState: String, Codable, Sendable { case live, trackingLost, staleDepth, invalidFrame, uncalibrated, stopped, simulation }
public struct EncoderOutput: Equatable, Sendable {
    public let packet: FeelPacket
    public let state: GuidanceState
    /// Columns showing the target (nil without a valid target). One column uses the firmware tap;
    /// several tap together, timed by the phone.
    public let targetColumns: ClosedRange<Int>?
    public init(packet: FeelPacket,state: GuidanceState,targetColumns: ClosedRange<Int>?=nil) { self.packet=packet; self.state=state; self.targetColumns=targetColumns }
}
public enum TactileEncoder {
    /// A multi-column target drops its pins for one packet in every `groupTapPeriod` (100 ms per 600 ms
    /// at 10 Hz), matching the firmware's single-column tap rhythm. No firmware or protocol change.
    public static let groupTapPeriod = 6
    public static func encode(sequence: UInt8, now: Double, frameTimestamp: Double, tracking: Bool, distances: [Double?], target: TargetObservation?=nil, floorCalibrated: Bool=true) -> EncoderOutput {
        func neutral(_ state: GuidanceState) -> EncoderOutput { .init(packet:.neutral(sequence:sequence),state:state) }
        guard tracking else { return neutral(.trackingLost) }
        guard floorCalibrated else { return neutral(.uncalibrated) }
        guard distances.count == 7, now.isFinite,frameTimestamp.isFinite,now>=frameTimestamp else { return neutral(.invalidFrame) }
        guard now-frameTimestamp<=0.250 else { return neutral(.staleDepth) }
        var bands=distances.map { $0.map { TactileGeometry.band(distance:$0) } ?? 0 }
        var highlight: UInt8=255
        var span: ClosedRange<Int>?
        if let target, target.valid(at:now), let columns=target.columns {
            let targetBand=TactileGeometry.band(distance:target.distance)
            // Preserve a closer obstacle. Target tapping indicates bearing, not an obstacle-free route.
            for column in columns { bands[column] = bands[column] == 0 ? targetBand : min(bands[column],targetBand) }
            span=columns
            if columns.count == 1 { if bands[columns.lowerBound]>0 { highlight=UInt8(columns.lowerBound) } }
            else if Int(sequence) % groupTapPeriod == 0 { for column in columns { bands[column]=0 } }
        }
        return .init(packet:try! FeelPacket(sequence:sequence,bands:bands,highlight:highlight),state:.live,targetColumns:span)
    }
}

public enum TargetSelector {
    public static func best(_ observations: [TargetObservation], at now: Double) -> TargetObservation? {
        observations.filter { $0.valid(at:now) }.sorted {
            if $0.confidence != $1.confidence { return $0.confidence>$1.confidence }
            if $0.distance != $1.distance { return $0.distance<$1.distance }
            return $0.bearingDegrees<$1.bearingDegrees
        }.first
    }
}

/// Short-lived object detection cache, not a user bookmark. Store world coordinates
/// so a camera turn never reuses an old camera-relative direction.
public struct CapturedTarget: Equatable, Sendable {
    public let position:Vector3, timestamp:Double, confidence:Double, label:String
    /// Half the physical width of the detection box at its depth, so the span stays right as the user moves.
    public let halfWidthMeters:Double
    public init(position:Vector3,timestamp:Double,confidence:Double=1,label:String="target",halfWidthMeters:Double=0) {
        self.position=position; self.timestamp=timestamp; self.confidence=confidence; self.label=label
        self.halfWidthMeters=halfWidthMeters.isFinite ? max(0,halfWidthMeters) : 0
    }
    public func observation(pose:CameraPose,now:Double) -> TargetObservation? {
        guard pose.isValid,position.isFinite else { return nil }
        let point=pose.cameraPoint(world:position)
        guard let bearing=TactileGeometry.bearing(x:point.x,z:point.z) else { return nil }
        let distance=hypot(point.x,point.z)
        let halfWidth=distance>0 ? atan2(halfWidthMeters,distance)*180 / .pi : 0
        let result=TargetObservation(bearingDegrees:bearing,distance:distance,timestamp:timestamp,confidence:confidence,label:label,halfWidthDegrees:halfWidth)
        return result.valid(at:now) ? result : nil
    }
}
