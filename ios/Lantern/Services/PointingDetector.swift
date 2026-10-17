import Foundation
import Vision
import CoreVideo
import FeelCore

/// Executed only on ARPerception's pointing queue. Reads the printed codes on the puck's back,
/// fits the sheet, checks the "I'm asking" pose, then finds the fingertip: taped marker first,
/// Vision hand pose as a fallback. Camera images never leave the phone.
final class PointingDetector {
    var useHandPoseFallback = true
    /// Sampling step on the sheet, mm.
    let step = 1.0

    func analyze(pixelBuffer: CVPixelBuffer, timestamp: Double) -> PointingObservation {
        let width=Double(CVPixelBufferGetWidth(pixelBuffer)), height=Double(CVPixelBufferGetHeight(pixelBuffer))
        let handler=VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up,options:[:])
        let request=VNDetectBarcodesRequest(); request.symbologies=[.qr]
        try? handler.perform([request])
        var sheet: [PlanePoint]=[], image: [PlanePoint]=[], seen=Set<String>()
        for code in request.results ?? [] {
            guard let payload=code.payloadStringValue, !seen.contains(payload), let corners=PuckBackLayout.corners(of:payload) else { continue }
            seen.insert(payload)
            // Vision: normalised, bottom-left origin, corners in the symbol's own orientation.
            sheet+=corners
            image+=[code.topLeft,code.topRight,code.bottomRight,code.bottomLeft].map { PlanePoint(Double($0.x)*width,(1-Double($0.y))*height) }
        }
        func result(_ gate: PointingGateResult?=nil,_ tip: PlanePoint?=nil,_ method: FingertipMethod?=nil) -> PointingObservation {
            .init(timestamp:timestamp,codesSeen:seen.count,gate:gate,fingertip:tip,method:method)
        }
        guard !seen.isEmpty, let toImage=Homography.fit(from:sheet,to:image), let toSheet=toImage.inverse,
              let gate=PointingGate.evaluate(toImage,imageWidth:width) else { return result() }
        guard gate.ok else { return result(gate) }
        if let tip=markerTip(pixelBuffer,toImage) { return result(gate,tip,.marker) }
        if useHandPoseFallback, let tip=handTip(handler,toSheet,width,height) { return result(gate,tip,.handPose) }
        return result(gate)
    }

    /// Samples the sheet's pin area every `step` mm and takes the largest marker-coloured blob.
    private func markerTip(_ buffer: CVPixelBuffer, _ toImage: Homography) -> PlanePoint? {
        let L=PuckBackLayout.self
        let w=Int(((L.searchMaxU-L.searchMinU)/step).rounded(.down))+1, h=Int(((L.searchMaxV-L.searchMinV)/step).rounded(.down))+1
        guard let mask=PixelReader.read(buffer, { reader -> [Bool] in
            var mask=[Bool](repeating:false,count:w*h)
            for j in 0..<h { for i in 0..<w {
                guard let p=toImage.apply(PlanePoint(L.searchMinU+Double(i)*step,L.searchMinV+Double(j)*step)),
                      let c=reader.rgb(x:Int(p.x.rounded()),y:Int(p.y.rounded())) else { continue }
                mask[j*w+i]=FingertipMarker.isMarker(r:c.r,g:c.g,b:c.b)
            } }
            return mask
        }) else { return nil }
        return FingertipMarker.locate(mask,width:w,height:h,minU:L.searchMinU,minV:L.searchMinV,step:step)
    }

    /// Index fingertip of whichever detected hand points inside the pin grid.
    private func handTip(_ handler: VNImageRequestHandler, _ toSheet: Homography, _ width: Double, _ height: Double) -> PlanePoint? {
        let request=VNDetectHumanHandPoseRequest(); request.maximumHandCount=2
        guard (try? handler.perform([request])) != nil else { return nil }
        for hand in request.results ?? [] {
            guard let tip=try? hand.recognizedPoint(.indexTip), tip.confidence>=0.3,
                  let p=toSheet.apply(PlanePoint(Double(tip.location.x)*width,(1-Double(tip.location.y))*height)),
                  PuckBackLayout.cell(at:p) != nil else { continue }
            return p
        }
        return nil
    }
}

/// RGB (0…1) from ARKit's YCbCr camera buffers, or BGRA (tests).
struct PixelReader {
    private enum Layout { case ycbcr(video: Bool), bgra }
    private let layout: Layout
    private let width: Int, height: Int
    private let base0: UnsafeRawPointer, stride0: Int
    private let base1: UnsafeRawPointer?, stride1: Int

    static func read<T>(_ buffer: CVPixelBuffer, _ body: (PixelReader) -> T) -> T? {
        CVPixelBufferLockBaseAddress(buffer,.readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        let format=CVPixelBufferGetPixelFormatType(buffer)
        let layout: Layout
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: layout = .ycbcr(video:false)
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: layout = .ycbcr(video:true)
        case kCVPixelFormatType_32BGRA: layout = .bgra
        default: return nil
        }
        let planar: Bool; if case .ycbcr=layout { planar=true } else { planar=false }
        guard let b0=planar ? CVPixelBufferGetBaseAddressOfPlane(buffer,0) : CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let reader=PixelReader(layout:layout,width:CVPixelBufferGetWidth(buffer),height:CVPixelBufferGetHeight(buffer),
                               base0:UnsafeRawPointer(b0),stride0:planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer,0) : CVPixelBufferGetBytesPerRow(buffer),
                               base1:planar ? CVPixelBufferGetBaseAddressOfPlane(buffer,1).map(UnsafeRawPointer.init) : nil,
                               stride1:planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer,1) : 0)
        if planar && reader.base1 == nil { return nil }
        return body(reader)
    }

    func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double)? {
        guard x>=0, y>=0, x<width, y<height else { return nil }
        func clamp(_ v: Double) -> Double { min(1,max(0,v)) }
        switch layout {
        case .bgra:
            let p=base0.advanced(by:y*stride0+x*4).assumingMemoryBound(to:UInt8.self)
            return (Double(p[2])/255,Double(p[1])/255,Double(p[0])/255)
        case .ycbcr(let video):
            guard let base1 else { return nil }
            var luma=Double(base0.advanced(by:y*stride0+x).assumingMemoryBound(to:UInt8.self).pointee)
            let c=base1.advanced(by:(y/2)*stride1+(x/2)*2).assumingMemoryBound(to:UInt8.self)
            var cb=Double(c[0])-128, cr=Double(c[1])-128
            if video { luma=(luma-16)*255/219; cb*=255/224; cr*=255/224 }
            // Full-range BT.601, as used for ARKit's captured image.
            return (clamp((luma+1.402*cr)/255),clamp((luma-0.344136*cb-0.714136*cr)/255),clamp((luma+1.772*cb)/255))
        }
    }
}
