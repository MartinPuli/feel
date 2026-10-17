import XCTest
import Vision
import CoreVideo
import FeelCore
@testable import Lantern

/// Runs the real detector on synthetic frames using the same request configuration
/// as the app. Unsupported Vision environments skip explicitly; the Mac harness
/// also exercises these scenarios without proving physical-device performance.
final class PointingDetectorTests: XCTestCase {
    func testSyntheticScenarios() throws {
        let synthetic=PointingSynthetic()
        let probe=try synthetic.frame(for:PointingSynthetic.scenarios[0])
        let request=PointingDetector.barcodeRequest()
        do { try VNImageRequestHandler(cvPixelBuffer:probe,orientation:.up,options:[:]).perform([request]) }
        catch { throw XCTSkip("Vision barcode reader unavailable here (\(error.localizedDescription)); run ios/scripts/pointing_harness.sh on the Mac") }
        for scenario in PointingSynthetic.scenarios {
            let detector=PointingDetector(); detector.useHandPoseFallback=false
            let observation=detector.analyze(pixelBuffer:try synthetic.frame(for:scenario),timestamp:1)
            XCTAssertNil(PointingSynthetic.check(observation,scenario),scenario.name)
        }
    }
}
