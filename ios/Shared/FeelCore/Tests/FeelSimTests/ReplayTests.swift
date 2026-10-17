import XCTest
import FeelCore
@testable import FeelSim

final class RecordingTests: XCTestCase {
    let k=CameraIntrinsics(fx:192.67,fy:192.67,cx:128,cy:96)

    func testRoundTripKeepsEveryField() throws {
        let depth=try XCTUnwrap(DepthFrame(width:3,height:2,depths:[0.5,1,1.5,2,4.25,.nan],confidence:[0,1,2,2,1,0],intrinsics:k))
        let target=CapturedTarget(position:Vector3(0.6,1,-2),timestamp:0.8,confidence:0.9,label:"door",halfWidthMeters:0.4)
        let frames=[RecordedFrame(timestamp:1.25,trackingNormal:true,pose:.identity,floorY:-1.2,target:target,depth:depth),
                    RecordedFrame(timestamp:1.35,trackingNormal:false,pose:.identity,floorY:nil,depth:nil)]
        var data=try SessionRecording.start(RecordingInfo(source:"iphone",createdAt:"2026-10-17T09:00:00Z",cameraHeight:1.2,note:"hallway"))
        for frame in frames { data.append(try SessionRecording.encode(frame)) }
        let decoded=try SessionRecording.decode(data)
        XCTAssertEqual(decoded.info.note,"hallway"); XCTAssertEqual(decoded.info.cameraHeight,1.2)
        XCTAssertEqual(decoded.frames.count,2)
        XCTAssertEqual(decoded.frames[0].target,target); XCTAssertEqual(decoded.frames[0].floorY,-1.2)
        XCTAssertEqual(decoded.frames[0].depth?.confidence,depth.confidence)
        XCTAssertEqual(decoded.frames[0].depth?.depths.prefix(5),depth.depths.prefix(5))
        XCTAssertTrue(decoded.frames[0].depth!.depths[5].isNaN)
        XCTAssertNil(decoded.frames[1].depth); XCTAssertFalse(decoded.frames[1].trackingNormal); XCTAssertNil(decoded.frames[1].floorY)
    }

    func testCorruptFilesAreRejected() throws {
        XCTAssertThrowsError(try SessionRecording.decode(Data("NOTFEEL!".utf8))) { XCTAssertEqual($0 as? SessionRecording.Failure,.badMagic) }
        var data=try SessionRecording.start(RecordingInfo(source:"iphone",createdAt:"x"))
        let frame=RecordedFrame(timestamp:0,trackingNormal:true,pose:.identity,floorY:0,
                                depth:DepthFrame(width:2,height:1,depths:[1,1],confidence:[2,2],intrinsics:k))
        data.append(try SessionRecording.encode(frame))
        XCTAssertThrowsError(try SessionRecording.decode(data.dropLast(3))) { XCTAssertEqual($0 as? SessionRecording.Failure,.truncated) }
        XCTAssertNil(DepthFrame(width:2,height:2,depths:[1],confidence:[1],intrinsics:k))
    }
}

final class SceneReplayTests: XCTestCase {
    func scene(_ json: String) throws -> [RecordedFrame] {
        var renderer=try SceneRenderer(JSONDecoder().decode(SceneSpec.self,from:Data(json.utf8)))
        return try SessionRecording.decode(renderer.render()).frames
    }
    let wall = #"{"kind":"box","min":[-10,0,-1.4],"max":[10,3,-1.2]}"#

