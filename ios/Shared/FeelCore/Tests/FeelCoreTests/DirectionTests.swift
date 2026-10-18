import XCTest
@testable import FeelCore

// MARK: Hand sign

final class HandSignTests: XCTestCase {
    /// Builds an upright hand (fingers toward -y), palm 100 px. Each finger is extended or folded;
    /// `spread` fans the index/middle apart by ± degrees.
    static func hand(index: Bool, middle: Bool, ring: Bool, little: Bool, spread: Double = 12, rotate: Double = 0, scale: Double = 1, origin: PlanePoint = PlanePoint(500,500)) -> HandJoints {
        let r=rotate * .pi/180
        func place(_ x: Double, _ y: Double) -> PlanePoint {
            PlanePoint(origin.x+(x*cos(r)-y*sin(r))*scale, origin.y+(x*sin(r)+y*cos(r))*scale)
        }
        func finger(_ baseX: Double, _ extended: Bool, _ angle: Double) -> HandJoints.Finger {
            let a=angle * .pi/180, dx=sin(a), dy = -cos(a)
            let mcp=(baseX,-100.0)
            if extended {
                return .init(mcp:place(mcp.0,mcp.1),pip:place(mcp.0+dx*40,mcp.1+dy*40),tip:place(mcp.0+dx*85,mcp.1+dy*85))
            }
            // Curled: PIP just past the knuckle, tip folded back toward the palm.
            return .init(mcp:place(mcp.0,mcp.1),pip:place(mcp.0,mcp.1-25),tip:place(mcp.0,mcp.1+15))
        }
        return HandJoints(wrist:place(0,0),index:finger(-25,index,-spread),middle:finger(-5,middle,spread),ring:finger(15,ring,0),little:finger(32,little,0))
    }

    func testVSignAnyOrientation() {
        for angle in stride(from:0.0,to:360,by:30) {
            XCTAssertTrue(HandSign.isVSign(Self.hand(index:true,middle:true,ring:false,little:false,rotate:angle)),"\(angle)°")
        }
    }
    func testVSignAnySize() {
        for scale in [0.3,1,4] { XCTAssertTrue(HandSign.isVSign(Self.hand(index:true,middle:true,ring:false,little:false,scale:scale))) }
    }
    func testOtherHandShapesRejected() {
        let shapes: [(Bool,Bool,Bool,Bool,String)]=[
            (true,false,false,false,"pointing"),(false,false,false,false,"fist"),(true,true,true,true,"open palm"),
            (true,true,true,false,"three fingers"),(false,true,false,false,"middle only"),(true,false,false,true,"horns")]
        for (i,m,r,l,name) in shapes { XCTAssertFalse(HandSign.isVSign(Self.hand(index:i,middle:m,ring:r,little:l)),name) }
    }
    func testTwoFingersTogetherIsNotAV() {
        XCTAssertFalse(HandSign.isVSign(Self.hand(index:true,middle:true,ring:false,little:false,spread:1)))
    }
    func testMissingJointsRejected() {
        var h=Self.hand(index:true,middle:true,ring:false,little:false)
        h.ring.tip=nil; XCTAssertFalse(HandSign.isVSign(h))
        h=Self.hand(index:true,middle:true,ring:false,little:false); h.wrist=nil; XCTAssertFalse(HandSign.isVSign(h))
    }
    func testDistanceEstimate() {
        let h=Self.hand(index:true,middle:true,ring:false,little:false)
        // Palm is about 100 px; focal 1500 px → 1500 × 0.095 / 100.
        let d=HandSign.estimatedDistance(h,focalPixels:1500)!
        XCTAssertEqual(d,1500*0.095/hypot(5,100),accuracy:1e-9)
        XCTAssertNil(HandSign.estimatedDistance(h,focalPixels:0))
    }
    func testFarHandDoesNotCount() {
        XCTAssertTrue(HandSignObservation(timestamp:0,vSign:true,distance:0.35).counts)
        XCTAssertFalse(HandSignObservation(timestamp:0,vSign:true,distance:1.4).counts)
        XCTAssertFalse(HandSignObservation(timestamp:0,vSign:true,distance:nil).counts)
        XCTAssertFalse(HandSignObservation(timestamp:0,vSign:false,distance:0.3).counts)
    }

