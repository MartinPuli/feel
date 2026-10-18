import XCTest
@testable import FeelCore

final class SpatialMemoryTests: XCTestCase {
    private let empty: [Double?] = Array(repeating:nil,count:7)
    private func pose(_ position: Vector3 = .zero, yaw: Double=0) -> CameraPose {
        let a=yaw * .pi / 180
        return CameraPose(position:position,right:Vector3(cos(a),0,-sin(a)),up:Vector3(0,1,0),back:Vector3(sin(a),0,cos(a)))
    }
    private func sample(_ pose: CameraPose = .identity, session: String="one", time: Double=1, tracking: Bool=true) -> MemoryPose {
        .init(session:session,pose:pose,timestamp:time,tracking:tracking)
    }
    private func recalled(_ point: Vector3) throws -> SpatialMemoryManager {
        var manager=SpatialMemoryManager(); try manager.begin(session:"one")
        try manager.remember(id:"desk",name:"Desk",sample:sample(pose(point)),now:1)
        try manager.recall(); return manager
    }
    func testRememberSelectRenameDeleteAndSwitch() throws {
        var m=try recalled(Vector3(0,0,-2))
        try m.remember(id:"chair",name:"  Chair  ",sample:sample(pose(Vector3(1,0,-2))),now:1)
        XCTAssertEqual(m.bookmarks.map(\.name),["Desk","Chair"]); XCTAssertEqual(m.selectedID,"chair"); XCTAssertNil(m.activeID)
        try m.recall(); XCTAssertEqual(m.activeID,"chair")
        try m.select(id:"desk"); XCTAssertNil(m.activeID)
        try m.recall(); try m.rename(id:"desk",name:"Table")
        XCTAssertEqual(m.guidance(sample:sample(),now:1).targetName,"Table")
        try m.delete(id:"desk"); XCTAssertNil(m.activeID); XCTAssertNil(m.selectedID); XCTAssertEqual(m.bookmarks.count,1)
    }
    func testMutationFailuresAreAtomic() throws {
        var m=try recalled(.zero); let before=m.snapshot
        for bad in ["", "   ", "a\nb", "a\0b", String(repeating:"a",count:41)] {
            XCTAssertThrowsError(try m.rename(id:"desk",name:bad)); XCTAssertEqual(m.snapshot,before)
        }
        for bad in ["", "$return", "space id", "é", String(repeating:"a",count:65)] {
            XCTAssertThrowsError(try m.remember(id:bad,name:"Other",sample:sample(),now:1)); XCTAssertEqual(m.snapshot,before)
        }
        XCTAssertThrowsError(try m.remember(id:"desk",name:"Other",sample:sample(),now:1))
        XCTAssertThrowsError(try m.remember(id:"other",name:"DESK",sample:sample(),now:1))
        XCTAssertThrowsError(try m.select(id:"missing")); XCTAssertThrowsError(try m.delete(id:"missing"))
        XCTAssertThrowsError(try m.recall(id:"missing")); XCTAssertEqual(m.snapshot,before)
    }
    func testUnicodeNamesAndDuplicateNormalization() throws {
        var m=SpatialMemoryManager(); try m.begin(session:"one")
        try m.remember(id:"cafe",name:"Café",sample:sample(),now:1)
        XCTAssertThrowsError(try m.remember(id:"other",name:"  CAFE  ",sample:sample(),now:1))
        try m.remember(id:"emoji",name:"Door 🚪",sample:sample(),now:1)
        XCTAssertThrowsError(try m.rename(id:"emoji",name:"café"))
        try m.rename(id:"cafe",name:"CAFÉ"); XCTAssertEqual(m.bookmarks[0].name,"CAFÉ")
    }
    func testCapacityLimitDoesNotOverwrite() throws {
        var m=SpatialMemoryManager(); try m.begin(session:"one")
        for i in 0..<64 { try m.remember(id:"p\(i)",name:"Place \(i)",sample:sample(),now:1) }
        XCTAssertThrowsError(try m.remember(id:"extra",name:"Extra",sample:sample(),now:1)); XCTAssertEqual(m.bookmarks.count,64)
    }
    func testCaptureRequiresSameFreshNormallyTrackedSession() throws {
        var m=SpatialMemoryManager()
        XCTAssertThrowsError(try m.remember(id:"a",name:"A",sample:sample(),now:1))
        try m.begin(session:"one")
        for s in [sample(session:"old"),sample(time:0.749),sample(time:1.01),sample(tracking:false)] {
            XCTAssertThrowsError(try m.remember(id:"a",name:"A",sample:s,now:1))
            XCTAssertThrowsError(try m.setReturnPoint(sample:s,now:1))
        }
        XCTAssertTrue(m.bookmarks.isEmpty); XCTAssertNil(m.returnPoint)
        try m.remember(id:"a",name:"A",sample:sample(time:0.75),now:1)
        XCTAssertEqual(m.bookmarks.count,1)
    }
    func testTrackingLossNeutralizesWithoutLosingIntent() throws {
        let m=try recalled(Vector3(0,0,-2))
        let lost=m.encode(sequence:1,sample:sample(tracking:false),now:1,distances:[1,1,1,1,1,1,1])
        XCTAssertEqual(lost.guidance.state,.trackingLost); XCTAssertEqual(lost.output.packet,.neutral(sequence:1))
        XCTAssertEqual(m.bookmarks.count,1); XCTAssertEqual(m.activeID,"desk")
        XCTAssertEqual(m.encode(sequence:2,sample:sample(time:4),now:4,distances:empty).output.packet.highlight,4)
    }
    func testStaleFutureInvalidAndBoundaryPoses() throws {
        let m=try recalled(Vector3(0,0,-2))
        XCTAssertEqual(m.guidance(sample:sample(time:0.75),now:1).state,.guiding)
        XCTAssertEqual(m.guidance(sample:sample(time:0.749999),now:1).state,.stalePose)
        XCTAssertEqual(m.guidance(sample:sample(time:1.001),now:1).state,.invalidPose)
        XCTAssertEqual(m.guidance(sample:sample(),now:.nan).state,.invalidPose)
        var invalid=CameraPose.identity; invalid.right=Vector3(-1,0,0)
        XCTAssertFalse(invalid.isValid)
        var shear=CameraPose.identity; shear.up=Vector3(0.5,1,0)
        var nonfinite=CameraPose.identity; nonfinite.position.x = .infinity
        for p in [invalid,shear,nonfinite,pose(.zero,yaw:.nan)] {
            let result=m.encode(sequence:0,sample:sample(p),now:1,distances:[1,1,1,1,1,1,1])
            XCTAssertEqual(result.guidance.state,.invalidPose); XCTAssertEqual(result.output.packet,.neutral(sequence:0))
        }
    }
    func testUpsideDownAndVerticalMountAreInvalid() throws {
        let m=try recalled(Vector3(0,0,-2))
        let rolled=CameraPose(right:Vector3(-1,0,0),up:Vector3(0,-1,0),back:Vector3(0,0,1))
        let vertical=CameraPose(right:Vector3(1,0,0),up:Vector3(0,0,-1),back:Vector3(0,1,0))
        XCTAssertTrue(rolled.isValid); XCTAssertTrue(vertical.isValid)
        XCTAssertEqual(m.guidance(sample:sample(rolled),now:1).state,.invalidPose)
        XCTAssertEqual(m.guidance(sample:sample(vertical),now:1).state,.invalidPose)
    }
    func testTranslationsAndNinetyAndOneEightyDegreeRotations() throws {
        let m=try recalled(.zero)
        for p in [pose(Vector3(0,0,2)),pose(Vector3(2,0,0),yaw:90),pose(Vector3(0,0,-2),yaw:180),pose(Vector3(-2,0,0),yaw:-90)] {
            let result=m.encode(sequence:2,sample:sample(p),now:1,distances:empty)
            XCTAssertEqual(result.guidance.state,.guiding); XCTAssertEqual(result.guidance.distance ?? -1,2,accuracy:1e-12)
            XCTAssertEqual(result.guidance.bearingDegrees ?? 999,0,accuracy:1e-10); XCTAssertEqual(result.output.packet.highlight,4)
        }
    }
    func testBearingSignAfterTranslation() throws {
        let m=try recalled(Vector3(0,0,-1))
        let direction=m.guidance(sample:sample(pose(Vector3(1,0,1))),now:1)
        XCTAssertEqual(direction.bearingDegrees ?? 0,-26.565051177,accuracy:1e-8)
        XCTAssertEqual(direction.distance ?? 0,sqrt(5),accuracy:1e-12)
    }
    func testPitchedCameraMatchesV1DepthAndTargetProjection() throws {
        let point=Vector3(1.2,0,-2),m=try recalled(point)
        for degrees in [20.0,40] {
            let a=degrees * .pi / 180
            let pitched=CameraPose(right:Vector3(1,0,0),up:Vector3(0,cos(a),sin(a)),back:Vector3(0,-sin(a),cos(a)))
            let memory=m.guidance(sample:sample(pitched),now:1)
            let detected=CapturedTarget(position:point,timestamp:1).observation(pose:pitched,now:1)
            XCTAssertEqual(memory.bearingDegrees,detected?.bearingDegrees)
            XCTAssertEqual(memory.distance,detected?.distance)
            XCTAssertEqual(memory.horizontalDistance ?? 0,hypot(1.2,2),accuracy:1e-12)
            let depths=DepthProjector.sectors(samples:[DepthSample(cameraPoint:pitched.cameraPoint(world:point),confidence:2)],pose:pitched,floorY:-1.2)
            let packet=m.encode(sequence:0,sample:sample(pitched),now:1,distances:depths).output.packet
            XCTAssertEqual(packet.bands.filter { $0>0 }.count,1)
            XCTAssertEqual(packet.highlight,UInt8(TactileGeometry.column(bearingDegrees:detected!.bearingDegrees)!))
        }
    }
    func testEverySectorBoundaryAndOutsideFOV() throws {
        for index in 0...6 {
            let angle = -45 + Double(index)*15, r=angle * .pi / 180
            let m=try recalled(Vector3(sin(r)*2,0,-cos(r)*2))
            let result=m.encode(sequence:0,sample:sample(),now:1,distances:empty)
            XCTAssertEqual(result.guidance.state,.guiding,"angle \(angle)")
            XCTAssertEqual(result.output.packet.highlight,UInt8(min(index+1,6)))
        }
        for angle in [-45.001,45.001] {
            let r=angle * .pi / 180,m=try recalled(Vector3(sin(r)*2,0,-cos(r)*2))
            let result=m.encode(sequence:0,sample:sample(),now:1,distances:empty)
            XCTAssertEqual(result.guidance.state,.outsideFieldOfView); XCTAssertEqual(result.output.packet.highlight,255)
        }
    }
    func testBehindAndSideTargetsNeverClampToEdge() throws {
        let m=try recalled(Vector3(0,0,-2))
        for yaw in [90.0,180,-90] {
            let result=m.encode(sequence:0,sample:sample(pose(.zero,yaw:yaw)),now:1,distances:empty)
            XCTAssertTrue([.outsideFieldOfView,.behind].contains(result.guidance.state))
            XCTAssertEqual(result.output.packet,.neutral(sequence:0))
            XCTAssertEqual(result.guidance.distance ?? -1,2,accuracy:1e-12)
        }
    }
    func testBeyondRangeReportsActualDistanceWithoutFakeBand() throws {
        for distance in [4.0,4.00001,12] {
            let m=try recalled(Vector3(0,0,-distance)),r=m.encode(sequence:7,sample:sample(),now:1,distances:empty)
            XCTAssertEqual(r.guidance.distance,distance)
            XCTAssertEqual(r.guidance.state,distance==4 ? .guiding : .beyondRange)
            XCTAssertEqual(r.output.packet.highlight,distance==4 ? 4 : 255)
        }
    }
    func testArrivalAndVerticalToleranceBoundaries() throws {
        for (point,state) in [(Vector3(0,0,-0.35),MemoryGuidanceState.arrived),(Vector3(0,0,-0.350001),.guiding),(Vector3(0,0.75,0),.arrived),(Vector3(0,0.750001,0),.differentLevel)] {
            let m=try recalled(point),r=m.encode(sequence:0,sample:sample(),now:1,distances:empty)
            XCTAssertEqual(r.guidance.state,state)
            if state != .guiding { XCTAssertEqual(r.output.packet.highlight,255) }
        }
    }
    func testCloserObstaclesRemainAndUnavailableTargetsKeepObstacleBands() throws {
        let m=try recalled(Vector3(0,0,-3)),distances: [Double?]=[nil,0.5,1,2,0.7,3,nil]
        let r=m.encode(sequence:1,sample:sample(),now:1,distances:distances)
        XCTAssertEqual(r.output.packet.bands,[0,1,2,3,1,4,0]); XCTAssertEqual(r.output.packet.highlight,4)
        for p in [pose(Vector3(0,0,-3)),pose(.zero,yaw:180),pose(Vector3(0,0,5))] {
            let r=m.encode(sequence:2,sample:sample(p),now:1,distances:distances)
            XCTAssertEqual(r.output.packet.bands,[0,1,2,3,1,4,0]); XCTAssertEqual(r.output.packet.highlight,255)
        }
    }
    func testFloorAndDepthValidationStillGateMemoryPackets() throws {
        let m=try recalled(Vector3(0,0,-2))
        let uncal=m.encode(sequence:1,sample:sample(),now:1,distances:empty,floorCalibrated:false)
        XCTAssertEqual(uncal.output.state,.uncalibrated); XCTAssertEqual(uncal.output.packet,.neutral(sequence:1))
        XCTAssertEqual(m.encode(sequence:0,sample:sample(),now:1,distances:[]).output.state,.invalidFrame)
    }
    func testReturnPointIsExplicitAndIndependentOfBookmarks() throws {
        var m=SpatialMemoryManager(); try m.begin(session:"one")
        XCTAssertThrowsError(try m.returnToStart())
        try m.setReturnPoint(sample:sample(),now:1)
        try m.remember(id:"desk",name:"Desk",sample:sample(pose(Vector3(2,0,-1))),now:1)
        try m.returnToStart(); XCTAssertEqual(m.activeID,"$return"); XCTAssertEqual(m.selectedID,"desk")
        XCTAssertEqual(m.guidance(sample:sample(pose(Vector3(0,0,2))),now:1).bearingDegrees,0)
        try m.recall(); XCTAssertEqual(m.activeID,"desk"); XCTAssertEqual(m.returnPoint,.zero)
        try m.returnToStart(); try m.setReturnPoint(sample:sample(pose(Vector3(1,0,1))),now:1)
        XCTAssertNil(m.activeID); XCTAssertEqual(m.returnPoint,Vector3(1,0,1))
    }
    func testStopGuidanceKeepsPlacesAndReturn() throws {
        var m=try recalled(Vector3(0,0,-2)); try m.setReturnPoint(sample:sample(),now:1)
        m.stopGuidance(); XCTAssertEqual(m.guidance(sample:sample(),now:1).state,.idle)
        XCTAssertEqual(m.bookmarks.count,1); XCTAssertEqual(m.returnPoint,.zero)
    }
    func testResetEndAndReusedSessionIDsNeverReuseMemory() throws {
        var m=try recalled(Vector3(0,0,-2)); try m.setReturnPoint(sample:sample(),now:1)
        let before=m.snapshot
        XCTAssertThrowsError(try m.begin(session:"one")); XCTAssertEqual(m.snapshot,before)
        try m.begin(session:"two")
        XCTAssertTrue(m.bookmarks.isEmpty); XCTAssertNil(m.returnPoint); XCTAssertNil(m.activeID)
        let result=m.encode(sequence:1,sample:sample(),now:1,distances:[1,1,1,1,1,1,1])
        XCTAssertEqual(result.guidance.state,.sessionMismatch); XCTAssertEqual(result.output.packet,.neutral(sequence:1))
        m.end(); XCTAssertNil(m.session)
        XCTAssertEqual(m.guidance(sample:sample(session:"two"),now:1).state,.sessionUnavailable)
        XCTAssertThrowsError(try m.recall()); XCTAssertThrowsError(try m.begin(session:"one"))
    }
}
