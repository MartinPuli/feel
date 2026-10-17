import Foundation
import ARKit
import CoreVideo
import FeelCore

struct PerceptionFrame {
    let epoch:Int
    let finderEpoch:Int
    let timestamp: TimeInterval
    let tracking: Bool
    let distances: [Double?]
    let target: TargetObservation?
    let pose: CameraPose
    let floorY: Double?
}

/// The AR delegate queue owns all mutable perception state. Vision has one in-flight
/// request; its originating frame and depth remain paired until completion.
final class ARPerception: NSObject, ARSessionDelegate {
    let session=ARSession()
    var onFrame: ((PerceptionFrame)->Void)?
    var onInvalidated: ((Int)->Void)?
    var onStatus: ((String)->Void)?
    var onModelStatus: ((String,Bool)->Void)?
    private let queue=DispatchQueue(label:"feel.arkit",qos:.userInitiated)
    private let visionQueue=DispatchQueue(label:"feel.vision",qos:.userInitiated)
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
            let config=ARWorldTrackingConfiguration(); config.frameSemantics=[.sceneDepth]; config.worldAlignment = .gravity
            self.session.run(config,options:[.resetTracking,.removeExistingAnchors]); self.publishStatus("Move slowly, then calibrate measured camera height")
        }
        return true
    }
    func stop() {
        queue.async { self.session.pause(); self.generation += 1; self.lastTarget=nil; self.floorY=nil; self.publishStatus("Stopped") }
    }
    func setFinder(_ mode: FinderMode,epoch:Int) { queue.async { self.finder=mode; self.finderEpoch=epoch; self.lastTarget=nil; self.generation += 1 } }
    func calibrate(cameraHeight: Double) {
        queue.async {
            guard cameraHeight.isFinite,cameraHeight>=0.6,cameraHeight<=2.1,let frame=self.session.currentFrame,case .normal=frame.camera.trackingState,ProcessInfo.processInfo.systemUptime-frame.timestamp<=0.25 else { self.publishStatus("Calibration needs fresh normal tracking and camera height 0.6–2.1 m"); return }
            let pose=Self.pose(frame.camera.transform)
            guard Self.mountValid(pose) else { self.publishStatus("Hold camera landscape-left, upright and facing forward"); return }
            self.floorY=pose.position.y-cameraHeight; self.publishStatus("Floor calibrated from measured camera height")
        }
    }
    private static func mountValid(_ pose: CameraPose) -> Bool { pose.isValid && pose.up.y>0.7 && abs(pose.right.y)<0.35 }
    private static func pose(_ matrix: simd_float4x4) -> CameraPose {
        func v(_ p: SIMD4<Float>) -> Vector3 { Vector3(Double(p.x),Double(p.y),Double(p.z)) }
        return CameraPose(position:v(matrix.columns.3),right:v(matrix.columns.0),up:v(matrix.columns.1),back:v(matrix.columns.2))
    }
    private func publishStatus(_ status: String) { DispatchQueue.main.async { self.onStatus?(status) } }
    private func publish(_ frame: PerceptionFrame) { DispatchQueue.main.async { self.onFrame?(frame) } }
    func session(_ session: ARSession,didUpdate frame: ARFrame) {
        guard frame.timestamp>=earliestFrame,frame.timestamp-lastProcessed>=0.095 else { return }; lastProcessed=frame.timestamp
        let pose=Self.pose(frame.camera.transform)
        let normal: Bool; if case .normal=frame.camera.trackingState { normal=true } else { normal=false }
        guard normal,Self.mountValid(pose),let depth=frame.sceneDepth,let map=DepthCopy(depth) else {
            lastTarget=nil; generation += 1
            publish(PerceptionFrame(epoch:sessionEpoch,finderEpoch:finderEpoch,timestamp:frame.timestamp,tracking:false,distances:Array(repeating:nil,count:7),target:nil,pose:pose,floorY:floorY))
            publishStatus(normal ? "Depth missing or mounting orientation invalid — guidance neutral" : "Tracking uncertain — guidance neutral")
            return
        }
        let raw=frame.camera.intrinsics
        let k=CameraIntrinsics(fx:Double(raw.columns.0.x),fy:Double(raw.columns.1.y),cx:Double(raw.columns.2.x),cy:Double(raw.columns.2.y))
            .scaled(x:Double(map.width)/Double(frame.camera.imageResolution.width),y:Double(map.height)/Double(frame.camera.imageResolution.height))
        var samples:[DepthSample]=[]; samples.reserveCapacity(map.width*map.height/9)
        for y in stride(from:0,to:map.height,by:3) {
            for x in stride(from:0,to:map.width,by:3) {
                let i=y*map.width+x
                if let point=k.unproject(x:Double(x),y:Double(y),depth:map.depths[i]) { samples.append(.init(cameraPoint:point,confidence:map.confidence[i])) }
            }
        }
        let distances=DepthProjector.sectors(samples:samples,pose:pose,floorY:floorY)
        publish(PerceptionFrame(epoch:sessionEpoch,finderEpoch:finderEpoch,timestamp:frame.timestamp,tracking:true,distances:distances,target:lastTarget?.observation(pose:pose,now:frame.timestamp),pose:pose,floorY:floorY))
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
                return CapturedTarget(position:pose.worldPoint(camera:point),timestamp:timestamp,confidence:detection.confidence,label:detection.label)
            }
            self.queue.async {
                self.visionBusy=false
                guard token==self.generation else { return }
                let now=ProcessInfo.processInfo.systemUptime
                self.lastTarget=targets.filter { $0.observation(pose:pose,now:now) != nil }.sorted { $0.confidence > $1.confidence }.first
                if let failure { self.publishStatus(failure) }
            }
        }
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }
    private func invalidate() {
        lastTarget=nil; floorY=nil; generation += 1
        let epoch=sessionEpoch
        DispatchQueue.main.async { self.onInvalidated?(epoch) }
    }
    func sessionWasInterrupted(_ session: ARSession) { invalidate(); publishStatus("AR interrupted — recalibrate after restart") }
    func sessionInterruptionEnded(_ session: ARSession) { _=start(epoch:sessionEpoch) }
    func session(_ session: ARSession,didFailWithError error: Error) { invalidate(); publishStatus("AR error: \(error.localizedDescription)") }
}

private struct DepthCopy {
    let width: Int,height: Int,depths: [Double],confidence: [UInt8]
    init?(_ data: ARDepthData) {
        let map=data.depthMap
        guard CVPixelBufferGetPixelFormatType(map)==kCVPixelFormatType_DepthFloat32,let confidenceMap=data.confidenceMap else { return nil }
        width=CVPixelBufferGetWidth(map); height=CVPixelBufferGetHeight(map)
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
        depths=values; confidence=confidences
    }
    func medianDepth(x:Double,y:Double)->Double? {
        guard x.isFinite,y.isFinite,x>=0,y>=0,x<Double(width),y<Double(height) else { return nil }
        var values:[Double]=[]
        for yy in max(0,Int(y)-2)...min(height-1,Int(y)+2) {
            for xx in max(0,Int(x)-2)...min(width-1,Int(x)+2) {
                let i=yy*width+xx,value=depths[i]
                if confidence[i]>=1,confidence[i]<=2,value.isFinite,value>0,value<=4 { values.append(value) }
            }
        }
        guard values.count>=3 else { return nil }; values.sort(); return values[values.count/2]
    }
}
