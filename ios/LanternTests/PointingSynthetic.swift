import Foundation
import CoreImage
import CoreGraphics
import CoreVideo
import FeelCore

/// Synthetic camera frames of the printed back sheet, warped by a known homography. Shared by
/// PointingDetectorTests (iOS) and scripts/pointing_harness.sh (macOS, where Vision's barcode
/// reader runs; the iOS simulator can't create its inference context). Proves geometry and
/// Vision's corner order only: not real lighting, blur, hands or tape.
struct PointingSynthetic {
    struct Failure: Error, CustomStringConvertible { let description: String }
    enum Expect { case cell(PuckCell, codes: Int), uprightRejected, noFingertip }
    struct Scenario {
        let name: String, tip: PuckCell?, angle: Double, hide: Set<String>, format: OSType, tipColor: CGColor, expect: Expect
        init(_ name: String, tip: PuckCell?, angle: Double = 180, hide: Set<String> = [], format: OSType = kCVPixelFormatType_32BGRA,
             tipColor: CGColor = CGColor(gray:0.05,alpha:1), expect: Expect) {
            self.name=name; self.tip=tip; self.angle=angle; self.hide=hide; self.format=format; self.tipColor=tipColor; self.expect=expect
        }
    }
    static let scenarios: [Scenario] = {
        var list = [PuckCell(column:0,band:1),PuckCell(column:6,band:1),PuckCell(column:0,band:4),PuckCell(column:6,band:4),PuckCell(column:3,band:2)].map {
            Scenario("fingers left, black tape, \($0)",tip:$0,expect:.cell($0,codes:3))
        }
        list += [
            Scenario("fingers right (other hand), C2 B3",tip:PuckCell(column:2,band:3),angle:0,expect:.cell(PuckCell(column:2,band:3),codes:3)),
            Scenario("blue tape, C5 B2",tip:PuckCell(column:5,band:2),tipColor:CGColor(red:0.1,green:0.3,blue:0.85,alpha:1),expect:.cell(PuckCell(column:5,band:2),codes:3)),
            Scenario("one code visible, far cell C1 B4",tip:PuckCell(column:1,band:4),hide:["FEEL:WC","FEEL:WR"],expect:.cell(PuckCell(column:1,band:4),codes:1)),
            Scenario("ARKit YCbCr buffer, C4 B3",tip:PuckCell(column:4,band:3),format:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,expect:.cell(PuckCell(column:4,band:3),codes:3)),
            Scenario("fingers up: gate rejects",tip:PuckCell(column:3,band:2),angle:90,expect:.uprightRejected),
            Scenario("no finger",tip:nil,expect:.noFingertip),
        ]
        return list
    }()

    let ci=CIContext()
    let imageW=1920, imageH=1440, pxPerMM=8.0

    /// Sheet → image (pixels, y down): `scale` px/mm, fingers toward `angle` (0 = image right), mild perspective.
    func view(angle: Double, scale: Double = 4.2) -> Homography {
        let a=angle * .pi/180
        let affine=[sin(a)*scale,cos(a)*scale,960.0, cos(a)*scale,-sin(a)*scale,700, 0,0,1]
        return Homography(Homography.mul(affine,[1,0,0, 0,1,0, 0.0012,-0.0008,1]))!
    }
    func require<T>(_ value: T?, _ what: String) throws -> T { guard let value else { throw Failure(description:what) }; return value }

