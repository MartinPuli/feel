import XCTest
import CoreImage
import CoreVideo
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
        CIContext(options: nil).render(image, to: pixelBuffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        let detections = try ObjectDetector().detect(pixelBuffer: pixelBuffer, mode: .barcode)
        let detection = try XCTUnwrap(detections.first { $0.label == "Code: FEEL test shelf" })
        XCTAssertGreaterThanOrEqual(detection.confidence, 0.5)
        XCTAssertGreaterThan(detection.box.width, 0)
        XCTAssertGreaterThan(detection.box.height, 0)
        XCTAssertGreaterThanOrEqual(detection.box.minX, 0)
        XCTAssertGreaterThanOrEqual(detection.box.minY, 0)
        XCTAssertLessThanOrEqual(detection.box.maxX, 1)
        XCTAssertLessThanOrEqual(detection.box.maxY, 1)
    }
}