    private func run(_ trigger: inout HandSignTrigger, _ seq: [(Double,Bool)]) -> [Double] {
        seq.compactMap { t,v in trigger.update(.init(timestamp:t,vSign:v,distance:0.3)) ? t : nil }
    }
    func testTriggerNeedsHoldAndFiresOnce() {
        var trigger=HandSignTrigger()
        let held=stride(from:0.0,through:2.0,by:0.15).map { ($0,true) }
        XCTAssertEqual(run(&trigger,held),[0.6])
    }
    func testBriefFlashDoesNotFire() {
        var trigger=HandSignTrigger()
        XCTAssertEqual(run(&trigger,[(0,true),(0.15,true),(0.3,true),(0.45,false),(0.6,false),(1.0,true),(1.15,false)]),[])
    }
    func testGapRestartsHold() {
        var trigger=HandSignTrigger()
        XCTAssertEqual(run(&trigger,[(0,true),(0.15,true),(0.3,true),(0.9,true),(1.05,true),(1.2,true),(1.35,true),(1.5,true)]),[1.5])
    }
    func testReleaseThenFireAgain() {
        var trigger=HandSignTrigger()
        var seq=stride(from:0.0,through:0.9,by:0.15).map { ($0,true) }
        seq += stride(from:1.05,through:2.0,by:0.15).map { ($0,false) }
        seq += stride(from:2.1,through:2.9,by:0.15).map { ($0,true) }
        XCTAssertEqual(run(&trigger,seq).count,2)
    }
    func testShortDropDoesNotRearm() {
        var trigger=HandSignTrigger()
        var seq=stride(from:0.0,through:0.9,by:0.15).map { ($0,true) }
        seq += [(1.05,false),(1.2,false)]
        seq += stride(from:1.35,through:2.5,by:0.15).map { ($0,true) }
        XCTAssertEqual(run(&trigger,seq).count,1)
    }
}

// MARK: Floor grid and route

final class FloorGridTests: XCTestCase {
    /// Fills a rectangle with floor or obstacle points, several hits per cell.
    static func paint(_ grid: inout FloorGrid, x: ClosedRange<Double>, z: ClosedRange<Double>, height: Double, camera: Vector3 = .zero) {
        var points: [Vector3]=[]
        for px in stride(from:x.lowerBound,through:x.upperBound,by:0.05) { for pz in stride(from:z.lowerBound,through:z.upperBound,by:0.05) {
            points.append(Vector3(px,height,pz))
        } }
        for _ in 0..<3 { grid.integrate(points:points,floorY:0,camera:camera) }
    }
    static func room() -> FloorGrid {
        var g=FloorGrid(); paint(&g,x:-3...3,z:(-3.9)...0.5,height:0); return g
    }

