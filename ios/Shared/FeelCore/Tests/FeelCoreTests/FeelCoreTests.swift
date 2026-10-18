import XCTest
@testable import FeelCore

final class ProtocolTests: XCTestCase {
    func testGoldenEncoding() throws {
        let p=try FeelPacket(sequence:255,bands:[1,2,3,4,0,0,1],highlight:6)
        XCTAssertEqual(p.hex,"ff0102030400000106"); XCTAssertEqual(p.bytes.count,9)
        XCTAssertEqual(try FeelPacket(bytes:p.bytes),p)
        XCTAssertEqual(try FeelPacket(hex:p.hex),p)
    }
    func testEmptyHighlightIsWireLegalButIneffective() throws {
        let p=try FeelPacket(sequence:0,bands:[0,0,0,0,0,0,0],highlight:3)
        XCTAssertEqual(p.highlight,3); XCTAssertEqual(p.effectiveHighlight,255)
    }
    func testRejectPacketLengths() {
        for count in [0,1,8,10,255] { XCTAssertThrowsError(try FeelPacket(bytes:Array(repeating:0,count:count))) }
    }
    func testRejectEveryInvalidBand() {
        for value in 5...255 { XCTAssertThrowsError(try FeelPacket(sequence:0,bands:[0,0,UInt8(value),0,0,0,0])) }
    }
    func testRejectEveryInvalidHighlight() {
        for value in 7...254 { XCTAssertThrowsError(try FeelPacket(sequence:0,bands:Array(repeating:1,count:7),highlight:UInt8(value))) }
    }
    func testRejectMalformedHex() {
        for text in ["","0000000000000000","00000000000000000000","0000000000000000zz","00 00 00 00 00 00 00 00 ff"] { XCTAssertThrowsError(try FeelPacket(hex:text)) }
    }
    func testAllSequenceValuesRoundTrip() throws {
        for s in 0...255 {
            let p=try FeelPacket(sequence:UInt8(s),bands:[0,1,2,3,4,1,2],highlight:5)
            XCTAssertEqual(try FeelPacket(bytes:p.bytes),p)
        }
    }
    func testCodablePreservesInvariants() throws {
        for text in [#"{"sequence":0,"bands":[],"highlight":0}"#,#"{"sequence":0,"bands":[0,0,0,0,0,0,5],"highlight":255}"#,#"{"sequence":0,"bands":[0,0,0,0,0,0,0],"highlight":7}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(FeelPacket.self,from:Data(text.utf8)))
        }
        let packet=FeelPacket.neutral(sequence:9)
        XCTAssertEqual(try JSONDecoder().decode(FeelPacket.self,from:JSONEncoder().encode(packet)),packet)
    }
    func testNeutralAndRollover() { var seq: UInt8=255; seq &+= 1; XCTAssertEqual(FeelPacket.neutral(sequence:seq).hex,"0000000000000000ff") }
}
final class GeometryTests: XCTestCase {
    func testBandEdges() {
        let data: [(Double,UInt8)]=[(0,0),(-1,0),(0.001,1),(0.3,1),(0.899999,1),(0.9,2),(1.599999,2),(1.6,3),(2.499999,3),(2.5,4),(4,4),(4.000001,0),(.infinity,0),(.nan,0)]
        for (distance,band) in data { XCTAssertEqual(TactileGeometry.band(distance:distance),band,"\(distance)") }
    }
    func testSectorCenters() {
        for column in 1...6 { XCTAssertEqual(TactileGeometry.column(bearingDegrees:-45+(Double(column)-0.5)*15),column) }
    }
    func testSectorEdgesChooseRight() {
        XCTAssertEqual(TactileGeometry.column(bearingDegrees:-45),1); XCTAssertEqual(TactileGeometry.column(bearingDegrees:45),6)
        for edge in 2...6 {
            let angle = -45+Double(edge-1)*15
            XCTAssertEqual(TactileGeometry.column(bearingDegrees:angle),edge)
            XCTAssertEqual(TactileGeometry.column(bearingDegrees:angle-1e-8),edge-1)
            XCTAssertEqual(TactileGeometry.column(bearingDegrees:angle+1e-8),edge)
        }
    }
    func testInvalidBearings() {
        for angle in [-45.0001,45.0001,180,Double.nan,.infinity] { XCTAssertNil(TactileGeometry.column(bearingDegrees:angle)) }
    }
    func testDirectionSignAndBehind() { XCTAssertEqual(TactileGeometry.bearing(x:1,z:-1),45); XCTAssertEqual(TactileGeometry.bearing(x:-1,z:-1),-45); XCTAssertNil(TactileGeometry.bearing(x:1,z:1)) }
    func testUnprojectionAndIntrinsicScaling() {
        let k=CameraIntrinsics(fx:1000,fy:1000,cx:960,cy:720).scaled(x:0.1,y:0.1)
        XCTAssertEqual(k.unproject(x:106,y:62,depth:2),Vector3(0.2,0.2,-2))
        XCTAssertNil(k.unproject(x:0,y:0,depth:.nan))
        XCTAssertNil(CameraIntrinsics(fx:0,fy:1,cx:0,cy:0).unproject(x:0,y:0,depth:1))
    }
    func testPoseTransforms() {
        let pose=CameraPose(position:Vector3(2,1,3),right:Vector3(0,0,-1),up:Vector3(0,1,0),back:Vector3(1,0,0))
        let point=Vector3(1,2,-3)
        XCTAssertTrue(pose.isValid); XCTAssertEqual(pose.worldPoint(camera:point),Vector3(-1,3,2)); XCTAssertEqual(pose.cameraPoint(world:pose.worldPoint(camera:point)),point)
    }
    func testInvalidPose() { XCTAssertFalse(CameraPose(right:Vector3(2,0,0)).isValid) }
}
final class PerceptionTests: XCTestCase {
    let pose=CameraPose(position:Vector3(0,1,0))
    func sample(_ x: Double=0,_ y: Double=0,_ z: Double = -1,_ confidence: UInt8=2) -> DepthSample { .init(cameraPoint:Vector3(x,y,z),confidence:confidence) }
    /// A real surface leaves several samples; the projector needs `DepthProjector.support` of them.
    func surface(_ x: Double=0,_ y: Double=0,_ z: Double = -1,_ confidence: UInt8=2) -> [DepthSample] { Array(repeating:sample(x,y,z,confidence),count:DepthProjector.support) }
    /// Six sectors in wire slots 1...6: straight ahead is slot 4.
    func testNearestSurfacePerSector() {
        let result=DepthProjector.sectors(samples:surface(0,0,-2)+surface(0,0,-0.8)+surface(-1,0,-2)+surface(1,0,-2),pose:pose,floorY:0)
        XCTAssertEqual(result[4],0.8); XCTAssertEqual(result[2],sqrt(5)); XCTAssertEqual(result[5],sqrt(5)); XCTAssertNil(result[0])
    }
    func testStrayPixelsNeverRaiseAPin() {
        XCTAssertEqual(DepthProjector.support,3)
        XCTAssertNil(DepthProjector.sectors(samples:[sample(0,0,-1),sample(0,0,-1)],pose:pose,floorY:0)[4],"two stray points are not an obstacle")
        XCTAssertEqual(DepthProjector.sectors(samples:surface(0,0,-2)+[sample(0,0,-0.5),sample(0.02,0,-0.7)],pose:pose,floorY:0)[4],2,"flyers ahead of a wall do not pull it closer")
        XCTAssertEqual(DepthProjector.sectors(samples:[sample(0,0,-1)],pose:pose,floorY:0,support:1)[4],1)
    }
    func testRejectFloorCeilingBehindAndConfidence() {
        let result=DepthProjector.sectors(samples:surface(0,-0.5,-1)+surface(0,1.2,-1)+surface(0,0,1)+surface(0,0,-1,0)+surface(0,0,-1,3),pose:pose,floorY:0)
        XCTAssertTrue(result.allSatisfy { $0 == nil })
    }
    func testFloorCalibrationIsRequired() { XCTAssertTrue(DepthProjector.sectors(samples:surface(),pose:pose,floorY:nil).allSatisfy { $0 == nil }) }
    func testCalibratedFloorNotWorldOrigin() {
        XCTAssertEqual(DepthProjector.sectors(samples:surface(),pose:CameraPose(position:Vector3(0,7,0)),floorY:6)[4],1)
    }
    func output(now:Double=10,time:Double=10,tracking:Bool=true,distances:[Double?]=[0.5,1,2,3,nil,nil,nil],target:TargetObservation?=nil,floor:Bool=true)->EncoderOutput {
        TactileEncoder.encode(sequence:12,now:now,frameTimestamp:time,tracking:tracking,distances:distances,target:target,floorCalibrated:floor)
    }
    func testProductionEncoding() { XCTAssertEqual(output().packet.hex,"0c00020304000000ff"); XCTAssertEqual(output().state,.live) }
    func testTrackingLossImmediatelyNeutral() { XCTAssertEqual(output(tracking:false).packet.bands,Array(repeating:0,count:7)); XCTAssertEqual(output(tracking:false).state,.trackingLost) }
    func testStaleDepthCutoff() { XCTAssertEqual(output(now:10.25).state,.live); XCTAssertEqual(output(now:10.25001).state,.staleDepth) }
    func testFutureInvalidTimestampAndMissingFrame() { XCTAssertEqual(output(time:11).state,.invalidFrame); XCTAssertEqual(output(now:.nan).state,.invalidFrame); XCTAssertEqual(output(distances:[]).state,.invalidFrame) }
    func testUncalibratedNeutral() { XCTAssertEqual(output(floor:false).state,.uncalibrated) }
    func testInvalidDistancesDoNotCreatePins() { XCTAssertEqual(output(distances:[nil,.nan,.infinity,-1,0,4.1,nil]).packet.bands,Array(repeating:0,count:7)) }
    func testTargetPreservesCloserObstacle() {
        let target=TargetObservation(bearingDegrees:0,distance:3,timestamp:10)
        let p=output(distances:[nil,nil,nil,nil,0.5,nil,nil],target:target).packet
        XCTAssertEqual(p.bands[4],1); XCTAssertEqual(p.highlight,4)
    }
    func testTargetCanRaisePreviouslyEmptyColumn() {
        let p=output(target:.init(bearingDegrees:40,distance:1.5,timestamp:10)).packet
        XCTAssertEqual(p.bands[6],2); XCTAssertEqual(p.highlight,6)
    }
    func testTargetExpiryAndConfidence() {
        XCTAssertEqual(output(target:.init(bearingDegrees:0,distance:1,timestamp:9.5)).packet.highlight,4)
        for t in [TargetObservation(bearingDegrees:0,distance:1,timestamp:9.49999),.init(bearingDegrees:0,distance:1,timestamp:11),.init(bearingDegrees:0,distance:1,timestamp:10,confidence:0.49),.init(bearingDegrees:0,distance:1,timestamp:10,confidence:1.1),.init(bearingDegrees:90,distance:1,timestamp:10)] { XCTAssertEqual(output(target:t).packet.highlight,255) }
    }
    func testLostTrackingSuppressesFreshTarget() { XCTAssertEqual(output(tracking:false,target:.init(bearingDegrees:0,distance:1,timestamp:10)).packet.highlight,255) }
    func testTargetSelectionDeterministic() {
        let targets=[TargetObservation(bearingDegrees:20,distance:2,timestamp:10,confidence:0.9),.init(bearingDegrees:-10,distance:1,timestamp:10,confidence:0.9),.init(bearingDegrees:0,distance:0.5,timestamp:1)]
        XCTAssertEqual(TargetSelector.best(targets,at:10)?.bearingDegrees,-10)
    }
}

