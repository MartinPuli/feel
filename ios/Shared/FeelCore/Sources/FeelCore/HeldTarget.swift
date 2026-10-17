import Foundation

/// Everything a Where-is lookup needs from one camera frame, captured together so the
/// photo, the depth and the pose describe the same instant.
public struct FrameSnapshot: Sendable {
    public let timestamp: Double, worldEpoch: Int, pose: CameraPose, intrinsics: CameraIntrinsics, depth: DepthGrid, jpegBase64: String
    public init(timestamp: Double, worldEpoch: Int, pose: CameraPose, intrinsics: CameraIntrinsics, depth: DepthGrid, jpegBase64: String) {
        self.timestamp = timestamp; self.worldEpoch = worldEpoch; self.pose = pose; self.intrinsics = intrinsics; self.depth = depth; self.jpegBase64 = jpegBase64
    }
}

/// A target placed once in world coordinates and re-expressed against the current pose
/// every tick. It belongs to one ARKit world (`worldEpoch`); a tracking reset ends it.
public struct HeldTarget: Equatable, Sendable {
    public static let reachedRadius = 0.5
    public let position: Vector3, label: String, worldEpoch: Int, setAt: Double
    public init(position: Vector3, label: String, worldEpoch: Int, setAt: Double) {
        self.position = position; self.label = label; self.worldEpoch = worldEpoch; self.setAt = setAt
    }
    /// Full-circle bearing (0 ahead, left negative, ±180 behind) and horizontal range.
    public func relative(pose: CameraPose) -> (bearingDegrees: Double, horizontalDistance: Double)? {
        guard pose.isValid, position.isFinite else { return nil }
        let point = pose.cameraPoint(world: position)
        let distance = hypot(point.x, point.z)
        guard distance.isFinite else { return nil }
        return (atan2(point.x, -point.z) * 180 / .pi, distance)
    }
    /// The encoder's target for this tick, stamped `now`. Nil whenever the puck cannot show it.
    public func observation(pose: CameraPose, now: Double, worldEpoch: Int) -> TargetObservation? {
        guard worldEpoch == self.worldEpoch, let relative = relative(pose: pose) else { return nil }
        let observation = TargetObservation(bearingDegrees: relative.bearingDegrees, distance: relative.horizontalDistance, timestamp: now, confidence: 1, label: label)
        return observation.valid(at: now) ? observation : nil
    }
    public func reached(pose: CameraPose) -> Bool {
        (relative(pose: pose)?.horizontalDistance ?? .infinity) < Self.reachedRadius
    }
    /// Spoken only when the pins cannot point: outside ±45°, or ahead but beyond 4 m.
    public func spokenDirection(pose: CameraPose) -> String? {
        guard let relative = relative(pose: pose) else { return nil }
        let bearing = relative.bearingDegrees, distance = relative.horizontalDistance
        if abs(bearing) <= 45 { return distance > 4 ? "\(label) ahead, about \(Int(distance.rounded())) meters." : nil }
        if abs(bearing) > 135 { return "\(label) is behind you." }
        return bearing < 0 ? "\(label) is to your left." : "\(label) is to your right."
    }
}

public enum WhereIsPlacement {
    /// Box centre → depth pixel → median LiDAR depth → camera point → world point.
    /// Nil when nothing was found or the depth there is unusable (glass, beyond range).
    public static func place(answer: WhereIsAnswer, snapshot: FrameSnapshot) -> HeldTarget? {
        guard answer.found, let box = answer.box else { return nil }
        let centre = box.center
        let x = centre.x * Double(snapshot.depth.width), y = centre.y * Double(snapshot.depth.height)
        guard let depth = snapshot.depth.medianDepth(x: x, y: y),
              let point = snapshot.intrinsics.unproject(x: x, y: y, depth: depth) else { return nil }
        return HeldTarget(position: snapshot.pose.worldPoint(camera: point), label: answer.label, worldEpoch: snapshot.worldEpoch, setAt: snapshot.timestamp)
    }
}
