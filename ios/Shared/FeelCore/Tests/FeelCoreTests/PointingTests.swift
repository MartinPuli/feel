import XCTest
@testable import FeelCore

final class TargetSpanTests: XCTestCase {
    let sector = 90.0/6
    func encode(_ t: TargetObservation, sequence: UInt8 = 1, distances: [Double?] = Array(repeating:nil,count:7)) -> EncoderOutput {
        TactileEncoder.encode(sequence:sequence,now:10,frameTimestamp:10,tracking:true,distances:distances,target:t)
    }
    func testPointTargetKeepsSingleColumnFirmwareTap() {
        let out=encode(.init(bearingDegrees:0,distance:2,timestamp:10))
        XCTAssertEqual(out.targetColumns,4...4); XCTAssertEqual(out.packet.highlight,4); XCTAssertEqual(out.packet.bands,[0,0,0,0,3,0,0])
    }
    func testWideTargetCoversColumnsAndUsesPhoneTap() {
        let t=TargetObservation(bearingDegrees:0,distance:2,timestamp:10,halfWidthDegrees:sector*1.2)
        XCTAssertEqual(t.columns,3...5)
        let out=encode(t)
        XCTAssertEqual(out.packet.highlight,255); XCTAssertEqual(out.packet.bands,[0,0,0,3,3,3,0])
    }
    func testGroupTapDropsSpanOncePerPeriod() {
        let t=TargetObservation(bearingDegrees:0,distance:2,timestamp:10,halfWidthDegrees:sector*1.2)
        let dropped=(0..<12).filter { encode(t,sequence:UInt8($0)).packet.bands[3] == 0 }
        XCTAssertEqual(dropped,[0,6])
        XCTAssertEqual(encode(t,sequence:6).targetColumns,3...5)
    }
    func testSmallOverlapDoesNotJoinNeighbour() {
        // Centre of column 3, edges 2° into columns 2 and 4: below the 3° minimum overlap.
        XCTAssertEqual(TargetObservation(bearingDegrees:7.5,distance:2,timestamp:10,halfWidthDegrees:sector/2+2).columns,4...4)
        XCTAssertEqual(TargetObservation(bearingDegrees:7.5,distance:2,timestamp:10,halfWidthDegrees:sector/2+4).columns,3...5)
    }
    func testSpanClipsAtFieldEdge() {
        XCTAssertEqual(TargetObservation(bearingDegrees:40,distance:2,timestamp:10,halfWidthDegrees:30).columns,4...6)
    }
    func testSpanPreservesCloserObstacles() {
        let t=TargetObservation(bearingDegrees:0,distance:3,timestamp:10,halfWidthDegrees:sector*1.2)
        XCTAssertEqual(encode(t,distances:[nil,nil,0.5,nil,4,nil,nil]).packet.bands,[0,0,1,4,4,4,0])
    }
    func testInvalidTargetHasNoColumns() {
        let out=encode(.init(bearingDegrees:0,distance:2,timestamp:5,halfWidthDegrees:20))
        XCTAssertNil(out.targetColumns); XCTAssertEqual(out.packet.bands,Array(repeating:0,count:7))
    }
    func testDecodingWithoutWidthIsPointTarget() throws {
        let t=try JSONDecoder().decode(TargetObservation.self,from:Data(#"{"bearingDegrees":0,"distance":2,"timestamp":1,"confidence":1,"label":"x"}"#.utf8))
        XCTAssertEqual(t.halfWidthDegrees,0); XCTAssertEqual(t.columns,4...4)
    }
    func testCapturedTargetWidthScalesWithDistance() {
        let near=CapturedTarget(position:Vector3(0,0,-1),timestamp:1,halfWidthMeters:0.5).observation(pose:.identity,now:1)
        let far=CapturedTarget(position:Vector3(0,0,-3),timestamp:1,halfWidthMeters:0.5).observation(pose:.identity,now:1)
        XCTAssertEqual(near?.halfWidthDegrees ?? 0,atan2(0.5,1)*180 / .pi,accuracy:1e-9)
        XCTAssertGreaterThan(near!.columns!.count,far!.columns!.count)
    }
}

final class HomographyTests: XCTestCase {
    let truth=Homography([1.8,0.3,640, -0.2,1.7,380, 0.0004,-0.0003,1])!
    let grid=[PlanePoint(-40,-20),PlanePoint(40,-20),PlanePoint(40,59),PlanePoint(-40,59),PlanePoint(0,10),PlanePoint(17,33)]
    func testExactFitFromFourPoints() throws {
        let from=Array(grid.prefix(4)), to=from.map { truth.apply($0)! }
        let h=try XCTUnwrap(Homography.fit(from:from,to:to))
        for p in grid { let a=h.apply(p)!, b=truth.apply(p)!; XCTAssertEqual(a.distance(to:b),0,accuracy:1e-6) }
    }
    func testInverseRoundTrip() throws {
        let inv=try XCTUnwrap(truth.inverse)
        for p in grid { XCTAssertEqual(inv.apply(truth.apply(p)!)!.distance(to:p),0,accuracy:1e-9) }
    }
    func testLeastSquaresAveragesNoise() throws {
        var from: [PlanePoint]=[], to: [PlanePoint]=[]
        for (i,u) in stride(from:-35.0,through:35,by:10).enumerated() { for (j,v) in stride(from:-18.0,through:4,by:7).enumerated() {
            from.append(PlanePoint(u,v)); let q=truth.apply(PlanePoint(u,v))!
            to.append(PlanePoint(q.x+((i+j).isMultiple(of:2) ? 0.5 : -0.5),q.y+(i % 3 == 0 ? 0.5 : -0.5)))
        } }
        let h=try XCTUnwrap(Homography.fit(from:from,to:to))
        // Extrapolating 60 mm past the codes to the far pin row stays within a pixel or two.
        XCTAssertLessThan(h.apply(PlanePoint(30,55))!.distance(to:truth.apply(PlanePoint(30,55))!),3)
    }
    func testDegenerateInputsRejected() {
        XCTAssertNil(Homography.fit(from:[PlanePoint(0,0),PlanePoint(1,1),PlanePoint(2,2),PlanePoint(3,3)],to:[PlanePoint(0,0),PlanePoint(1,0),PlanePoint(0,1),PlanePoint(1,1)]))
        XCTAssertNil(Homography.fit(from:[PlanePoint(0,0)],to:[PlanePoint(0,0)]))
        XCTAssertNil(Homography([1,0,0,0,1,0,0,0,0]))
    }
}

final class PuckBackLayoutTests: XCTestCase {
    func testEveryCellCentreMapsBack() {
        for c in 1...6 { for b in UInt8(1)...4 {
            let cell=PuckCell(column:c,band:b)
            XCTAssertEqual(PuckBackLayout.cell(at:PuckBackLayout.center(of:cell)),cell)
            XCTAssertEqual(PuckBackLayout.edgeMargin(at:PuckBackLayout.center(of:cell)),6)
        } }
    }
    func testBackIsMirroredColumnZeroOnTheRight() {
        XCTAssertNil(PuckBackLayout.cell(at:PlanePoint(36,14.5)))
        XCTAssertEqual(PuckBackLayout.cell(at:PlanePoint(-36,14.5))?.column,6)
        XCTAssertEqual(PuckBackLayout.cell(at:PlanePoint(0,53.5))?.band,4)
    }
    func testOutsideGridIsNil() {
        for p in [PlanePoint(0,7.9),PlanePoint(0,60.1),PlanePoint(42.1,30),PlanePoint(-42.1,30),PlanePoint(.nan,1)] { XCTAssertNil(PuckBackLayout.cell(at:p)) }
    }
    func testCodesSitBelowTheGridAndOnTheSheet() {
        for code in PuckBackLayout.codes {
            let corners=PuckBackLayout.corners(of:code.payload)!
            XCTAssertLessThanOrEqual(corners.map(\.y).max()!+4,PuckBackLayout.firstRowV-6.5+0.5)   // quiet zone clears row 1 (0.5 mm overlap allowed)
            XCTAssertGreaterThanOrEqual(corners.map(\.y).min()!-4,PuckBackLayout.sheetMinV)
            XCTAssertGreaterThanOrEqual(corners.map(\.x).min()!-4,PuckBackLayout.sheetMinU)
            XCTAssertLessThanOrEqual(corners.map(\.x).max()!+4,PuckBackLayout.sheetMaxU)
        }
        XCTAssertNil(PuckBackLayout.corners(of:"FEEL:XX"))
    }
}

final class PointingGateTests: XCTestCase {
    /// Sheet → image: `scale` px/mm, fingers pointing at `angle` degrees (0 = image right), centred at (960,720).
    func view(scale: Double = 4, angle: Double = 180, squashV: Double = 1) -> Homography {
        let a=angle * .pi/180
        // v axis direction in image (y down); u axis is v rotated −90° in a y-up frame.
        let vx=cos(a)*scale*squashV, vy = -sin(a)*scale*squashV, ux=sin(a)*scale, uy=cos(a)*scale
        return Homography([ux,vx,960, uy,vy,720, 0,0,1])!
    }
    func testThumbUpEitherHandPasses() {
        XCTAssertEqual(PointingGate.evaluate(view(angle:180),imageWidth:1920)?.ok,true)
        XCTAssertEqual(PointingGate.evaluate(view(angle:0),imageWidth:1920)?.ok,true)
        XCTAssertEqual(PointingGate.evaluate(view(angle:150),imageWidth:1920)?.ok,true)
    }
    func testFingersUpOrDownRejected() {
        let r=PointingGate.evaluate(view(angle:90),imageWidth:1920)
        XCTAssertEqual(r?.upright,false); XCTAssertEqual(r?.ok,false)
        XCTAssertEqual(PointingGate.evaluate(view(angle:-90),imageWidth:1920)?.ok,false)
    }
    func testTooFarAndTiltedRejected() {
        XCTAssertEqual(PointingGate.evaluate(view(scale:2),imageWidth:1920)?.closeEnough,false)
        let tilted=Homography([0,-4,960, 4,0,720, 0.004,0,1])!   // strong perspective: one side much longer
        XCTAssertEqual(PointingGate.evaluate(tilted,imageWidth:1920)?.faceOn,false)
    }
    func testMirroredFitRejected() {
        let m=view().m
        let mirrored=Homography([-m[0],m[1],m[2],-m[3],m[4],m[5],0,0,1])!
        XCTAssertEqual(PointingGate.evaluate(mirrored,imageWidth:1920)?.faceOn,false)
    }
}

final class FingertipMarkerTests: XCTestCase {
    func testColourClasses() {
        XCTAssertTrue(FingertipMarker.isMarker(r:0.05,g:0.05,b:0.06))          // black tape
        XCTAssertTrue(FingertipMarker.isMarker(r:0.1,g:0.3,b:0.85))            // blue tape
        XCTAssertTrue(FingertipMarker.isMarker(r:0.15,g:0.7,b:0.25))           // green tape
        XCTAssertFalse(FingertipMarker.isMarker(r:0.95,g:0.95,b:0.93))         // paper
        XCTAssertFalse(FingertipMarker.isMarker(r:0.78,g:0.78,b:0.78))         // printed grid
        XCTAssertFalse(FingertipMarker.isMarker(r:0.85,g:0.62,b:0.5))          // skin
        XCTAssertFalse(FingertipMarker.isMarker(r:0.9,g:0.2,b:0.15))           // red
        XCTAssertFalse(FingertipMarker.isMarker(r:0.5,g:0.45,b:0.42))          // shadowed paper
    }
    func testLargestBlobCentroid() {
        var mask=[Bool](repeating:false,count:20*10)
        for x in 2..<8 { for y in 2..<8 { mask[y*20+x]=true } }     // 36-sample blob centred (4.5,4.5)
        mask[9*20+19]=true                                           // speck
        let p=FingertipMarker.locate(mask,width:20,height:10,minU:-10,minV:8,step:1)
        XCTAssertEqual(p,PlanePoint(-5.5,12.5))
    }
    func testTooSmallOrTooLargeIgnored() {
        XCTAssertNil(FingertipMarker.locate([Bool](repeating:false,count:100),width:10,height:10,minU:0,minV:0,step:1))
        XCTAssertNil(FingertipMarker.locate([Bool](repeating:true,count:40*40),width:40,height:40,minU:0,minV:0,step:1))
    }
}

final class PointingControllerTests: XCTestCase {
    let ahead=CameraPose(position:Vector3(0,1.2,0))
    func turned(_ degrees: Double) -> CameraPose {
        let a=degrees * .pi/180
        return CameraPose(position:Vector3(0,1.2,0),right:Vector3(cos(a),0,sin(a)),up:Vector3(0,1,0),back:Vector3(-sin(a),0,cos(a)))
    }
    func scene(_ t: Double, nearest: Double = 1.2, pose: CameraPose? = nil) -> CachedScene {
        CachedScene(timestamp:t,pose:pose ?? ahead,tracking:true,distances:[nil,nil,2,nearest,nil,nil,nil],target:nil)
    }
    func obs(_ t: Double, gate: Bool = true, codes: Int = 3, cell: PuckCell? = nil) -> PointingObservation {
        .init(timestamp:t,codesSeen:codes,gate:.init(faceOn:gate,upright:true,closeEnough:true),fingertip:cell.map(PuckBackLayout.center(of:)),method:cell == nil ? nil : .marker)
    }
    /// Scene frames every 0.1 s until `until`; the arm comes up at 1.0 s and reads 0.3 m from 1.0 on.
    func controller(until: Double = 3.0, pose: (Double)->CameraPose = { _ in CameraPose(position:Vector3(0,1.2,0)) }) -> PointingController {
        var c=PointingController()
        for i in 0...Int(until*10) { let t=Double(i)/10; c.record(scene(t,nearest:t>=1.0 ? 0.3 : 1.2,pose:pose(t))) }
        return c
    }
    func run(_ c: inout PointingController, _ o: [PointingObservation]) -> [PointingEvent] {
        o.flatMap { c.update($0) { cell,s in PointingDescriber.describe(cell,in:s) } }
    }
    func testArmsAfterHoldThenDescribesAfterDwell() {
        var c=controller()
        let cell=PuckCell(column:3,band:2)
        let events=run(&c,[obs(1.4),obs(1.6),obs(1.8),obs(1.9,cell:cell),obs(2.1,cell:cell),obs(2.3,cell:cell),obs(2.5,cell:cell)])
        XCTAssertEqual(events.first,.armed)
        guard case .armed(let ref)=c.phase else { return XCTFail("not armed") }
        XCTAssertEqual(ref.timestamp,0.9,accuracy:1e-9)        // newest clean frame before the arm came up
        XCTAssertEqual(events.filter { if case .described=$0 { return true }; return false }.count,1)
        XCTAssertEqual(events.last,.described(cell,"Obstacle."))
    }
    func testFrozenPacketIsTheCachedScene() {
        var c=controller()
        _=run(&c,[obs(1.4),obs(1.9)])
        XCTAssertEqual(c.frozenOutput(sequence:7)?.packet.bands,[0,0,3,2,0,0,0])
        XCTAssertEqual(c.frozenOutput(sequence:7)?.packet.sequence,7)
    }
    func testNoArmBeforeHoldOrWhenGateFails() {
        var c=controller()
        XCTAssertEqual(run(&c,[obs(1.4),obs(1.6)]),[])
        XCTAssertEqual(run(&c,[obs(1.8,gate:false),obs(2.0),obs(2.2)]),[])
        XCTAssertEqual(c.phase,.idle)
    }
    func testTurnedSinceSceneRefuses() {
        var c=controller(pose:{ $0>=1.0 ? self.turned(25) : self.ahead })
        let events=run(&c,[obs(1.4),obs(1.9)])
        XCTAssertEqual(c.phase,.refused)
        if case .refused(let text)=events.last { XCTAssertTrue(text.contains("turned")) } else { XCTFail("\(events)") }
        XCTAssertEqual(c.frozenOutput(sequence:1)?.packet.bands,Array(repeating:0,count:7))
    }
    func testExpiresAfterThreeSeconds() {
        var c=controller(until:2)
        _=run(&c,[obs(1.4),obs(1.9)])
        XCTAssertEqual(run(&c,[obs(3.85)]),[])
        XCTAssertEqual(run(&c,[obs(3.95)]),[.expired])
    }
    func testLoweringThePuckReleases() {
        var c=controller()
        _=run(&c,[obs(1.4),obs(1.9)])
        XCTAssertEqual(c.tick(now:2.4),[])
        XCTAssertEqual(c.tick(now:2.6),[.released(nil)]); XCTAssertNil(c.frozenOutput(sequence:1))
    }
    func testFlickerIsIgnoredSteadyCellDescribedOnce() {
        var c=controller()
        let a=PuckCell(column:1,band:1), b=PuckCell(column:5,band:3)
        // a and b alternate (no 0.4 s hold), then b is held from 2.6 s; repeats of b stay silent.
        let events=run(&c,[obs(1.4),obs(1.9,cell:a),obs(2.3,cell:a),obs(2.4,cell:b),obs(2.5,cell:a),obs(2.6,cell:b),obs(2.9,cell:b),obs(3.0,cell:b),obs(3.2,cell:b),obs(3.4,cell:b)])
        let described=events.compactMap { e -> PuckCell? in if case .described(let cell,_)=e { return cell }; return nil }
        XCTAssertEqual(described,[b])
    }
}

final class PointingDescriberTests: XCTestCase {
    let door=TargetObservation(bearingDegrees:-15,distance:2.1,timestamp:1,label:"Door candidate",halfWidthDegrees:12)
    func testShortFormIsJustTheName() {
        let empty=CachedScene(timestamp:1,pose:.identity,tracking:true,distances:Array(repeating:nil,count:7),target:nil)
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:6,band:2),in:empty),"Nothing measured.")
        // In the six-active-column layout, the door spans columns 2-3.
        let s=CachedScene(timestamp:1,pose:.identity,tracking:true,distances:[nil,1.2,nil,nil,0.7,nil,nil],target:door)
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:1,band:3),in:s,targetName:"Possible door"),"Obstacle.")
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:3,band:3),in:s),"Door candidate.")
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:4,band:1),in:s),"Obstacle.")
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:5,band:1),in:s),"Nothing measured.")
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:2,band:4),in:s,targetName:"Chair."),"Chair.")
    }
    func testTargetInSpanNamedFirst() {
        let t=TargetObservation(bearingDegrees:-15,distance:2.1,timestamp:1,label:"Door candidate",halfWidthDegrees:12)
        let s=CachedScene(timestamp:1,pose:.identity,tracking:true,distances:[nil,nil,1.2,nil,nil,nil,nil],target:t)
        XCTAssertEqual(PointingDescriber.describe(PuckCell(column:2,band:3),in:s,targetName:"Possible door"), "Possible door.")
    }
    func testDetailedFormKeepsDirectionAndReadings() {
        let s=CachedScene(timestamp:1,pose:.identity,tracking:true,distances:[nil,nil,1.2,nil,nil,nil,nil],target:door)
        XCTAssertEqual(PointingDescriber.describeDetailed(PuckCell(column:2,band:3),in:s,targetName:"Possible door"),
                       "Left: Possible door, 2.1 meters. Nearest reading 1.2 meters. The raised pin is closer than where you're pointing.")
    }
}

