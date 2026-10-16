import XCTest
import CoreImage
import CoreVideo
import UIKit
import Vision
@testable import Lantern

final class BarcodeDetectorTests: XCTestCase {
    func testPayloadLabelsArePlainBoundedAndNeverInterpreted() {
        XCTAssertEqual(ObjectDetector.barcodeLabel(nil), "Barcode")
        XCTAssertEqual(ObjectDetector.barcodeLabel(""), "Barcode")
        XCTAssertEqual(ObjectDetector.barcodeLabel(" A\n\u{202E}B\u{0}\tC "), "Code: A B C")
        XCTAssertEqual(ObjectDetector.barcodeLabel("https://example.invalid/stop"), "Code: https://example.invalid/stop")
        let label = ObjectDetector.barcodeLabel(String(repeating: "x", count: 10_000))
        XCTAssertEqual(label.count, 64)
        XCTAssertTrue(label.hasPrefix("Code: "))
        XCTAssertEqual(ObjectDetector.barcodeLabel(String(repeating: "\u{0}", count: 513) + "hidden"), "Barcode")
    }

    /// Exercises Apple's actual Vision request on a generated image, not mocked
    /// observations. It does not establish camera, LiDAR or printed-code range.
    func testVisionDetectsGeneratedQRCodeWithUsableBoundingBox() throws {
        let generator = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        generator.setValue(Data("FEEL test shelf".utf8), forKey: "inputMessage")
        generator.setValue("M", forKey: "inputCorrectionLevel")
        let code = try XCTUnwrap(generator.outputImage).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        // A white quiet zone helps make this a stable Vision smoke fixture.
        let extent = CGRect(x: 0, y: 0, width: code.extent.width + 80, height: code.extent.height + 80)
        let image = code.transformed(by: CGAffineTransform(translationX: 40, y: 40))
            .composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent))
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, Int(extent.width), Int(extent.height),
                                        kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferCGImageCompatibilityKey: true,
                                         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                                        &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        // Materialize the fixture on the CPU, then fill the pixel buffer with
        // CoreGraphics. This avoids depending on an implicit simulator GPU
        // render into a buffer without IOSurface backing.
        let cgImage=try XCTUnwrap(CIContext(options:[.useSoftwareRenderer:true]).createCGImage(image,from:extent))
        let rendered:CGImage = try {
            let lockResult=CVPixelBufferLockBaseAddress(pixelBuffer,[])
            XCTAssertEqual(lockResult,kCVReturnSuccess)
            guard lockResult==kCVReturnSuccess else { throw NSError(domain:"QRFixture",code:Int(lockResult)) }
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer,[]) }
            let base=try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            let rowBytes=CVPixelBufferGetBytesPerRow(pixelBuffer)
            let bitmapInfo=CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            let context=try XCTUnwrap(CGContext(data:base,width:Int(extent.width),height:Int(extent.height),bitsPerComponent:8,bytesPerRow:rowBytes,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:bitmapInfo))
            context.setFillColor(UIColor.white.cgColor); context.fill(extent)
            context.interpolationQuality = .none; context.draw(cgImage,in:extent)
            var black=0,white=0
            let bytes=base.assumingMemoryBound(to:UInt8.self)
            for y in 0..<Int(extent.height) {
                for x in 0..<Int(extent.width) {
                    let i=y*rowBytes+x*4
                    if bytes[i]<20,bytes[i+1]<20,bytes[i+2]<20 { black += 1 }
                    if bytes[i]>235,bytes[i+1]>235,bytes[i+2]>235 { white += 1 }
                }
            }
            XCTAssertGreaterThan(black,Int(extent.width*extent.height*0.05),"QR fixture must contain black modules")
            XCTAssertGreaterThan(white,Int(extent.width*extent.height*0.1),"QR fixture must contain white modules and quiet zone")
            XCTAssertEqual(Array(UnsafeBufferPointer(start:bytes,count:4)),[255,255,255,255],"Quiet-zone corner must be opaque white")
            return try XCTUnwrap(context.makeImage())
        }()
        let fixture=XCTAttachment(image:UIImage(cgImage:rendered)); fixture.name="Actual QR pixel-buffer fixture"; fixture.lifetime = .keepAlways; add(fixture)
        // The base-address lock is released before Vision reads the same buffer.
        let detections = try ObjectDetector().detect(pixelBuffer: pixelBuffer, mode: .barcode)
        if !detections.contains(where: { $0.label == "Code: FEEL test shelf" }) {
            let raw=ObjectDetector.barcodeRequest()
            try VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up,options:[:]).perform([raw])
            let diagnostic=XCTAttachment(string:(raw.results ?? []).map { "\($0.symbology.rawValue): confidence=\($0.confidence), payload=\($0.payloadStringValue ?? "nil"), box=\($0.boundingBox)" }.joined(separator:"\n"))
            diagnostic.name="Unfiltered Vision observations for generated fixture"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        let detection = try XCTUnwrap(detections.first { $0.label == "Code: FEEL test shelf" },"Expected generated payload; found \(detections.map(\.label))")
        XCTAssertGreaterThanOrEqual(detection.confidence, 0.5)
        XCTAssertGreaterThan(detection.box.width, 0)
        XCTAssertGreaterThan(detection.box.height, 0)
        XCTAssertGreaterThanOrEqual(detection.box.minX, 0)
        XCTAssertGreaterThanOrEqual(detection.box.minY, 0)
        XCTAssertLessThanOrEqual(detection.box.maxX, 1)
        XCTAssertLessThanOrEqual(detection.box.maxY, 1)
    }
}
