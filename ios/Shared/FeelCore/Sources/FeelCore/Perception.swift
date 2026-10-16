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
    /// Nearest positive horizontal range per sector. Unknown remains nil, never "clear".
    /// Floor is explicitly calibrated, never assumed to be AR world's y=0.
    public static func sectors(samples: [DepthSample], pose: CameraPose, floorY: Double?, minHeight: Double = 0.6, maxHeight: Double = 2.1) -> [Double?] {
        var result = [Double?](repeating: nil, count: 7)
        guard pose.isValid, let floorY, floorY.isFinite, minHeight.isFinite,maxHeight.isFinite,minHeight>=0,maxHeight>minHeight else { return result }
        for sample in samples {
            let p=sample.cameraPoint
            guard p.isFinite, sample.confidence >= 1, sample.confidence <= 2,
                  let angle=TactileGeometry.bearing(x:p.x,z:p.z), let column=TactileGeometry.column(bearingDegrees: angle) else { continue }
            let height=pose.worldPoint(camera:p).y-floorY
            guard height >= minHeight, height <= maxHeight else { continue }
            let distance=hypot(p.x,p.z)
            guard distance>0,distance<=4 else { continue }
            result[column]=min(result[column] ?? .infinity,distance)
        }
        return result
    }
}

public struct TargetObservation: Equatable, Codable, Sendable {
    public let bearingDegrees: Double, distance: Double, timestamp: Double, confidence: Double
    public let label: String
    public init(bearingDegrees: Double,distance: Double,timestamp: Double,confidence: Double=1,label: String="target") {
        self.bearingDegrees=bearingDegrees; self.distance=distance; self.timestamp=timestamp; self.confidence=confidence; self.label=label
    }
    public func valid(at now: Double) -> Bool {
        now.isFinite && timestamp.isFinite && now>=timestamp && now-timestamp<=0.5 && confidence.isFinite && confidence>=0.5 && confidence<=1 &&
        TactileGeometry.column(bearingDegrees:bearingDegrees) != nil && TactileGeometry.band(distance:distance)>0
    }
}

public enum GuidanceState: String, Codable, Sendable { case live, trackingLost, staleDepth, invalidFrame, uncalibrated, stopped, simulation }
public struct EncoderOutput: Equatable, Sendable {
    public let packet: FeelPacket
    public let state: GuidanceState
    public init(packet: FeelPacket,state: GuidanceState) { self.packet=packet; self.state=state }
}
public enum TactileEncoder {
    public static func encode(sequence: UInt8, now: Double, frameTimestamp: Double, tracking: Bool, distances: [Double?], target: TargetObservation?=nil, floorCalibrated: Bool=true) -> EncoderOutput {
        func neutral(_ state: GuidanceState) -> EncoderOutput { .init(packet:.neutral(sequence:sequence),state:state) }
        guard tracking else { return neutral(.trackingLost) }
        guard floorCalibrated else { return neutral(.uncalibrated) }
        guard distances.count == 7, now.isFinite,frameTimestamp.isFinite,now>=frameTimestamp else { return neutral(.invalidFrame) }
        guard now-frameTimestamp<=0.250 else { return neutral(.staleDepth) }
        var bands=distances.map { $0.map { TactileGeometry.band(distance:$0) } ?? 0 }
        var highlight: UInt8=255
        if let target, target.valid(at:now), let column=TactileGeometry.column(bearingDegrees:target.bearingDegrees) {
            let targetBand=TactileGeometry.band(distance:target.distance)
            // Preserve a closer obstacle. Target tapping indicates bearing, not an obstacle-free route.
            bands[column] = bands[column] == 0 ? targetBand : min(bands[column],targetBand)
            if bands[column]>0 { highlight=UInt8(column) }
        }
        return .init(packet:try! FeelPacket(sequence:sequence,bands:bands,highlight:highlight),state:.live)
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
    public init(position:Vector3,timestamp:Double,confidence:Double=1,label:String="target") { self.position=position; self.timestamp=timestamp; self.confidence=confidence; self.label=label }
    public func observation(pose:CameraPose,now:Double) -> TargetObservation? {
        guard pose.isValid,position.isFinite else { return nil }
        let point=pose.cameraPoint(world:position)
        guard let bearing=TactileGeometry.bearing(x:point.x,z:point.z) else { return nil }
        let result=TargetObservation(bearingDegrees:bearing,distance:hypot(point.x,point.z),timestamp:timestamp,confidence:confidence,label:label)
        return result.valid(at:now) ? result : nil
    }
}
