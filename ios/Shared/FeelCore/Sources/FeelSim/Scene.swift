import Foundation
import FeelCore

/// A synthetic world for deterministic replay: floor at y = 0, axis-aligned boxes and vertical
/// cylinders (optionally moving), a chest camera following keyframes, and an ideal-geometry LiDAR
/// with optional noise and outliers. It models geometry, not real sensor behaviour.
public struct SceneSpec: Codable, Sendable {
    public struct Key: Codable, Sendable { public var t: Double, x: Double, z: Double; public var yaw: Double? }
    public struct Object: Codable, Sendable {
        /// "box" (min/max corners) or "cylinder" (vertical: center [x, z], radius, height, optional base).
        public var kind: String
        public var min: [Double]?, max: [Double]?
        public var center: [Double]?, radius: Double?, height: Double?, base: Double?
        /// Metres per second in x and z, starting at `from` (or 0).
        public var velocity: [Double]?
        public var from: Double?, to: Double?
        public var label: String?
    }
    public struct Target: Codable, Sendable {
        public var position: [Double]
        public var label: String?
        public var halfWidth: Double?
        public var confidence: Double?
        public var from: Double?, to: Double?
        /// Detector cadence and inference time, as in ARPerception (≥ 0.35 s between runs, one in flight).
        public var period: Double?, latency: Double?
    }
    public struct Sensor: Codable, Sendable {
        /// Gaussian depth noise as a fraction of range (0.005 = 0.5 %).
        public var noise: Double?
        /// Fraction of pixels replaced by a random range with `outlierConfidence`.
        public var outlierRate: Double?, outlierConfidence: Int?
        public var maxRange: Double?
        public var seed: UInt64?
    }
    public var duration: Double
    public var frameRate: Double?
    public var cameraHeight: Double?
    /// Positive tilts the camera up.
    public var pitch: Double?
    public var path: [Key]
    public var objects: [Object]?
    public var target: Target?
    public var sensor: Sensor?
    /// [from, to] intervals with ARKit tracking limited.
    public var trackingLost: [[Double]]?
    /// [from, to] intervals with no frames delivered at all.
    public var frameGaps: [[Double]]?
    public var floorCalibrated: Bool?
    /// Depth-map resolution and full-resolution intrinsics (iPhone wide camera, 1920 × 1440 by default).
    public var depthSize: [Int]?
    public var imageSize: [Double]?
    public var focal: Double?
}

public enum SceneError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String { switch self { case .invalid(let s): return "Invalid scene: \(s)" } }
}

public struct SceneRenderer {
    public let spec: SceneSpec
    private var rng: SplitMix64

    public init(_ spec: SceneSpec) throws {
        guard spec.duration.isFinite, spec.duration>0, spec.duration<=600 else { throw SceneError.invalid("duration must be 0–600 s") }
        guard !spec.path.isEmpty, spec.path.allSatisfy({ $0.t.isFinite && $0.x.isFinite && $0.z.isFinite }) else { throw SceneError.invalid("path needs finite keyframes") }
        guard zip(spec.path,spec.path.dropFirst()).allSatisfy({ $0.t<$1.t }) else { throw SceneError.invalid("path keyframe times must increase") }
        for (i,o) in (spec.objects ?? []).enumerated() {
            switch o.kind {
            case "box": guard o.min?.count == 3, o.max?.count == 3, zip(o.min!,o.max!).allSatisfy({ $0<$1 }) else { throw SceneError.invalid("object \(i): box needs min < max, 3 values each") }
            case "cylinder": guard o.center?.count == 2, (o.radius ?? 0)>0, (o.height ?? 0)>0 else { throw SceneError.invalid("object \(i): cylinder needs center [x,z], radius, height") }
            default: throw SceneError.invalid("object \(i): kind must be box or cylinder")
            }
            if let v=o.velocity, v.count != 2 { throw SceneError.invalid("object \(i): velocity is [vx, vz]") }
        }
        if let target=spec.target, target.position.count != 3 { throw SceneError.invalid("target position is [x, y, z]") }
        self.spec=spec; rng=SplitMix64(seed:spec.sensor?.seed ?? 1)
    }

    var cameraHeight: Double { spec.cameraHeight ?? 1.2 }
    var depthWidth: Int { spec.depthSize?.first ?? 256 }
    var depthHeight: Int { spec.depthSize?.last ?? 192 }
    /// Intrinsics scaled to the depth map, as ARPerception does.
    var intrinsics: CameraIntrinsics {
        let image=spec.imageSize ?? [1920,1440], f=spec.focal ?? 1445
        return CameraIntrinsics(fx:f,fy:f,cx:image[0]/2,cy:image[1]/2).scaled(x:Double(depthWidth)/image[0],y:Double(depthHeight)/image[1])
    }