final class CapturedTargetTests:XCTestCase {
    func testRotatedCameraReprojectsTarget() {
        let target=CapturedTarget(position:Vector3(0,1,-2),timestamp:10)
        let root=CameraPose(position:Vector3(0,1,0))
        XCTAssertEqual(target.observation(pose:root,now:10.1)?.bearingDegrees,0)
        let angle=30.0*Double.pi/180
        let turned=CameraPose(position:root.position,right:Vector3(cos(angle),0,sin(angle)),up:Vector3(0,1,0),back:Vector3(-sin(angle),0,cos(angle)))
        XCTAssertEqual(target.observation(pose:turned,now:10.1)!.bearingDegrees,-30,accuracy:1e-10)
        XCTAssertEqual(TactileGeometry.column(bearingDegrees:target.observation(pose:turned,now:10.1)!.bearingDegrees),2)
    }
    func testTranslationRecomputesRange() {
        let target=CapturedTarget(position:Vector3(0,1,-2),timestamp:10)
        XCTAssertEqual(target.observation(pose:CameraPose(position:Vector3(0,1,-1)),now:10.1)?.distance,1)
    }
    func testBehindAndExpiredDrop() {
        let target=CapturedTarget(position:Vector3(0,1,-2),timestamp:10)
        XCTAssertNil(target.observation(pose:CameraPose(position:Vector3(0,1,-3)),now:10.1))
        XCTAssertNil(target.observation(pose:.identity,now:10.50001))
    }
}