final class TwoFingerTests: XCTestCase {
    func disc(_ colors: inout [FingertipMarker.Color?], width: Int, cx: Int, cy: Int, r: Int, color: FingertipMarker.Color) {
        for y in (cy-r)...(cy+r) { for x in (cx-r)...(cx+r) where (x-cx)*(x-cx)+(y-cy)*(y-cy)<=r*r { colors[y*width+x]=color } }
    }
    func reading(_ discs: [(Int,Int,Int,FingertipMarker.Color)]) -> FingerReading {
        var colors=[FingertipMarker.Color?](repeating:nil,count:80*60)
        for d in discs { disc(&colors,width:80,cx:d.0,cy:d.1,r:d.2,color:d.3) }
        return FingerCounter.read(FingertipMarker.blobs(colors,width:80,height:60,minU:0,minV:0,step:1))
    }
    func testOneRoundBandIsOneFinger() { XCTAssertEqual(reading([(30,30,6,.dark)]),.one(PlanePoint(30,30))) }
    func testBlackAndBlueTouchingStaySeparate() {
        guard case .two(let a,let b)=reading([(30,22,7,.dark),(30,36,7,.colored)]) else { return XCTFail() }
        XCTAssertEqual(Set([a.y,b.y].map { $0.rounded() }),[22,36])
    }
    func testSameColourPressedTogetherReadsAsTwo() {
        guard case .two(let a,let b)=reading([(30,23,7,.dark),(30,36,7,.dark)]) else { return XCTFail("merged blob not split") }
        XCTAssertEqual(a.x,30,accuracy:0.5); XCTAssertEqual(abs(a.y-b.y),13,accuracy:4)
    }
    func testFarStrayBlobIgnored() { if case .one=reading([(10,30,6,.dark),(70,30,5,.dark)]) {} else { XCTFail() } }
    func testColourClasses() {
        XCTAssertEqual(FingertipMarker.color(r:0.05,g:0.05,b:0.05),.dark)
        XCTAssertEqual(FingertipMarker.color(r:0.1,g:0.3,b:0.85),.colored)
        XCTAssertNil(FingertipMarker.color(r:0.85,g:0.62,b:0.5))
    }
    func obs(_ a: PlanePoint?, _ b: PlanePoint? = nil, t: Double = 1) -> PointingObservation {
        .init(timestamp:t,codesSeen:3,gate:.init(faceOn:true,upright:true,closeEnough:true),fingertip:a,method:a == nil ? nil : .marker,secondTip:b)
    }
    func testRouteColumnNeedsFingersAlongTheColumn() {
        let c2=PuckBackLayout.center(of:PuckCell(column:2,band:2))
        let along=obs(c2,PlanePoint(c2.x+3,c2.y+16)), across=obs(c2,PlanePoint(c2.x-16,c2.y))
        XCTAssertEqual(along.fingers,2); XCTAssertEqual(along.routeColumn,2); XCTAssertNil(along.cell)
        XCTAssertNil(across.routeColumn)
        XCTAssertEqual(obs(c2).routeColumn,nil); XCTAssertEqual(obs(c2).cell,PuckCell(column:2,band:2))
        XCTAssertEqual(obs(nil,c2).fingers,0)
    }
}