    public func pose(at t: Double) -> CameraPose {
        let keys=spec.path
        var x=keys[0].x, z=keys[0].z, yaw=keys[0].yaw ?? 0
        if t>=keys[keys.count-1].t { x=keys.last!.x; z=keys.last!.z; yaw=keys.last!.yaw ?? 0 }
        else if t>keys[0].t, let i=keys.firstIndex(where:{ $0.t>t }) {
            let a=keys[i-1], b=keys[i], u=(t-a.t)/(b.t-a.t)
            x=a.x+(b.x-a.x)*u; z=a.z+(b.z-a.z)*u; yaw=(a.yaw ?? 0)+((b.yaw ?? 0)-(a.yaw ?? 0))*u
        }
        // yaw 0 faces -z; positive yaw turns right (toward +x).
        let r=yaw * .pi/180, p=(spec.pitch ?? 0) * .pi/180
        let forward=Vector3(sin(r),0,-cos(r)), right=Vector3(cos(r),0,sin(r)), worldUp=Vector3(0,1,0)
        let f=forward*cos(p)+worldUp*sin(p), up=worldUp*cos(p)-forward*sin(p)
        return CameraPose(position:Vector3(x,cameraHeight,z),right:right,up:up,back:f*(-1))
    }

    static func inside(_ t: Double, _ intervals: [[Double]]?) -> Bool { (intervals ?? []).contains { $0.count == 2 && t>=$0[0] && t<$0[1] } }

    /// All frames at the scene's frame rate, with the detector modelled as ARPerception runs it.
    public mutating func render(info: RecordingInfo? = nil) throws -> Data {
        var data=try SessionRecording.start(info ?? RecordingInfo(source:"synthetic",createdAt:"deterministic",cameraHeight:cameraHeight))
        let dt=1/(spec.frameRate ?? 10)
        var detector=DetectorModel(target:spec.target)
        var frameIndex=0
        while true {
            let t=Double(frameIndex)*dt; frameIndex += 1
            if t>spec.duration+1e-9 { break }
            if Self.inside(t,spec.frameGaps) { continue }
            let pose=pose(at:t)
            let tracking = !Self.inside(t,spec.trackingLost)
            var frame=RecordedFrame(timestamp:t,trackingNormal:tracking,pose:pose,floorY:spec.floorCalibrated == false ? nil : 0,depth:nil)
            if tracking {
                frame.depth=depthMap(pose:pose,t:t)
                frame.target=detector.step(t:t,pose:pose,renderer:self)
            } else { detector.invalidate() }
            data.append(try SessionRecording.encode(frame))
        }
        return data
    }

    mutating func depthMap(pose: CameraPose, t: Double) -> DepthFrame {
        let w=depthWidth, h=depthHeight, k=intrinsics
        let sensor=spec.sensor, maxRange=sensor?.maxRange ?? 5, noise=sensor?.noise ?? 0, outliers=sensor?.outlierRate ?? 0
        var depths=[Float](repeating:0,count:w*h), confidence=[UInt8](repeating:0,count:w*h)
        let shapes=activeShapes(at:t)
        for y in 0..<h {
            for x in 0..<w {
                let dx=(Double(x)-k.cx)/k.fx, dy=(Double(y)-k.cy)/k.fy
                // Camera ray (dx, -dy, -1) in world space; parameter = depth along the optical axis.
                let dir=pose.right*dx+pose.up*(-dy)+pose.back*(-1)
                var depth=Self.hit(origin:pose.position,dir:dir,shapes:shapes) ?? .infinity
                var conf: UInt8
                if depth>maxRange { depth=maxRange; conf=0 }
                else {
                    conf=depth<=3 ? 2 : depth<=4.5 ? 1 : 0
                    if noise>0 { depth=max(0.01,depth*(1+noise*rng.gaussian())) }
                }
                if outliers>0, rng.unit()<outliers { depth=0.3+rng.unit()*(maxRange-0.3); conf=UInt8(clamping:sensor?.outlierConfidence ?? 1) }
                depths[y*w+x]=Float(depth); confidence[y*w+x]=conf
            }
        }
        return DepthFrame(width:w,height:h,depths:depths,confidence:confidence,intrinsics:k)!
    }

    enum Shape { case box(Vector3,Vector3), cylinder(Double,Double,Double,Double,Double) }
    func activeShapes(at t: Double) -> [Shape] {
        (spec.objects ?? []).compactMap { o in
            if let from=o.from, t<from { return nil }; if let to=o.to, t>to { return nil }
            let v=o.velocity ?? [0,0], s=t-(o.from ?? 0), ox=v[0]*s, oz=v[1]*s
            if o.kind == "box", let a=o.min, let b=o.max { return .box(Vector3(a[0]+ox,a[1],a[2]+oz),Vector3(b[0]+ox,b[1],b[2]+oz)) }
            if let c=o.center, let r=o.radius, let height=o.height { let base=o.base ?? 0; return .cylinder(c[0]+ox,c[1]+oz,r,base,base+height) }
            return nil
        }
    }