    func testCellStates() {
        var g=FloorGrid()
        XCTAssertEqual(g.state(g.cell(Vector3(1,0,1))),.unknown)
        Self.paint(&g,x:0...0.3,z:0...0.3,height:0)
        XCTAssertEqual(g.state(g.cell(Vector3(0.15,0,0.15))),.free)
        Self.paint(&g,x:1...1.3,z:0...0.3,height:0.2)
        XCTAssertEqual(g.state(g.cell(Vector3(1.15,0,0.15))),.blocked, "a 20 cm bag blocks")
        Self.paint(&g,x:2...2.3,z:0...0.3,height:2.5)
        XCTAssertEqual(g.state(g.cell(Vector3(2.15,0,0.15))),.unknown, "ceiling is ignored")
    }
    func testLowFloorObjectBelowThresholdIsFloor() {
        var g=FloorGrid(); Self.paint(&g,x:0...0.3,z:0...0.3,height:0.05)
        XCTAssertEqual(g.state(g.cell(Vector3(0.15,0,0.15))),.free)
    }
    func testObstacleClearsWhenFloorSeenAgain() {
        var g=FloorGrid(); let c=g.cell(Vector3(0.15,0,0.15))
        Self.paint(&g,x:0...0.3,z:0...0.3,height:1.0); XCTAssertEqual(g.state(c),.blocked)
        for _ in 0..<5 { Self.paint(&g,x:0...0.3,z:0...0.3,height:0) }
        XCTAssertEqual(g.state(c),.free)
    }
    func testPointsBeyondRangeIgnored() {
        var g=FloorGrid(); Self.paint(&g,x:5...5.3,z:0...0.3,height:0)
        XCTAssertEqual(g.cellCount,0)
    }
    func testFarCellsForgotten() {
        var g=FloorGrid(); Self.paint(&g,x:0...0.3,z:0...0.3,height:0)
        for _ in 0..<60 { g.integrate(points:[],floorY:0,camera:Vector3(20,0,0)) }
        XCTAssertEqual(g.cellCount,0)
    }
    func testStraightRouteInOpenRoom() {
        let g=Self.room()
        let path=g.route(from:.zero,to:Vector3(0,0,-3))!
        XCTAssertLessThan(abs(path.last!.x),0.2)
        XCTAssertTrue(path.allSatisfy { abs($0.x)<0.2 })
    }
    func testRouteGoesAroundObstacle() {
        var g=Self.room()
        // A table across the direct line, open on the left (−x).
        Self.paint(&g,x:(-0.6)...2.5,z:(-1.7)...(-1.3),height:0.7)
        let path=g.route(from:.zero,to:Vector3(0,0,-3))!
        XCTAssertTrue(path.contains { $0.x < -0.6 }, "route passes left of the table")
        for p in path { XCTAssertNotEqual(g.state(g.cell(p)),.blocked) }
    }
    func testFloorObstacleBelowSectorWindowStillAvoided() {
        var g=Self.room()
        Self.paint(&g,x:(-0.4)...0.4,z:(-1.2)...(-0.9),height:0.25)
        let path=g.route(from:.zero,to:Vector3(0,0,-3))!
        XCTAssertFalse(path.contains { abs($0.x)<0.4 && $0.z < -0.9 && $0.z > -1.2 })
    }
    func testBlockedReturnsNil() {
        var g=Self.room()
        Self.paint(&g,x:(-6)...6,z:(-1.7)...(-1.3),height:1.0, camera:Vector3(0,0,-1))
        XCTAssertNil(g.route(from:.zero,to:Vector3(0,0,-3),margin:2))
    }
    func testTargetOnAWallIsReachable() {
        var g=Self.room()
        Self.paint(&g,x:(-3)...3,z:(-4.2)...(-3.95),height:1.0, camera:Vector3(0,0,-2))
        let path=g.route(from:.zero,to:Vector3(0,0,-4.05))
        XCTAssertNotNil(path, "goal is any open cell near the target, so a door in a wall works")
    }
    func testUnknownAroundFeetIsPassable() {
        var g=FloorGrid(); Self.paint(&g,x:(-2)...2,z:(-3)...(-1),height:0)
        XCTAssertNotNil(g.route(from:.zero,to:Vector3(0,0,-2.5)))
    }
}

