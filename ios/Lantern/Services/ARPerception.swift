import Foundation
import ARKit
import CoreImage
import CoreVideo
import ImageIO
import FeelCore

/// A distinct target of the selected kind that is in view now.
struct VisibleCandidate {
    let position: Vector3
    let observation: TargetObservation
}

struct PerceptionFrame {
    let epoch:Int
    let finderEpoch:Int
    /// Increments on every tracking reset; a held target from an older world is stale.
    let worldEpoch:Int
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
    /// Printed FEEL room tags recognized by ARKit image detection, tagged with the session epoch. The frame is the
    /// tag's image anchor in the current world; room memory places remembered targets through it.
    var onTag: ((Int,TagSighting)->Void)?
    /// The printed width ARKit is told. ios/Lantern/Resources/feel-tag-01.png must be printed exactly this wide,
    /// or every remembered target lands at the wrong distance.
    static let roomTagWidthMetres=0.20
    /// The tags shipped in the bundle (ios/scripts/make_room_tag.py draws them), named by tag id.
    private static let roomTags: Set<ARReferenceImage>={
        var tags: Set<ARReferenceImage>=[]
        for name in ["feel-tag-01"] {
            guard let url=Bundle.main.url(forResource:name,withExtension:"png"),let source=CGImageSourceCreateWithURL(url as CFURL,nil),
                  let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { continue }
            let tag=ARReferenceImage(image,orientation:.up,physicalWidth:CGFloat(roomTagWidthMetres)); tag.name=name; tags.insert(tag)
        }
        return tags
    }()
    private var lastTagPublished: [String: TimeInterval]=[:]
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
    /// Camera height above the floor, latched by manual or automatic calibration. The phone is worn at a
    /// fixed height, so the floor is recomputed from it every frame: stairs, ramps and ARKit height drift
    /// keep the 0.6–2.1 m sector window on real obstacles instead of on a floor level left behind.
    private var cameraHeight: Double?
    /// Floor level the map was built at; a new level (stairs) starts the map again.
    private var gridFloorY: Double?
    /// A detected target that turns out of the camera's view keeps its route this long, so the path
    /// wave and arrows can say "keep turning". One still in view but no longer detected is dropped at once.
    static let retainSeconds = 8.0
    private var automaticFloor=AutomaticFloorCalibration()
    private var isRunning=false
    private var isInterrupted=false
    private var sessionEpoch=0
    private var worldEpoch=0
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
        if ARWorldTrackingConfiguration.isSupported {
            for tag in Self.roomTags { tag.validate { [weak self] error in if let error { self?.publishStatus("Room tag \(tag.name ?? "") unusable: \(error.localizedDescription)") } } }
        }
        visionQueue.async { [weak self] in
            guard let self else { return }
            let status=self.detector.modelStatus, available=self.detector.model != nil
            DispatchQueue.main.async { self.onModelStatus?(status,available) }
        }
    }
    @discardableResult func start(epoch:Int) -> Bool {
        guard ARWorldTrackingConfiguration.isSupported,ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else { publishStatus("Live sensing requires a LiDAR iPhone or iPad. Use Simulation for software replay."); return false }
        queue.async { self.isRunning=true; self.runSession(epoch:epoch) }
        return true
    }
    /// Called only on the AR delegate queue, including interruption recovery.
    private func runSession(epoch: Int) {
        isInterrupted=false; sessionEpoch=epoch; worldEpoch += 1; earliestFrame=ProcessInfo.processInfo.systemUptime
        floorY=nil; cameraHeight=nil; gridFloorY=nil; automaticFloor.reset(); lastTarget=nil; generation += 1; lastProcessed = -.infinity
        grid.reset(); lastHint=nil; candidates=[]; lockPosition=nil; routeGoal=nil
        let config=ARWorldTrackingConfiguration(); config.frameSemantics=[.sceneDepth]
        config.worldAlignment = .gravity; config.planeDetection=[.horizontal]
        // Room tags: the printed FEEL tag gives room memory its frame (RoomMemory.swift).
        config.detectionImages=Self.roomTags; config.maximumNumberOfTrackedImages=Self.roomTags.isEmpty ? 0 : 1; lastTagPublished=[:]
        session.run(config,options:[.resetTracking,.removeExistingAnchors])
        publishStatus(ARPlaneAnchor.isClassificationSupported ? "Looking for floor — move slowly with the floor in view" : "Automatic floor detection unavailable — calibrate measured camera height")
    }
    func stop() {
        queue.async { self.isRunning=false; self.session.pause(); self.generation += 1; self.lastTarget=nil; self.floorY=nil; self.cameraHeight=nil; self.gridFloorY=nil; self.automaticFloor.reset(); self.grid.reset(); self.lastHint=nil; self.candidates=[]; self.lockPosition=nil; self.routeGoal=nil; self.publishStatus("Stopped") }
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
    /// Whether a world point lies inside the camera's horizontal field (3° inside the edge), so the detector could see it.
    private static func inView(_ position: Vector3,pose: CameraPose,intrinsics k: CameraIntrinsics) -> Bool {
        let p=pose.cameraPoint(world:position)
        guard let bearing=TactileGeometry.bearing(x:p.x,z:p.z), k.fx>0 else { return false }
        return abs(bearing)<=atan(k.cx/k.fx)*180 / .pi-3
    }
    private static func nearest(_ targets: [CapturedTarget],to point: Vector3) -> CapturedTarget? {
        targets.filter { flatDistance($0.position,point)<=1.5 }.min { flatDistance($0.position,point)<flatDistance($1.position,point) }
    }
    func calibrate(cameraHeight: Double) {
        queue.async {
            guard self.isRunning,!self.isInterrupted,cameraHeight.isFinite,cameraHeight>=0.6,cameraHeight<=2.1,let frame=self.session.currentFrame,frame.timestamp>=self.earliestFrame,case .normal=frame.camera.trackingState,ProcessInfo.processInfo.systemUptime>=frame.timestamp,ProcessInfo.processInfo.systemUptime-frame.timestamp<=0.25 else { self.publishStatus("Calibration needs fresh normal tracking and camera height 0.6–2.1 m"); return }
            let pose=Self.pose(frame.camera.transform)
            guard Self.mountValid(pose) else { self.publishStatus("Hold camera landscape-left, upright and facing forward"); return }
            // Heights in the floor map depend on the floor level, so start the map again.
            self.floorY=pose.position.y-cameraHeight; self.cameraHeight=cameraHeight; self.gridFloorY=self.floorY
            self.automaticFloor.reset(); self.grid.reset(); self.lastHint=nil; self.publishStatus("Floor calibrated from measured camera height; it follows the phone at that height")
        }
    }
    /// One frame for Where-is: photo, depth and pose captured together, or nil when the
    /// camera is not tracking normally, is mounted wrong, or has no depth. No photo is kept.
    /// Runs the detector on a Where-is photo for the on-device fallback. Completion on the Vision queue;
    /// nil when the detector cannot run that query here (object queries without the Core ML weights).
    func detectLocal(_ query: LocalQuery,jpeg: Data,completion: @escaping ([ImageDetection]?) -> Void) {
        visionQueue.async {
            guard self.detector.canRun(query) else { completion(nil); return }
            completion((try? self.detector.detect(jpeg:jpeg,query:query)) ?? [])
        }
    }
    func snapshot(completion: @escaping (FrameSnapshot?) -> Void) {
        queue.async {
            var result: FrameSnapshot?
            if let frame=self.session.currentFrame, case .normal=frame.camera.trackingState {
                let pose=Self.pose(frame.camera.transform)
                if Self.mountValid(pose), let depth=frame.sceneDepth, let map=DepthGrid(depth), let jpeg=Self.jpegBase64(frame.capturedImage) {
                    result=FrameSnapshot(timestamp:frame.timestamp,worldEpoch:self.worldEpoch,pose:pose,intrinsics:Self.intrinsics(frame,map),depth:map,jpegBase64:jpeg)
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    /// Intrinsics are published for the full captured image; scale them to the depth grid.
    private static func intrinsics(_ frame: ARFrame,_ map: DepthGrid) -> CameraIntrinsics {
        let raw=frame.camera.intrinsics
        return CameraIntrinsics(fx:Double(raw.columns.0.x),fy:Double(raw.columns.1.y),cx:Double(raw.columns.2.x),cy:Double(raw.columns.2.y))
            .scaled(x:Double(map.width)/Double(frame.camera.imageResolution.width),y:Double(map.height)/Double(frame.camera.imageResolution.height))
    }
    private static let imageContext=CIContext()
    /// JPEG of the captured frame in its native orientation, long side at most 1024 px, quality 0.6.
    private static func jpegBase64(_ buffer: CVPixelBuffer) -> String? {
        let image=CIImage(cvPixelBuffer:buffer)
        let longSide=max(image.extent.width,image.extent.height)
        guard longSide>0 else { return nil }
        let scale=min(1,1024/longSide)
        let scaled=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        let quality=CIImageRepresentationOption(rawValue:kCGImageDestinationLossyCompressionQuality as String)
        return imageContext.jpegRepresentation(of:scaled,colorSpace:CGColorSpaceCreateDeviceRGB(),options:[quality:0.6])?.base64EncodedString()
    }
    private static func mountValid(_ pose: CameraPose) -> Bool { DepthFrameProcessor.mountValid(pose) }
    private static func pose(_ matrix: simd_float4x4) -> CameraPose {
        func v(_ p: SIMD4<Float>) -> Vector3 { Vector3(Double(p.x),Double(p.y),Double(p.z)) }
        return CameraPose(position:v(matrix.columns.3),right:v(matrix.columns.0),up:v(matrix.columns.1),back:v(matrix.columns.2))
    }
    private func publishStatus(_ status: String) { DispatchQueue.main.async { self.onStatus?(status) } }
    private func publish(_ frame: PerceptionFrame) { DispatchQueue.main.async { self.onFrame?(frame) } }
    func session(_ session: ARSession,didUpdate frame: ARFrame) {
        guard isRunning,!isInterrupted else { return }
        // Camera video for replay runs at its own rate, before the 10 Hz processing gate.
        if frame.timestamp>=earliestFrame,recorder.isActive { recorder.appendVideo(frame.capturedImage,timestamp:frame.timestamp) }
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
        let depthMap=frame.sceneDepth.flatMap { DepthFrame($0,camera:frame.camera) }
        // Once the floor is known it stays the calibrated distance below the worn camera.
        if let cameraHeight { floorY=pose.position.y-cameraHeight }
        // Stability is sampled across fresh frames containing the same classified anchor,
        // not independent classification events. A manual calibration or accepted automatic floor
        // remains latched until the AR session resets; automatic updates never overwrite it.
        if floorY == nil {
            let planes: [FloorPlaneObservation] = ARPlaneAnchor.isClassificationSupported ? frame.anchors.compactMap { anchor in
                guard let plane=anchor as? ARPlaneAnchor,plane.alignment == .horizontal else { return nil }
                let center=plane.transform * SIMD4<Float>(plane.center.x,plane.center.y,plane.center.z,1)
                return FloorPlaneObservation(id:plane.identifier.uuidString,
                    classification:plane.classification == .floor ? .floor : .other,
                    worldY:Double(center.y),width:Double(plane.planeExtent.width),length:Double(plane.planeExtent.height))
            } : []
            if let accepted=automaticFloor.observe(planes:planes,timestamp:frame.timestamp,
                now:ProcessInfo.processInfo.systemUptime,cameraY:pose.position.y,
                trackingNormal:normal && depthMap != nil,mountValid:Self.mountValid(pose)) {
                floorY=accepted; cameraHeight=pose.position.y-accepted; gridFloorY=accepted; grid.reset(); lastHint=nil
                publishStatus("Floor calibrated automatically; it follows the phone at this height")
            }
        }
        guard normal,Self.mountValid(pose),let map=depthMap else {
            if recorder.isActive { recorder.append(RecordedFrame(timestamp:frame.timestamp,trackingNormal:normal,pose:pose,floorY:floorY,depth:nil)) }
            lastTarget=nil; lastHint=nil; candidates=[]; generation += 1
            publish(PerceptionFrame(epoch:sessionEpoch,finderEpoch:finderEpoch,worldEpoch:worldEpoch,timestamp:frame.timestamp,tracking:false,distances:Array(repeating:nil,count:7),target:nil,pose:pose,floorY:floorY))
            publishStatus(normal ? "Depth missing or mounting orientation invalid — guidance neutral" : "Tracking uncertain — guidance neutral")
            return
        }
        let k=map.intrinsics
        // Shared with offline replay (simulation/run.py), so recordings score exactly what the app computes.
        if recorder.isActive { recorder.append(RecordedFrame(timestamp:frame.timestamp,trackingNormal:true,pose:pose,floorY:floorY,target:lastTarget,depth:map)) }
        let processed=DepthFrameProcessor.process(map,pose:pose,floorY:floorY)
        let distances=processed.distances
        let target=lastTarget?.observation(pose:pose,now:frame.timestamp)
        if let floorY {
            // Cell heights are relative to the floor, so a new level (stairs) starts the map again.
            if let level=gridFloorY, abs(floorY-level)>0.4 { grid.reset(); lastHint=nil; gridFloorY=floorY }
            if gridFloorY == nil { gridFloorY=floorY }
            grid.integrate(points:processed.mapPoints,floorY:floorY,camera:pose.position)
        }
        // A pointing goal is a fixed world point, so it needs no target in view. Otherwise route only
        // to a target that is in view right now. Either way, a few times a second.
        if let goal=routeGoal {
            if floorY != nil, frame.timestamp-lastPlan>=0.4 {
                lastPlan=frame.timestamp
                lastHint=RouteHint.make(path:grid.route(from:pose.position,to:goal.point),pose:pose,target:goal.point,timestamp:frame.timestamp,label:goal.label)
            }
        }
        else if let goal=lastTarget, frame.timestamp-goal.timestamp<=Self.retainSeconds {
            // Also while the target has turned out of view (retained above): the route then says which way to turn.
            if floorY != nil, frame.timestamp-lastPlan>=0.4 {
                lastPlan=frame.timestamp
                lastHint=RouteHint.make(path:grid.route(from:pose.position,to:goal.position),pose:pose,target:goal.position,timestamp:frame.timestamp,label:goal.label)
            }
        }
        else { lastHint=nil }
        var published=PerceptionFrame(epoch:sessionEpoch,finderEpoch:finderEpoch,worldEpoch:worldEpoch,timestamp:frame.timestamp,tracking:true,distances:distances,target:target,pose:pose,floorY:floorY)
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
                let fresh: CapturedTarget?
                if let lock=self.lockPosition {
                    // Never jump to a different one: losing the chosen target means no target.
                    fresh=Self.nearest(distinct,to:lock)
                    if let fresh { self.lockPosition=fresh.position }
                } else { fresh=distinct.first }
                if let fresh { self.lastTarget=fresh }
                // Not detected this pass: a target that has turned out of the camera's view is kept for a
                // while; one the camera can still see was really lost.
                else if let kept=self.lastTarget, !Self.inView(kept.position,pose:pose,intrinsics:k), now-kept.timestamp<=Self.retainSeconds {}
                else { self.lastTarget=nil }
                if let failure { self.publishStatus(failure) }
            }
        }
    }
    func session(_ session: ARSession,didAdd anchors: [ARAnchor]) { publishTags(anchors) }
    func session(_ session: ARSession,didUpdate anchors: [ARAnchor]) { publishTags(anchors) }
    /// A tracked tag becomes a sighting at most twice a second: its anchor transform is the room frame in this world.
    private func publishTags(_ anchors: [ARAnchor]) {
        let now=ProcessInfo.processInfo.systemUptime
        for case let anchor as ARImageAnchor in anchors where anchor.isTracked {
            guard let name=anchor.referenceImage.name,RoomMemoryStore.isTagId(name),now-(lastTagPublished[name] ?? -.infinity)>=0.5,
                  let frame=RoomFrame(columnMajor:Self.columnMajor(anchor.transform)) else { continue }
            lastTagPublished[name]=now
            let sighting=TagSighting(tagId:name,frame:frame,worldEpoch:worldEpoch,timestamp:now), epoch=sessionEpoch
            DispatchQueue.main.async { self.onTag?(epoch,sighting) }
        }
    }
    private static func columnMajor(_ m: simd_float4x4) -> [Double] {
        [m.columns.0,m.columns.1,m.columns.2,m.columns.3].flatMap { [Double($0.x),Double($0.y),Double($0.z),Double($0.w)] }
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
    private func invalidate() {
        lastTarget=nil; floorY=nil; automaticFloor.reset(); grid.reset(); lastHint=nil; candidates=[]; lockPosition=nil; routeGoal=nil; generation += 1
        let epoch=sessionEpoch
        DispatchQueue.main.async { self.onInvalidated?(epoch) }
    }
    func sessionWasInterrupted(_ session: ARSession) { isInterrupted=true; invalidate(); publishStatus("AR interrupted — recalibrate after restart") }
    func sessionInterruptionEnded(_ session: ARSession) {
        guard isRunning else { return }
        runSession(epoch:sessionEpoch)
    }
    func session(_ session: ARSession,didFailWithError error: Error) { isRunning=false; invalidate(); publishStatus("AR error: \(error.localizedDescription)") }
}

extension DepthGrid {
    /// Copies one ARKit depth frame (Float32 metres) with its confidence map (0 low, 1 medium, 2 high).
    init?(_ data: ARDepthData) {
        let map=data.depthMap
        guard CVPixelBufferGetPixelFormatType(map)==kCVPixelFormatType_DepthFloat32,let confidenceMap=data.confidenceMap else { return nil }
        let width=CVPixelBufferGetWidth(map), height=CVPixelBufferGetHeight(map)
        guard CVPixelBufferGetWidth(confidenceMap)==width,CVPixelBufferGetHeight(confidenceMap)==height else { return nil }
        CVPixelBufferLockBaseAddress(map,.readOnly); CVPixelBufferLockBaseAddress(confidenceMap,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map,.readOnly); CVPixelBufferUnlockBaseAddress(confidenceMap,.readOnly) }
        guard let base=CVPixelBufferGetBaseAddress(map),let confidenceBase=CVPixelBufferGetBaseAddress(confidenceMap) else { return nil }
        var values:[Double]=[]; var confidences:[UInt8]=[]; values.reserveCapacity(width*height); confidences.reserveCapacity(width*height)
        for y in 0..<height {
            let row=base.advanced(by:y*CVPixelBufferGetBytesPerRow(map)).assumingMemoryBound(to:Float.self)
            let confidenceRow=confidenceBase.advanced(by:y*CVPixelBufferGetBytesPerRow(confidenceMap)).assumingMemoryBound(to:UInt8.self)
            for x in 0..<width { values.append(Double(row[x])); confidences.append(confidenceRow[x]) }
        }
        self.init(width:width,height:height,depths:values,confidence:confidences)
    }
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
