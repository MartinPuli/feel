import XCTest
@testable import FeelCore

final class AutomaticFloorCalibrationTests: XCTestCase {
    private func plane(_ id: String = "floor", y: Double = 0,
                       classification: FloorPlaneObservation.Classification = .floor,
                       width: Double = 1, length: Double = 1) -> FloorPlaneObservation {
        FloorPlaneObservation(id:id,classification:classification,worldY:y,width:width,length:length)
    }
    @discardableResult private func sample(_ policy: inout AutomaticFloorCalibration, _ time: Double,
                                          planes: [FloorPlaneObservation]? = nil, now: Double? = nil,
                                          cameraY: Double = 1.2, normal: Bool = true, mount: Bool = true) -> Double? {
        policy.observe(planes:planes ?? [plane()],timestamp:time,now:now ?? time,
                       cameraY:cameraY,trackingNormal:normal,mountValid:mount)
    }
    func testAcceptsStableClassifiedFloorAndLatchesUntilReset() {
        var policy=AutomaticFloorCalibration()
        for i in 0..<15 { XCTAssertNil(sample(&policy,Double(i)/10)) }
        XCTAssertEqual(sample(&policy,1.5),0)
        XCTAssertEqual(sample(&policy,2,planes:[],normal:false),0)
        policy.reset()
        XCTAssertNil(policy.floorY)
        XCTAssertNil(sample(&policy,2.1))
    }
    func testRequiresTenFramesEvenWhenDurationIsSatisfied() {
        var policy=AutomaticFloorCalibration()
        for i in 0..<9 { XCTAssertNil(sample(&policy,Double(i)*0.2)) }
        XCTAssertEqual(sample(&policy,1.8),0)
    }
    func testRejectsNonfinitePlaneGeometry() {
        for invalid in [plane(y:.nan),plane(y:.infinity),plane(width:.nan),plane(length:.infinity)] {
            var policy=AutomaticFloorCalibration()
            for i in 0...30 { XCTAssertNil(sample(&policy,Double(i)/10,planes:[invalid])) }
        }
    }
    func testRejectsUnknownAndOtherPlanesWithoutHeightFallback() {
        for classification in [FloorPlaneObservation.Classification.unknown,.other] {
            var policy=AutomaticFloorCalibration()
            for i in 0...30 {
                XCTAssertNil(sample(&policy,Double(i)/10,planes:[plane(classification:classification)]))
            }
        }
    }
    func testRejectsSmallPlanesAndImplausibleCameraHeights() {
        for dimensions in [(0.49,2.0),(2.0,0.49),(0.6,0.6)] {
            var policy=AutomaticFloorCalibration()
            for i in 0...30 { XCTAssertNil(sample(&policy,Double(i)/10,planes:[plane(width:dimensions.0,length:dimensions.1)])) }
        }
        for height in [0.59,2.11,Double.nan,Double.infinity] {
            var policy=AutomaticFloorCalibration()
            for i in 0...30 { XCTAssertNil(sample(&policy,Double(i)/10,cameraY:height)) }
        }
    }
    func testRejectsStaleFutureAndNonfiniteTimes() {
        for offset in [-0.01,0.251,Double.nan,Double.infinity] {
            var policy=AutomaticFloorCalibration()
            for i in 0...30 {
                let time=Double(i)/10
                XCTAssertNil(sample(&policy,time,now:time+offset))
            }
        }
    }
    func testInvalidTrackingMountOrMissingFloorBreaksContinuity() {
        for invalid in 0..<3 {
            var policy=AutomaticFloorCalibration()
            for i in 0..<10 { sample(&policy,Double(i)/10) }
            XCTAssertNil(sample(&policy,1,planes:invalid == 0 ? [] : nil,normal:invalid != 1,mount:invalid != 2))
            for i in 11...25 { XCTAssertNil(sample(&policy,Double(i)/10)) }
            XCTAssertEqual(sample(&policy,2.6),0)
        }
    }
    func testAnchorSwitchAndUnstableHeightRestartWindow() {
        for switched in [false,true] {
            var policy=AutomaticFloorCalibration()
            for i in 0..<10 { sample(&policy,Double(i)/10) }
            let changed=plane(switched ? "new" : "floor",y:0.04)
            for i in 10..<25 { XCTAssertNil(sample(&policy,Double(i)/10,planes:[changed])) }
            XCTAssertEqual(sample(&policy,2.5,planes:[changed]) ?? -1,0.04,accuracy:0.00001)
        }
    }
    func testSlowHeightDriftCannotEvadeStabilityWindow() {
        var policy=AutomaticFloorCalibration()
        for i in 0...60 {
            XCTAssertNil(sample(&policy,Double(i)/10,planes:[plane(y:Double(i)*0.004)]))
        }
    }
    func testDuplicateSparseAndBackwardsFramesDoNotAccumulate() {
        var policy=AutomaticFloorCalibration()
        for _ in 0..<100 { XCTAssertNil(sample(&policy,0)) }
        for i in 1...10 { XCTAssertNil(sample(&policy,Double(i))) }
        for i in 101..<110 { XCTAssertNil(sample(&policy,Double(i)/10)) }
        XCTAssertNil(sample(&policy,9))
        for i in 110..<125 { XCTAssertNil(sample(&policy,Double(i)/10)) }
        XCTAssertEqual(sample(&policy,12.5),0)
    }
    func testSelectsFloorInsteadOfLargerTableAndKeepsAnchorWhenOrderChanges() {
        var policy=AutomaticFloorCalibration()
        let floor=plane(),other=plane("table",y:0.7,classification:.other,width:3,length:3)
        let smallerFloor=plane("secondary",y:0.1,width:0.8,length:0.8)
        for i in 0..<15 {
            let planes=i%2 == 0 ? [other,floor,smallerFloor] : [smallerFloor,other,floor]
            XCTAssertNil(sample(&policy,Double(i)/10,planes:planes))
        }
        XCTAssertEqual(sample(&policy,1.5,planes:[other,smallerFloor,floor]),0)
    }
}