final class RouteHintTests: XCTestCase {
    func pose(facing degrees: Double) -> CameraPose {
        // Yaw right-positive: forward = (sin, 0, -cos); back = -forward.
        let a=degrees * .pi/180
        return CameraPose(position:.zero,right:Vector3(cos(a),0,sin(a)),up:Vector3(0,1,0),back:Vector3(-sin(a),0,cos(a)))
    }
    func testBearingSignAndLookahead() {
        let path=[Vector3(0,0,0),Vector3(0.5,0,-0.5),Vector3(1,0,-1),Vector3(1,0,-3)]
        let hint=RouteHint.make(path:path,pose:pose(facing:0),target:Vector3(1,0,-3),timestamp:0,label:"door")!
        XCTAssertEqual(hint.status,.route)
        XCTAssertEqual(hint.bearingDegrees,45,accuracy:1)
        XCTAssertEqual(hint.targetDistance,hypot(1,3),accuracy:1e-9)
    }
    func testTurningChangesBearing() {
        let path=[Vector3(0,0,0),Vector3(0,0,-2)]
        XCTAssertEqual(RouteHint.make(path:path,pose:pose(facing:90),target:Vector3(0,0,-2),timestamp:0,label:"")!.bearingDegrees,-90,accuracy:1e-6)
        XCTAssertEqual(abs(RouteHint.make(path:path,pose:pose(facing:180),target:Vector3(0,0,-2),timestamp:0,label:"")!.bearingDegrees),180,accuracy:1e-6)
    }
    func testNoPathIsBlocked() {
        let hint=RouteHint.make(path:nil,pose:pose(facing:0),target:Vector3(0,0,-2),timestamp:0,label:"")!
        XCTAssertEqual(hint.status,.blocked)
    }
}

// MARK: Cues

final class DirectionCueTests: XCTestCase {
    private func dots(_ f: [UInt8]) -> String { f.map { $0==0 ? "." : String($0) }.joined() }
    private func hint(_ bearing: Double, distance: Double = 3, at t: Double = 0, status: RouteHint.Status = .route) -> RouteHint {
        RouteHint(timestamp:t,status:status,bearingDegrees:bearing,targetDistance:distance,routeLength:distance,label:"door")
    }

    func testClassification() {
        let cases: [(Double,DirectionCue)]=[(0,.straight),(14,.straight),(-14,.straight),(17,.bear(column:5)),(20,.bear(column:5)),(40,.bear(column:6)),
                                            (-30,.bear(column:2)),(60,.turnRight),(-100,.turnLeft),(150,.turnAround),(-179,.turnAround)]
        for (b,cue) in cases { XCTAssertEqual(DirectionCue.classify(hint(b),previous:nil),cue,"\(b)") }
        XCTAssertEqual(DirectionCue.classify(hint(30,distance:0.8),previous:nil),.arrived)
        XCTAssertNil(DirectionCue.classify(hint(0,status:.blocked),previous:nil))
    }
    func testHysteresis() {
        XCTAssertEqual(DirectionCue.classify(hint(18),previous:.straight),.straight)
        XCTAssertEqual(DirectionCue.classify(hint(12),previous:.bear(column:4)),.bear(column:4))
        XCTAssertEqual(DirectionCue.classify(hint(-12),previous:.bear(column:3)),.bear(column:3))
        XCTAssertEqual(DirectionCue.classify(hint(52),previous:.turnRight),.turnRight)
    }
    func testFrames() {
        XCTAssertEqual(DirectionCue.straight.frames.map(dots).last,".234432")
        XCTAssertEqual(DirectionCue.bear(column:5).frames.map(dots),["....4..","....44.",".....4."])
        XCTAssertEqual(DirectionCue.turnRight.frames.map(dots),["....1..","....2..","....3..","....4..","....44.",".....44","......4"])
        XCTAssertEqual(DirectionCue.turnLeft.frames.map(dots).last,".4.....")
        XCTAssertEqual(DirectionCue.turnAround.frames.map(dots),["...44..","...33..","...22..","...11.."])
        XCTAssertEqual(DirectionCue.arrived.frames.map(dots),["...44..",".......","...44..","......."])
    }
    func testAllFramesWireLegalAndDistinct() throws {
        let all: [DirectionCue]=[.straight,.turnLeft,.turnRight,.turnAround,.arrived]+[1,2,3,4,5,6].map { .bear(column:$0) }
        for cue in all { for f in cue.frames { _=try FeelPacket(sequence:0,bands:f) } }
        XCTAssertEqual(Set(all.map { $0.frames.map(dots).joined(separator:"|") }).count,all.count)
    }
    func testNoticeableDifference() {
        XCTAssertFalse(DirectionCue.bear(column:4).noticeablyDifferent(from:.bear(column:5)))
        XCTAssertTrue(DirectionCue.bear(column:4).noticeablyDifferent(from:.bear(column:6)))
        XCTAssertTrue(DirectionCue.bear(column:2).noticeablyDifferent(from:.bear(column:4)))
        XCTAssertTrue(DirectionCue.straight.noticeablyDifferent(from:nil))
        XCTAssertFalse(DirectionCue.turnLeft.noticeablyDifferent(from:.turnLeft))
    }
}