final class PointingRouterTests: XCTestCase {
    let ahead=CameraPose(position:Vector3(1,1.2,2))
    func scene(_ distances: [Double?], target: TargetObservation? = nil, pose: CameraPose? = nil) -> CachedScene {
        CachedScene(timestamp:10,pose:pose ?? ahead,tracking:true,distances:distances,target:target)
    }
    func testWorldPointFollowsHeading() throws {
        let p=try XCTUnwrap(PointingRouter.worldPoint(bearing:0,distance:2,pose:ahead))
        XCTAssertEqual(p.x,1,accuracy:1e-9); XCTAssertEqual(p.z,0,accuracy:1e-9)          // ARKit forward is -z
        let right=try XCTUnwrap(PointingRouter.worldPoint(bearing:90,distance:2,pose:ahead))
        XCTAssertEqual(right.x,3,accuracy:1e-9); XCTAssertEqual(right.z,2,accuracy:1e-9)
        // Facing +x (turned 90° right): straight ahead is +x.
        let turned=CameraPose(position:.zero,right:Vector3(0,0,1),up:Vector3(0,1,0),back:Vector3(-1,0,0))
        let q=try XCTUnwrap(PointingRouter.worldPoint(bearing:0,distance:3,pose:turned))
        XCTAssertEqual(q.x,3,accuracy:1e-9); XCTAssertEqual(q.z,0,accuracy:1e-9)
    }
    func testTargetInColumnIsTheGoal() {
        let t=TargetObservation(bearingDegrees:-19,distance:2.5,timestamp:10,label:"Door candidate",halfWidthDegrees:8)
        guard case .route(let r,let spoken)=PointingRouter.plan(column:2,scene:scene([nil,nil,1.5,nil,nil,nil,nil],target:t),targetName:"Possible door") else { return XCTFail() }
        XCTAssertTrue(r.toTarget); XCTAssertEqual(r.distance,2.5)
        let expected=PointingRouter.worldPoint(bearing:-19,distance:2.5,pose:ahead)!
        XCTAssertEqual(r.goal.x,expected.x,accuracy:1e-9); XCTAssertEqual(r.goal.z,expected.z,accuracy:1e-9)
        XCTAssertEqual(spoken,"Route set to possible door, left, 2.5 meters. Lower the puck to start.")
    }
    func testObstacleStopsShort() {
        guard case .route(let r,let spoken)=PointingRouter.plan(column:4,scene:scene([nil,nil,nil,nil,3,nil,nil]),targetName:nil) else { return XCTFail() }
        XCTAssertFalse(r.toTarget); XCTAssertEqual(r.distance,2.5)
        XCTAssertEqual(spoken,"Route set slightly right, about 2.5 meters, stopping short of what's there. Lower the puck to start.")
    }
    func testNothingMeasuredOrTooCloseRefuses() {
        if case .route=PointingRouter.plan(column:3,scene:scene(Array(repeating:nil,count:7)),targetName:nil) { XCTFail("routed into the unknown") }
        // 1.9 m reading → goal 1.4 m: beyond the guide's 1 m arrival + 0.3 m, so a real route.
        if case .route(let r,_)=PointingRouter.plan(column:3,scene:scene([nil,nil,nil,1.9,nil,nil,nil]),targetName:nil) { XCTAssertFalse(r.highlightOnly) } else { XCTFail("1.4 m goal should route") }
    }
    func testTooCloseTapsTheColumnSilently() {
        // 1.7 m reading → goal 1.2 m would arrive at once: tap column 3 instead, band 3, no speech.
        guard case .route(let r,let spoken)=PointingRouter.plan(column:3,scene:scene([nil,nil,nil,1.7,nil,nil,nil]),targetName:nil) else { return XCTFail() }
        XCTAssertTrue(r.highlightOnly); XCTAssertEqual(r.column,3); XCTAssertEqual(r.band,3); XCTAssertEqual(spoken,"")
        let near=TargetObservation(bearingDegrees:0,distance:1.1,timestamp:10,label:"Chair")
        guard case .route(let t,let quiet)=PointingRouter.plan(column:4,scene:scene(Array(repeating:nil,count:7),target:near),targetName:nil) else { return XCTFail() }
        XCTAssertTrue(t.highlightOnly); XCTAssertTrue(t.toTarget); XCTAssertEqual(t.band,2); XCTAssertEqual(quiet,"")
    }
}

