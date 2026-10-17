import Foundation
import Vision
import CoreVideo
import FeelCore

/// Executed only on ARPerception's pointing queue, on the same camera image, so no extra
/// frame is retained. Finds the closest hand making the V request sign. Images stay on the phone.
final class HandSignDetector {
    func analyze(pixelBuffer: CVPixelBuffer, timestamp: Double, focalPixels: Double) -> HandSignObservation {
        let width=Double(CVPixelBufferGetWidth(pixelBuffer)), height=Double(CVPixelBufferGetHeight(pixelBuffer))
        let request=VNDetectHumanHandPoseRequest(); request.maximumHandCount=2
        let handler=VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up,options:[:])
        guard (try? handler.perform([request])) != nil else { return .init(timestamp:timestamp,vSign:false,distance:nil) }
        var best: HandSignObservation?
        for hand in request.results ?? [] {
            func point(_ name: VNHumanHandPoseObservation.JointName) -> PlanePoint? {
                guard let p=try? hand.recognizedPoint(name), p.confidence>=0.3 else { return nil }
                // Vision: normalised, bottom-left origin.
                return PlanePoint(Double(p.location.x)*width,(1-Double(p.location.y))*height)
            }
            let joints=HandJoints(wrist:point(.wrist),
                                  index:.init(mcp:point(.indexMCP),pip:point(.indexPIP),tip:point(.indexTip)),
                                  middle:.init(mcp:point(.middleMCP),pip:point(.middlePIP),tip:point(.middleTip)),
                                  ring:.init(mcp:point(.ringMCP),pip:point(.ringPIP),tip:point(.ringTip)),
                                  little:.init(mcp:point(.littleMCP),pip:point(.littlePIP),tip:point(.littleTip)))
            let observation=HandSignObservation(timestamp:timestamp,vSign:HandSign.isVSign(joints),
                                                distance:HandSign.estimatedDistance(joints,focalPixels:focalPixels))
            // Prefer a counting sign, then the nearest hand.
            if best == nil || (observation.counts && !best!.counts) ||
                (observation.counts == best!.counts && (observation.distance ?? .infinity) < (best!.distance ?? .infinity)) {
                best=observation
            }
        }
        return best ?? .init(timestamp:timestamp,vSign:false,distance:nil)
    }
}