final class ConnectionAndStatusTests:XCTestCase {
    func testSwitchedPeripheralRejectsOldCallbacks() {
        var selection=PeripheralSelection(); let a=UUID(),b=UUID()
        selection.select(a); XCTAssertTrue(selection.accepts(a)); selection.clear(); selection.select(b)
        XCTAssertFalse(selection.accepts(a)); XCTAssertTrue(selection.accepts(b)); selection.clear(); XCTAssertFalse(selection.accepts(b))
    }
    func testStatusOutputDisabledIsExplicit() throws {
        let status=try PuckStatus(bytes:[1,1,1,1,42,3,0,0,1,2,3,4,0,0,0])
        XCTAssertEqual(status.outputState,.disabled); XCTAssertTrue(status.summary.contains("DISABLED")); XCTAssertEqual(status.sequence,42)
    }
    func testStatusFaultAndMalformed() throws {
        let status=try PuckStatus(bytes:[1,1,0,0,0,255,0,2,0,0,0,0,0,0,0])
        XCTAssertEqual(status.outputState,.fault); XCTAssertTrue(status.summary.contains("FAULT"))
        XCTAssertThrowsError(try PuckStatus(bytes:[]))
        XCTAssertThrowsError(try PuckStatus(bytes:[1,1,0,0,0,255,0,3,0,0,0,0,0,0,0]))
    }
}