final class TwoFingerControllerTests: XCTestCase {
    func run(_ c: inout PointingController, _ o: [PointingObservation]) -> [PointingEvent] {
        o.flatMap { c.update($0,targetName:nil) { cell,s in PointingDescriber.describe(cell,in:s) } }
    }
    func armed() -> PointingController {
        var c=PointingController()
        for i in 0...20 { let t=Double(i)/10; c.record(CachedScene(timestamp:t,pose:CameraPose(position:Vector3(0,1.2,0)),tracking:true,distances:[nil,nil,2.5,1.2,nil,nil,nil],target:nil)) }
        _=run(&c,[o(1.4,nil),o(1.9,nil)])
        return c
    }
    func o(_ t: Double, _ column: Int?, single: Bool = false) -> PointingObservation {
        let tip=column.map { PuckBackLayout.center(of:PuckCell(column:$0,band:2)) }
        return .init(timestamp:t,codesSeen:3,gate:.init(faceOn:true,upright:true,closeEnough:true),fingertip:tip,method:tip == nil ? nil : .marker,
                     secondTip:single ? nil : tip.map { PlanePoint($0.x,$0.y+16) })
    }
    func testTwoFingersHeldSetRouteOnceAndHandItOverOnRelease() {
        var c=armed()
        let events=run(&c,[o(2.0,2),o(2.3,2),o(2.6,2),o(2.8,2)])
        let routes=events.compactMap { e -> PointingRoute? in if case .routeSet(let r,_)=e { return r }; return nil }
        XCTAssertEqual(routes.map(\.column),[2]); XCTAssertEqual(routes.first?.distance ?? 0,2.0,accuracy:1e-9)
        XCTAssertEqual(c.pendingRoute?.column,2)
        XCTAssertEqual(c.tick(now:3.5),[.released(routes.first)]); XCTAssertNil(c.pendingRoute)
    }
    func testTooShortHoldDoesNothingAndOneFingerStillDescribes() {
        var c=armed()
        XCTAssertEqual(run(&c,[o(2.0,2),o(2.4,2)]).count,0)          // 0.4 s < 0.6 s
        let events=run(&c,[o(2.5,3,single:true),o(2.9,3,single:true)])
        if case .described(let cell,_)=events.last { XCTAssertEqual(cell,PuckCell(column:3,band:2)) } else { XCTFail("\(events)") }
    }
    func testRefusedRouteKeepsPointing() {
        var c=armed()
        let events=run(&c,[o(2.0,5),o(2.6,5)])                       // column 5: nothing measured
        if case .refused=events.last {} else { XCTFail("\(events)") }
        if case .armed=c.phase {} else { XCTFail("phase \(c.phase)") }
        XCTAssertNil(c.pendingRoute)
    }
}