final class CuePlayerTests: XCTestCase {
    private func dots(_ f: [UInt8]) -> String { f.map { $0==0 ? "." : String($0) }.joined() }
    private func base(_ bands: [UInt8] = [0,0,2,0,0,3,0], state: GuidanceState = .live) -> EncoderOutput {
        EncoderOutput(packet:try! FeelPacket(sequence:9,bands:bands,highlight:5),state:state)
    }
    func testPlaysOnceThenReturnsToBase() {
        var p=CuePlayer(); p.play(.bear(column:5),now:0)
        let shown=(0..<6).map { dots(p.apply(to:base(),now:Double($0)*0.1).packet.bands) }
        XCTAssertEqual(shown,["....4..","....44.",".....4.","..2..3.","..2..3.","..2..3."])
        XCTAssertNil(p.playing)
    }
    func testCueFramesKeepSequenceAndDropHighlight() {
        var p=CuePlayer(); p.play(.straight,now:0)
        let out=p.apply(to:base(),now:0)
        XCTAssertEqual(out.packet.sequence,9); XCTAssertEqual(out.packet.highlight,255)
    }
    func testNearObstacleHoldsThenRestarts() {
        var p=CuePlayer(); p.play(.bear(column:5),now:0)
        _=p.apply(to:base(),now:0)
        let near=base([0,1,0,0,0,0,0])
        XCTAssertEqual(p.apply(to:near,now:0.1),near)
        XCTAssertEqual(dots(p.apply(to:base(),now:0.5).packet.bands),"....4..","restarts from the first frame")
    }
    func testLongObstacleDropsCue() {
        var p=CuePlayer(); p.play(.turnRight,now:0)
        let near=base([0,1,0,0,0,0,0])
        _=p.apply(to:near,now:0); _=p.apply(to:near,now:2.5)
        XCTAssertNil(p.playing)
        XCTAssertEqual(p.apply(to:base(),now:2.6),base())
    }
    func testNonLiveStateCancels() {
        var p=CuePlayer(); p.play(.straight,now:0)
        let lost=EncoderOutput(packet:.neutral(sequence:1),state:.trackingLost)
        XCTAssertEqual(p.apply(to:lost,now:0),lost); XCTAssertNil(p.playing)
    }
    func testJitter() {
        var p=CuePlayer(); p.play(.bear(column:5),now:0)
        XCTAssertEqual([0,0.13,0.17,0.32].map { dots(p.apply(to:base(),now:$0).packet.bands) },["....4..","....44.",".....4.","..2..3."])
    }
}

