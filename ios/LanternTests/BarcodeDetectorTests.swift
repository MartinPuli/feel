import XCTest
import CoreImage
import CoreVideo
import ImageIO
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
        let detections: [ImageDetection]
        do {
            detections = try ObjectDetector().detect(pixelBuffer: pixelBuffer, mode: .barcode)
        } catch {
            attachBarcodeDiagnostics(pixelBuffer:pixelBuffer,cgImage:rendered)
            throw error
        }
        if !detections.contains(where: { $0.label == "Code: FEEL test shelf" }) {
            attachBarcodeDiagnostics(pixelBuffer:pixelBuffer,cgImage:rendered)
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

    /// Failure-only comparison of the same retained pixels. No result from this
    /// matrix substitutes for the production detector assertion above.
    private func attachBarcodeDiagnostics(pixelBuffer:CVPixelBuffer,cgImage:CGImage) {
        let production=ObjectDetector.barcodeRequest()
        let supported=VNDetectBarcodesRequest.supportedRevisions
        // Bound the matrix if a future runtime adds many algorithm revisions.
        let revisions=Array(Set([production.revision]+Array(supported.prefix(4)))).sorted()
        var lines=["runtime=\(ProcessInfo.processInfo.operatingSystemVersionString), supportedRevisions=\(Array(supported)), productionRevision=\(production.revision), productionCPUOnly=\(production.usesCPUOnly)",
                   "fixture=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)), pixelFormat=\(CVPixelBufferGetPixelFormatType(pixelBuffer)), bytesPerRow=\(CVPixelBufferGetBytesPerRow(pixelBuffer))"]
        func inspect(input:String,revision:Int,cpuOnly:Bool,mirrored:Bool) {
            let request=VNDetectBarcodesRequest()
            request.revision=revision; request.usesCPUOnly=cpuOnly
            let orientation:CGImagePropertyOrientation = mirrored ? .upMirrored : .up
            let handler:VNImageRequestHandler
            if input=="CGImage" {
                handler=VNImageRequestHandler(cgImage:cgImage,orientation:orientation,options:[:])
            } else {
                handler=VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:orientation,options:[:])
            }
            let prefix="input=\(input), revision=\(request.revision), cpuOnly=\(request.usesCPUOnly), orientation=\(mirrored ? "upMirrored" : "up")"
            do {
                try handler.perform([request])
                let observations=(request.results ?? []).map {
                    "{symbology=\($0.symbology.rawValue), confidence=\($0.confidence), payload=\(String(reflecting:$0.payloadStringValue)), box=\($0.boundingBox)}"
                }.joined(separator:", ")
                lines.append("\(prefix), observations=[\(observations)]")
            } catch {
                let failure=error as NSError
                lines.append("\(prefix), error=\(failure.domain):\(failure.code) \(failure.localizedDescription)")
            }
        }
        for revision in revisions {
            for cpuOnly in [false,true] {
                for input in ["CGImage","CVPixelBuffer"] {
                    inspect(input:input,revision:revision,cpuOnly:cpuOnly,mirrored:false)
                }
            }
        }
        for input in ["CGImage","CVPixelBuffer"] {
            inspect(input:input,revision:production.revision,cpuOnly:production.usesCPUOnly,mirrored:true)
        }
        for line in lines { print("[QR diagnostic] \(line)") }
        let diagnostic=XCTAttachment(string:lines.joined(separator:"\n"))
        diagnostic.name="Vision input, revision and compute diagnostic matrix"
        diagnostic.lifetime = .keepAlways; add(diagnostic)
    }
}