    /// Nearest positive ray parameter over the floor and every shape.
    static func hit(origin o: Vector3, dir d: Vector3, shapes: [Shape]) -> Double? {
        var best = Double.infinity
        if d.y<0, o.y>0 { best = -o.y/d.y }
        for shape in shapes {
            switch shape {
            case .box(let lo,let hi):
                var t0 = -Double.infinity, t1 = Double.infinity, ok=true
                for (oc,dc,l,h) in [(o.x,d.x,lo.x,hi.x),(o.y,d.y,lo.y,hi.y),(o.z,d.z,lo.z,hi.z)] {
                    if abs(dc)<1e-12 { if oc<l || oc>h { ok=false; break }; continue }
                    var a=(l-oc)/dc, b=(h-oc)/dc; if a>b { swap(&a,&b) }
                    t0=max(t0,a); t1=min(t1,b); if t0>t1 { ok=false; break }
                }
                if ok, t1>0 { let t=t0>0 ? t0 : t1; best=min(best,t) }
            case .cylinder(let cx,let cz,let r,let y0,let y1):
                let px=o.x-cx, pz=o.z-cz, a=d.x*d.x+d.z*d.z
                if a>1e-12 {
                    let b=2*(px*d.x+pz*d.z), c=px*px+pz*pz-r*r, disc=b*b-4*a*c
                    if disc>=0 {
                        let s=disc.squareRoot()
                        for t in [(-b-s)/(2*a),(-b+s)/(2*a)] where t>0 {
                            let y=o.y+d.y*t; if y>=y0, y<=y1 { best=min(best,t); break }
                        }
                    }
                }
                for capY in [y0,y1] where abs(d.y)>1e-12 {
                    let t=(capY-o.y)/d.y
                    if t>0 { let x=o.x+d.x*t-cx, z=o.z+d.z*t-cz; if x*x+z*z<=r*r { best=min(best,t) } }
                }
            }
        }
        return best.isFinite ? best : nil
    }

    /// Ground-truth visibility for the detector: inside the camera's horizontal view, ≤ 4 m, unoccluded.
    func targetVisible(_ position: Vector3, pose: CameraPose, t: Double) -> Bool {
        let p=pose.cameraPoint(world:position)
        guard p.z<0 else { return false }
        let k=intrinsics, x=k.cx+p.x/(-p.z)*k.fx, y=k.cy-p.y/(-p.z)*k.fy
        guard x>=0, x<Double(depthWidth), y>=0, y<Double(depthHeight), hypot(p.x,p.z)<=4 else { return false }
        let dir=position-pose.position, along = -p.z
        let scaled=dir*(1/along)
        if let hit=Self.hit(origin:pose.position,dir:scaled,shapes:activeShapes(at:t)), hit<along-0.05 { return false }
        return true
    }
}

/// ARPerception's detector timing: a run starts on a frame ≥ `period` after the last start when none
/// is in flight; its result replaces the cached target `latency` later; a tracking loss drops it.
struct DetectorModel {
    let target: SceneSpec.Target?
    var lastStart = -Double.infinity
    var inFlight: (start: Double, result: CapturedTarget?)?
    var cached: CapturedTarget?
    init(target: SceneSpec.Target?) { self.target=target }
    mutating func invalidate() { cached=nil; inFlight=nil }
    mutating func step(t: Double, pose: CameraPose, renderer: SceneRenderer) -> CapturedTarget? {
        guard let target else { return nil }
        let latency=target.latency ?? 0.1, period=target.period ?? 0.35
        if let flight=inFlight, t+1e-9>=flight.start+latency {
            // The app keeps a result only if it is still fresh when inference completes.
            cached = latency<=0.5 ? flight.result : nil; inFlight=nil
        }
        let returned=cached
        if inFlight == nil, t-lastStart>=period-1e-9 {
            lastStart=t
            let position=Vector3(target.position[0],target.position[1],target.position[2])
            let live=(target.from.map { t>=$0 } ?? true) && (target.to.map { t<=$0 } ?? true)
            let seen=live && renderer.targetVisible(position,pose:pose,t:t)
            inFlight=(t,seen ? CapturedTarget(position:position,timestamp:t,confidence:target.confidence ?? 0.9,label:target.label ?? "target",halfWidthMeters:target.halfWidth ?? 0) : nil)
        }
        return returned
    }
}

/// Small deterministic generator so a seed gives the same frames on every platform.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state=seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z=state; z=(z ^ (z>>30)) &* 0xBF58476D1CE4E5B9; z=(z ^ (z>>27)) &* 0x94D049BB133111EB; return z ^ (z>>31)
    }
    mutating func unit() -> Double { Double(next()>>11) / Double(1<<53) }
    mutating func gaussian() -> Double { let u=max(unit(),1e-300), v=unit(); return (-2*log(u)).squareRoot()*cos(2 * .pi*v) }
}