final class DirectionGuideTests: XCTestCase {
    private func hint(_ bearing: Double, at t: Double, distance: Double = 3, status: RouteHint.Status = .route) -> RouteHint {
        RouteHint(timestamp:t,status:status,bearingDegrees:bearing,targetDistance:distance,routeLength:distance,label:"door")
    }
    func testNothingWithoutSign() {
        var g=DirectionGuide()
        for t in stride(from:0.0,to:5,by:0.1) { XCTAssertNil(g.update(now:t,sign:false,hint:hint(60,at:t)).play) }
        XCTAssertFalse(g.active)
    }
    func testSignStartsAndPlaysCurrentCue() {
        var g=DirectionGuide()
        let r=g.update(now:1,sign:true,hint:hint(0,at:1))
        XCTAssertEqual(r.play,.straight); XCTAssertEqual(r.events,[.started(.straight)]); XCTAssertTrue(g.active)
    }
    func testSignWithoutTarget() {
        var g=DirectionGuide()
        XCTAssertEqual(g.update(now:1,sign:true,hint:nil).events,[.noTarget])
        XCTAssertEqual(g.update(now:5,sign:true,hint:hint(0,at:1)).events,[.noTarget],"stale hint")
        XCTAssertFalse(g.active)
    }
    func testSteadyRouteNeverRepeats() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(0,at:0))
        for t in stride(from:0.1,to:10,by:0.1) { XCTAssertNil(g.update(now:t,sign:false,hint:hint(5*sin(t),at:t)).play) }
    }
    func testChangePlaysOnceAfterItHolds() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(0,at:0))
        var played: [(Double,DirectionCue)]=[]
        for t in stride(from:2.0,through:6,by:0.1) {
            if let c=g.update(now:t,sign:false,hint:hint(80,at:t)).play { played.append((t,c)) }
        }
        XCTAssertEqual(played.count,1); XCTAssertEqual(played[0].1,.turnRight)
        XCTAssertEqual(played[0].0,2.8,accuracy:0.05)
    }
    func testBriefWobbleIgnored() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(0,at:0))
        for t in stride(from:2.0,through:2.5,by:0.1) { XCTAssertNil(g.update(now:t,sign:false,hint:hint(80,at:t)).play) }
        for t in stride(from:2.6,through:5,by:0.1) { XCTAssertNil(g.update(now:t,sign:false,hint:hint(0,at:t)).play) }
    }
    func testSignAgainRepeats() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(30,at:0))
        let r=g.update(now:3,sign:true,hint:hint(30,at:3))
        XCTAssertEqual(r.play,.bear(column:6)); XCTAssertEqual(r.events,[.repeated(.bear(column:6))])
    }
    func testArrivalEndsGuidance() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(0,at:0))
        var events: [GuideEvent]=[]
        for t in stride(from:2.0,through:4,by:0.1) { events += g.update(now:t,sign:false,hint:hint(0,at:t,distance:0.8)).events }
        XCTAssertEqual(events,[.arrived]); XCTAssertFalse(g.active)
    }
    func testTargetLostEndsGuidance() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(0,at:0))
        var events: [GuideEvent]=[]
        for t in stride(from:0.1,through:5,by:0.1) { events += g.update(now:t,sign:false,hint:nil).events }
        XCTAssertEqual(events,[.lost]); XCTAssertFalse(g.active)
    }
    func testBlockedRouteReportedOnceThenRecovered() {
        var g=DirectionGuide(); _=g.update(now:0,sign:true,hint:hint(0,at:0))
        var events: [GuideEvent]=[], plays: [DirectionCue]=[]
        for t in stride(from:0.1,through:2,by:0.1) { events += g.update(now:t,sign:false,hint:hint(0,at:t,status:.blocked)).events }
        for t in stride(from:2.1,through:4,by:0.1) { let r=g.update(now:t,sign:false,hint:hint(0,at:t)); events += r.events; if let c=r.play { plays.append(c) } }
        XCTAssertEqual(events.first,.noRoute); XCTAssertEqual(events.filter { $0 == .noRoute }.count,1)
        XCTAssertEqual(plays,[.straight],"a reopened route is announced even in the same direction")
    }
}