    /// The sheet drawn flat; CG's bottom-left origin is (sheetMinU, sheetMinV), v up.
    func sheetImage(tip: PlanePoint?, hide: Set<String>, tipColor: CGColor) throws -> CGImage {
        let L=PuckBackLayout.self
        let w=Int((L.sheetMaxU-L.sheetMinU)*pxPerMM), h=Int((L.sheetMaxV-L.sheetMinV)*pxPerMM)
        let ctx=try require(CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),"context")
        func rect(_ u0: Double,_ v0: Double,_ u1: Double,_ v1: Double) -> CGRect {
            CGRect(x:(u0-L.sheetMinU)*pxPerMM,y:(v0-L.sheetMinV)*pxPerMM,width:(u1-u0)*pxPerMM,height:(v1-v0)*pxPerMM)
        }
        ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:w,height:h))
        ctx.setStrokeColor(CGColor(gray:0.78,alpha:1)); ctx.setLineWidth(0.3*pxPerMM)
        for c in 0...7 { let u=(3.5-Double(c))*L.columnPitch; ctx.stroke(rect(u,8,u,58.5)) }
        for r in 0...4 { let v=min(58.5,8+Double(r)*L.rowPitch); ctx.stroke(rect(-41,v,41,v)) }
        ctx.interpolationQuality = .none
        for code in L.codes where !hide.contains(code.payload) {
            let s=L.codeSize/2
            ctx.draw(try qrSymbol(code.payload),in:rect(code.centerU-s,L.codeCenterV-s,code.centerU+s,L.codeCenterV+s))
        }
        if let tip {
            // A skin-coloured finger coming in from the side, tape on its tip.
            ctx.setFillColor(CGColor(red:0.85,green:0.62,blue:0.5,alpha:1)); ctx.fill(rect(tip.x,tip.y-7,L.sheetMaxU+1,tip.y+7))
            ctx.setFillColor(tipColor); ctx.fillEllipse(in:rect(tip.x-6,tip.y-6,tip.x+6,tip.y+6))
        }
        return try require(ctx.makeImage(),"sheet image")
    }

    /// The QR symbol alone (quiet zone cropped), one pixel per module.
    func qrSymbol(_ text: String) throws -> CGImage {
        let filter=try require(CIFilter(name:"CIQRCodeGenerator"),"QR filter")
        filter.setValue(Data(text.utf8),forKey:"inputMessage"); filter.setValue("H",forKey:"inputCorrectionLevel")
        let output=try require(filter.outputImage,"QR output")
        let full=try require(ci.createCGImage(output,from:output.extent),"QR image")
        let w=full.width, h=full.height
        var px=[UInt8](repeating:0,count:w*h)
        try px.withUnsafeMutableBytes { raw in
            let gray=try require(CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0),"gray")
            gray.draw(full,in:CGRect(x:0,y:0,width:w,height:h))
        }
        var minX=w,minY=h,maxX = -1,maxY = -1
        for y in 0..<h { for x in 0..<w where px[y*w+x]<128 { minX=min(minX,x); maxX=max(maxX,x); minY=min(minY,y); maxY=max(maxY,y) } }
        guard maxX-minX+1 == 21 else { throw Failure(description:"expected a version-1 symbol, got \(maxX-minX+1) modules") }
        return try require(full.cropping(to:CGRect(x:minX,y:minY,width:21,height:21)),"crop")
    }

    /// Warps the flat sheet into a camera frame over a dark chassis-coloured background.
    func cameraFrame(_ sheet: CGImage, _ h: Homography, format: OSType) throws -> CVPixelBuffer {
        let L=PuckBackLayout.self
        func point(_ u: Double,_ v: Double) -> CIVector { let p=h.apply(PlanePoint(u,v))!; return CIVector(x:p.x,y:Double(imageH)-p.y) }
        let warp=try require(CIFilter(name:"CIPerspectiveTransform"),"warp")
        warp.setValue(CIImage(cgImage:sheet),forKey:kCIInputImageKey)
        warp.setValue(point(L.sheetMinU,L.sheetMaxV),forKey:"inputTopLeft"); warp.setValue(point(L.sheetMaxU,L.sheetMaxV),forKey:"inputTopRight")
        warp.setValue(point(L.sheetMinU,L.sheetMinV),forKey:"inputBottomLeft"); warp.setValue(point(L.sheetMaxU,L.sheetMinV),forKey:"inputBottomRight")
        let bounds=CGRect(x:0,y:0,width:imageW,height:imageH)
        let image=try require(warp.outputImage,"warped").composited(over:CIImage(color:CIColor(red:0.12,green:0.12,blue:0.13)).cropped(to:bounds))
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil,imageW,imageH,format,[kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&buffer) == kCVReturnSuccess,
              let out=buffer else { throw Failure(description:"pixel buffer") }
        ci.render(image,to:out,bounds:bounds,colorSpace:CGColorSpaceCreateDeviceRGB())
        return out
    }

    func frame(for s: Scenario) throws -> CVPixelBuffer {
        try cameraFrame(try sheetImage(tip:s.tip.map(PuckBackLayout.center(of:)),hide:s.hide,tipColor:s.tipColor),view(angle:s.angle),format:s.format)
    }

    /// Nil if the observation matches the expectation, else what went wrong.
    static func check(_ o: PointingObservation, _ s: Scenario) -> String? {
        switch s.expect {
        case .cell(let cell, let codes):
            if o.codesSeen != codes { return "codes \(o.codesSeen), expected \(codes)" }
            if o.gate?.ok != true { return "gate \(o.gate?.reason ?? "no fit")" }
            if o.method != .marker { return "fingertip method \(String(describing:o.method))" }
            if o.cell != cell { return "cell \(String(describing:o.cell)), expected \(cell)" }
            if let tip=o.fingertip, tip.distance(to:PuckBackLayout.center(of:cell))>=2 { return String(format:"tip %.1f mm from centre",tip.distance(to:PuckBackLayout.center(of:cell))) }
        case .uprightRejected:
            if o.codesSeen == 0 { return "no codes" }
            if o.gate?.upright != false { return "gate did not reject rotation" }
            if o.fingertip != nil { return "looked for a fingertip despite the gate" }
        case .noFingertip:
            if o.gate?.ok != true { return "gate \(o.gate?.reason ?? "no fit")" }
            if o.fingertip != nil { return "phantom fingertip at \(o.fingertip!)" }
        }
        return nil
    }
}
