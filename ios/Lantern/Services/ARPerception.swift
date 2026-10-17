import Foundation
import ARKit
import CoreVideo
import FeelCore

/// A distinct target of the selected kind that is in view now.
struct VisibleCandidate {
    let position: Vector3
    let observation: TargetObservation
}

struct PerceptionFrame {
    let epoch:Int
    let finderEpoch:Int
    let timestamp: TimeInterval
    let tracking: Bool
    let distances: [Double?]
    let target: TargetObservation?
    let pose: CameraPose
    let floorY: Double?
    /// Route to the currently visible target over the local floor grid; nil without one.
    var routeHint: RouteHint? = nil
    /// Distinct targets of the selected kind in view, left to right.
    var candidates: [VisibleCandidate] = []
}

/// The AR delegate queue owns all mutable perception state. Vision has one in-flight
/// request; its originating frame and depth remain paired until completion.
final class ARPerception: NSObject, ARSessionDelegate {
    let session=ARSession()
    var onFrame: ((PerceptionFrame)->Void)?
    var onInvalidated: ((Int)->Void)?
    var onStatus: ((String)->Void)?
    var onModelStatus: ((String,Bool)->Void)?
    /// Point-to-describe observations, tagged with the session epoch.
    var onPointing: ((Int,PointingObservation)->Void)?
    /// V-sign checks, tagged with the session epoch. Skipped while the puck's codes are in view.
    var onHandSign: ((Int,HandSignObservation)->Void)?
    private let queue=DispatchQueue(label:"feel.arkit",qos:.userInitiated)
    private let visionQueue=DispatchQueue(label:"feel.vision",qos:.userInitiated)
    private let pointingQueue=DispatchQueue(label:"feel.pointing",qos:.userInitiated)
    private lazy var pointingDetector=PointingDetector()
    private lazy var handSignDetector=HandSignDetector()
    /// Floor map of the current surroundings; reset with the session or calibration.
    private var grid=FloorGrid()
    private var lastPlan: TimeInterval = -.infinity
    private var lastHint: RouteHint?
    /// Explicit world goal from two-finger pointing. While set, routes go there instead of the visible target.
    private var routeGoal: (point: Vector3, label: String)?
    /// Distinct detections from the latest Vision pass (≥ 1 m apart).
    private var candidates: [CapturedTarget] = []
    /// When set, guidance follows the detection nearest this point instead of the most confident.
    private var lockPosition: Vector3?
    private var pointingBusy=false
    private var lastPointing: TimeInterval = -.infinity
    private lazy var detector=ObjectDetector()
    private var floorY: Double?
    private var sessionEpoch=0
    private var earliestFrame:TimeInterval = 0
    private var finder: FinderMode = .none
    private var finderEpoch=0
    private var generation=0
    private var lastProcessed: TimeInterval = -.infinity
    private var lastVision: TimeInterval = -.infinity
    private var visionBusy=false
    private var lastTarget: CapturedTarget?
    /// Optional depth recording for offline replay; idle unless the user turns it on.
    let recorder=SessionRecorder()
    override init() {
        super.init(); session.delegate=self; session.delegateQueue=queue
        visionQueue.async { [weak self] in
            guard let self else { return }
            let status=self.detector.modelStatus, available=self.detector.model != nil
            DispatchQueue.main.async { self.onModelStatus?(status,available) }
        }
    }
    @discardableResult func start(epoch:Int) -> Bool {
        guard ARWorldTrackingConfiguration.isSupported,ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else { publishStatus("Live sensing requires a LiDAR iPhone or iPad. Use Simulation for software replay."); return false }
        queue.async {
            self.sessionEpoch=epoch; self.earliestFrame=ProcessInfo.processInfo.systemUptime
            self.floorY=nil; self.lastTarget=nil; self.generation += 1; self.lastProcessed = -.infinity
            self.grid.reset(); self.lastHint=nil; self.candidates=[]; self.lockPosition=nil; self.routeGoal=nil
            let config=ARWorldTrackingConfiguration(); config.frameSemantics=[.sceneDepth]; config.worldAlignment = .gravity
            self.session.run(config,options:[.resetTracking,.removeExistingAnchors]); self.publishStatus("Move slowly, then calibrate measured camera height")
        }
        return true
    }
    func stop() {
        queue.async { self.session.pause(); self.generation += 1; self.lastTarget=nil; self.floorY=nil; self.grid.reset(); self.lastHint=nil; self.candidates=[]; self.lockPosition=nil; self.routeGoal=nil; self.publishStatus("Stopped") }
    }
    func setFinder(_ mode: FinderMode,epoch:Int) { queue.async { self.finder=mode; self.finderEpoch=epoch; self.lastTarget=nil; self.lastHint=nil; self.candidates=[]; self.lockPosition=nil; self.routeGoal=nil; self.generation += 1 } }
    /// Route to a fixed world point (two fingers on a puck column) until cleared with nil.
    func setRouteGoal(_ point: Vector3?, label: String = "") {
        queue.async { self.routeGoal=point.map { ($0,label) }; self.lastHint=nil; self.lastPlan = -.infinity }
    }
    /// Follow the target nearest `position` (one of several in view) until the finder changes.
    func lockTarget(at position: Vector3) {
        queue.async {
            self.lockPosition=position
            self.lastTarget=Self.nearest(self.candidates,to:position)
            self.lastHint=nil; self.lastPlan = -.infinity
        }
    }
    private static func flatDistance(_ a: Vector3,_ b: Vector3) -> Double { hypot(a.x-b.x,a.z-b.z) }
    private static func nearest(_ targets: [CapturedTarget],to point: Vector3) -> CapturedTarget? {
        targets.filter { flatDistance($0.position,point)<=1.5 }.min { flatDistance($0.position,point)<flatDistance($1.position,point) }
    }
    func calibrate(cameraHeight: Double) {
        queue.async {
            guard cameraHeight.isFinite,cameraHeight>=0.6,cameraHeight<=2.1,let frame=self.session.currentFrame,case .normal=frame.camera.trackingState,ProcessInfo.processInfo.systemUptime-frame.timestamp<=0.25 else { self.publishStatus("Calibration needs fresh normal tracking and camera height 0.6–2.1 m"); return }
            let pose=Self.pose(frame.camera.transform)
            guard Self.mountValid(pose) else { self.publishStatus("Hold camera landscape-left, upright and facing forward"); return }
            // Heights in the floor map depend on the floor level, so start the map again.
            self.floorY=pose.position.y-cameraHeight; self.grid.reset(); self.lastHint=nil; self.publishStatus("Floor calibrated from measured camera height")
        }
    }
    private static func mountValid(_ pose: CameraPose) -> Bool { DepthFrameProcessor.mountValid(pose) }
    private static func pose(_ matrix: simd_float4x4) -> CameraPose {
        func v(_ p: SIMD4<Float>) -> Vector3 { Vector3(Double(p.x),Double(p.y),Double(p.z)) }
        return CameraPose(position:v(matrix.columns.3),right:v(matrix.columns.0),up:v(matrix.columns.1),back:v(matrix.columns.2))
    }
    private func publishStatus(_ status: String) { DispatchQueue.main.async { self.onStatus?(status) } }
    private func publish(_ frame: PerceptionFrame) { DispatchQueue.main.async { self.onFrame?(frame) } }
    func session(_ session: ARSession,didUpdate frame: ARFrame) {
        guard frame.timestamp>=earliestFrame,frame.timestamp-lastProcessed>=0.095 else { return }; lastProcessed=frame.timestamp
        let pose=Self.pose(frame.camera.transform)
        // Runs even while tracking is limited: a puck held close to the lens may degrade it.
        if !pointingBusy,frame.timestamp-lastPointing>=0.15 {
            pointingBusy=true; lastPointing=frame.timestamp
            let image=frame.capturedImage,timestamp=frame.timestamp,epoch=sessionEpoch
            let focal=Double(frame.camera.intrinsics.columns.0.x)
            pointingQueue.async {
                let observation=self.pointingDetector.analyze(pixelBuffer:image,timestamp:timestamp)
                // Same image, same queue: one retained frame. The puck's codes in view mean point-to-describe.
                let sign=observation.codesSeen==0 ? self.handSignDetector.analyze(pixelBuffer:image,timestamp:timestamp,focalPixels:focal) : nil
                self.queue.async { self.pointingBusy=false }
                DispatchQueue.main.async {
                    self.onPointing?(epoch,observation)
                    if let sign { self.onHandSign?(epoch,sign) }
                }
            }
        }
        let normal: Bool; if case .normal=frame.camera.trackingState { normal=true } else { normal=false }
        guard normal,Self.mountValid(pose),let depth=frame.sceneDepth,let map=DepthFrame(depth,camera:frame.camera) else {
            if recorder.isActive { recorder.append(RecordedFrame(timestamp:frame.timestamp,trackingNormal:normal,pose:pose,floorY:floorY,depth:nil)) }
            lastTarget=nil; lastHint=nil; candidates=[]; generation += 1
            publish(PerceptionFrame(epoch:sessionEpoch,finderEpoch:finderEpoch,timestamp:frame.timestamp,tracking:false,distances:Array(repeating:nil,count:7),target:nil,pose:pose,floorY:floorY))
            publishStatus(normal ? "Depth missing or mounting orientation invalid — guidance neutral" : "Tracking uncertain — guidance neutral")
            return
        }
        let k=map.intrinsics
        // Shared with offline replay (simulation/run.py), so recordings score exactly what the app computes.
        if recorder.isActive { recorder.append(RecordedFrame(timestamp:frame.timestamp,trackingNormal:true,pose:pose,floorY:floorY,target:lastTarget,depth:map)) }
        let processed=DepthFrameProcessor.process(map,pose:pose,floorY:floorY)
        let distances=processed.distances
        let target=lastTarget?.observation(pose:pose,now:frame.timestamp)
        if let floorY { grid.integrate(points:processed.mapPoints,floorY:floorY,camera:pose.position) }
        // A pointing goal is a fixed world point, so it needs no target in view. Otherwise route only
        // to a target that is in view right now. Either way, a few times a second.
        if let goal=routeGoal {
            if floorY != nil, frame.timestamp-lastPlan>=0.4 {
                lastPlan=frame.timestamp
                lastHint=RouteHint.make(path:grid.route(from:pose.position,to:goal.point),pose:pose,target:goal.point,timestamp:frame.timestamp,label:goal.label)
            }
        }
        else if target == nil { lastHint=nil }
        else if let goal=lastTarget, floorY != nil, frame.timestamp-lastPlan>=0.4 {
            lastPlan=frame.timestamp
            lastHint=RouteHint.make(path:grid.route(from:pose.position,to:goal.position),pose:pose,target:goal.position,timestamp:frame.timestamp,label:goal.label)
        }
        var published=PerceptionFrame(epoch:sessionEpoch,finderEpoch:finderEpoch,timestamp:frame.timestamp,tracking:true,distances:distances,target:target,pose:pose,floorY:floorY)
        published.routeHint=lastHint
        published.candidates=candidates.compactMap { c in c.observation(pose:pose,now:frame.timestamp).map { VisibleCandidate(position:c.position,observation:$0) } }
            .sorted { $0.observation.bearingDegrees<$1.observation.bearingDegrees }
        publish(published)
        guard finder != .none,finder != .teammate,!visionBusy,frame.timestamp-lastVision>=0.35 else { return }
        visionBusy=true; lastVision=frame.timestamp
        let mode=finder,token=generation,image=frame.capturedImage,timestamp=frame.timestamp
        visionQueue.async {
            let detections: [ImageDetection]; let failure: String?
            do { detections=try self.detector.detect(pixelBuffer:image,mode:mode); failure=nil }
            catch { detections=[]; failure="Detection unavailable: \(error.localizedDescription)" }
            let targets=detections.compactMap { detection -> CapturedTarget? in
                let x=Double(detection.box.midX)*Double(map.width),y=(1-Double(detection.box.midY))*Double(map.height)
                guard let depth=map.medianDepth(x:x,y:y),let point=k.unproject(x:x,y:y,depth:depth),let bearing=TactileGeometry.bearing(x:point.x,z:point.z) else { return nil }
                guard TactileGeometry.column(bearingDegrees:bearing) != nil else { return nil }
                // Box edges at the centre's depth give the target's width, so it can span columns.
                let halfWidth: Double
                if let left=k.unproject(x:Double(detection.box.minX)*Double(map.width),y:y,depth:depth),
                   let right=k.unproject(x:Double(detection.box.maxX)*Double(map.width),y:y,depth:depth) { halfWidth=hypot(right.x-left.x,right.z-left.z)/2 } else { halfWidth=0 }
                return CapturedTarget(position:pose.worldPoint(camera:point),timestamp:timestamp,confidence:detection.confidence,label:detection.label,halfWidthMeters:halfWidth)
            }
            self.queue.async {
                self.visionBusy=false
                guard token==self.generation else { return }
                let now=ProcessInfo.processInfo.systemUptime
                // Several of the same kind (two exits) stay separate if at least 1 m apart.
                var distinct: [CapturedTarget]=[]
                for t in targets.filter({ $0.observation(pose:pose,now:now) != nil }).sorted(by: { $0.confidence > $1.confidence })
                where !distinct.contains(where: { Self.flatDistance($0.position,t.position)<1.0 }) { distinct.append(t) }
                self.candidates=distinct
                if let lock=self.lockPosition {
                    // Never jump to a different one: losing the chosen target means no target.
                    self.lastTarget=Self.nearest(distinct,to:lock)
                    if let kept=self.lastTarget { self.lockPosition=kept.position }
                } else { self.lastTarget=distinct.first }
                if let failure { self.publishStatus(failure) }
            }
        }
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
    private func invalidate() {
        lastTarget=nil; floorY=nil; grid.reset(); lastHint=nil; candidates=[]; lockPosition=nil; routeGoal=nil; generation += 1
        let epoch=sessionEpoch
        DispatchQueue.main.async { self.onInvalidated?(epoch) }
    }
    func sessionWasInterrupted(_ session: ARSession) { invalidate(); publishStatus("AR interrupted — recalibrate after restart") }
    func sessionInterruptionEnded(_ session: ARSession) { _=start(epoch:sessionEpoch) }
    func session(_ session: ARSession,didFailWithError error: Error) { invalidate(); publishStatus("AR error: \(error.localizedDescription)") }
}

extension DepthFrame {
    /// Copies ARKit's Float32 depth and confidence maps; intrinsics are scaled to the depth resolution.
    init?(_ data: ARDepthData, camera: ARCamera) {
        let map=data.depthMap
        guard CVPixelBufferGetPixelFormatType(map)==kCVPixelFormatType_DepthFloat32,let confidenceMap=data.confidenceMap else { return nil }
        let width=CVPixelBufferGetWidth(map), height=CVPixelBufferGetHeight(map)
        guard CVPixelBufferGetWidth(confidenceMap)==width,CVPixelBufferGetHeight(confidenceMap)==height else { return nil }
        CVPixelBufferLockBaseAddress(map,.readOnly); CVPixelBufferLockBaseAddress(confidenceMap,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map,.readOnly); CVPixelBufferUnlockBaseAddress(confidenceMap,.readOnly) }
        guard let base=CVPixelBufferGetBaseAddress(map),let confidenceBase=CVPixelBufferGetBaseAddress(confidenceMap) else { return nil }
        var values:[Float]=[]; var confidences:[UInt8]=[]; values.reserveCapacity(width*height); confidences.reserveCapacity(width*height)
        for y in 0..<height {
            let row=base.advanced(by:y*CVPixelBufferGetBytesPerRow(map)).assumingMemoryBound(to:Float.self)
            let confidenceRow=confidenceBase.advanced(by:y*CVPixelBufferGetBytesPerRow(confidenceMap)).assumingMemoryBound(to:UInt8.self)
            for x in 0..<width { values.append(row[x]); confidences.append(confidenceRow[x]) }
        }
        let raw=camera.intrinsics
        let k=CameraIntrinsics(fx:Double(raw.columns.0.x),fy:Double(raw.columns.1.y),cx:Double(raw.columns.2.x),cy:Double(raw.columns.2.y))
            .scaled(x:Double(width)/Double(camera.imageResolution.width),y:Double(height)/Double(camera.imageResolution.height))
        self.init(width:width,height:height,depths:values,confidence:confidences,intrinsics:k)
    }
}