    func testWallRangesFollowColumnEdgeBearings() throws {
        let frames=try scene(#"{"duration":0.05,"path":[{"t":0,"x":0,"z":0}],"objects":[\#(wall)]}"#)
        let distances=DepthFrameProcessor.process(try XCTUnwrap(frames[0].depth),pose:frames[0].pose,floorY:frames[0].floorY).distances
        // Nearest sampled point per sector: the wall at 1.2 m divided by cos of the sector's innermost sampled bearing.
        XCTAssertEqual(distances[3]!,1.2,accuracy:0.002)
        for (column,edge) in [(2,6.43),(4,6.43),(1,19.29),(5,19.29),(0,32.14),(6,32.14)] {
            XCTAssertEqual(distances[column]!,1.2/cos(edge * .pi/180),accuracy:0.02,"column \(column)")
        }
    }

    func testRenderIsDeterministicAndSeeded() throws {
        func render(_ seed: Int) throws -> Data {
            var r=try SceneRenderer(JSONDecoder().decode(SceneSpec.self,from:Data(#"{"duration":0.3,"path":[{"t":0,"x":0,"z":0}],"objects":[\#(wall)],"sensor":{"noise":0.01,"outlierRate":0.001,"seed":\#(seed)}}"#.utf8)))
            return try r.render()
        }
        XCTAssertEqual(try render(3),try render(3))
        XCTAssertNotEqual(try render(3),try render(4))
    }

    func testInvalidScenesAreRejected() {
        for json in [#"{"duration":-1,"path":[{"t":0,"x":0,"z":0}]}"#,
                     #"{"duration":1,"path":[]}"#,
                     #"{"duration":1,"path":[{"t":1,"x":0,"z":0},{"t":0,"x":0,"z":0}]}"#,
                     #"{"duration":1,"path":[{"t":0,"x":0,"z":0}],"objects":[{"kind":"box","min":[1,0,0],"max":[0,1,1]}]}"#,
                     #"{"duration":1,"path":[{"t":0,"x":0,"z":0}],"objects":[{"kind":"sphere"}]}"#] {
            XCTAssertThrowsError(try SceneRenderer(JSONDecoder().decode(SceneSpec.self,from:Data(json.utf8))),json)
        }
    }

    func testTrackingLossFrameGapAndUncalibratedGoNeutral() throws {
        let frames=try scene(#"{"duration":3,"path":[{"t":0,"x":0,"z":0}],"objects":[\#(wall)],"trackingLost":[[1,1.5]],"frameGaps":[[2,2.6]]}"#)
        let ticks=SessionReplayer.run(frames)
        func at(_ t: Double) -> ReplayTick { ticks.min { abs($0.t-t)<abs($1.t-t) }! }
        XCTAssertEqual(at(0.55).state,"live"); XCTAssertEqual(at(0.55).bands,[2,2,2,2,2,2,2])
        XCTAssertEqual(at(1.25).state,"trackingLost"); XCTAssertEqual(at(1.25).bands,[0,0,0,0,0,0,0])
        XCTAssertEqual(at(2.45).state,"staleDepth"); XCTAssertEqual(at(2.45).bands,[0,0,0,0,0,0,0])
        XCTAssertEqual(at(2.85).state,"live")
        XCTAssertEqual(Set(ticks.map(\.seq)).count,ticks.count,"one fresh sequence number per tick")
        let uncalibrated=SessionReplayer.run(try scene(#"{"duration":1,"path":[{"t":0,"x":0,"z":0}],"objects":[\#(wall)],"floorCalibrated":false}"#))
        XCTAssertTrue(uncalibrated.allSatisfy { $0.state == "uncalibrated" || $0.state == "staleDepth" })
        XCTAssertTrue(uncalibrated.allSatisfy { $0.bands == [0,0,0,0,0,0,0] })
    }

    func testDetectorCadenceAndFreshness() throws {
        func highlights(latency: Double) throws -> [UInt8] {
            let frames=try scene(#"{"duration":4,"path":[{"t":0,"x":0,"z":0}],"objects":[{"kind":"box","min":[-10,0,-2.2],"max":[10,3,-2.0]}],"target":{"position":[0.6,1.0,-2.0],"label":"door","latency":\#(latency)}}"#)
            return SessionReplayer.run(frames).filter { $0.t>=1 && $0.t<=4 }.map(\.highlight)
        }
        XCTAssertTrue(try highlights(latency:0.1).allSatisfy { $0 == 4 },"0.1 s inference keeps every detection under 0.5 s old")
        XCTAssertTrue(try highlights(latency:0.2).contains(255),"0.2 s inference lets the cached detection expire between results")
        XCTAssertTrue(try highlights(latency:0.6).allSatisfy { $0 == 255 },"a result older than 0.5 s at completion is discarded")
    }

    func testTurningRightMovesObstacleTowardCentre() throws {
        let frames=try scene(#"{"duration":4,"path":[{"t":0,"x":0,"z":0,"yaw":0},{"t":4,"x":0,"z":0,"yaw":26.565}],"objects":[{"kind":"cylinder","center":[1,-2],"radius":0.1,"height":2}]}"#)
        let ticks=SessionReplayer.run(frames)
        XCTAssertEqual(ticks.first { $0.t>0.2 }!.bands,[0,0,0,0,0,3,0])
        XCTAssertEqual(ticks.last { $0.frame == 4 && $0.state == "live" }!.bands,[0,0,0,3,0,0,0])
    }
}
