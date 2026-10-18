import XCTest
@testable import FeelCore

final class PersistentMemoryTests:XCTestCase {
    let map="550E8400-E29B-41D4-A716-446655440000",anchor="550E8400-E29B-41D4-A716-446655440001"
    func archive() throws -> PersistentMemoryArchive {
        var memory=SpatialMemoryManager(); try memory.begin(session:"original")
        let sample=MemoryPose(session:"original",pose:.identity,timestamp:0,tracking:true)
        try memory.remember(id:"desk",name:"Desk",sample:sample,now:0)
        try memory.setReturnPoint(sample:sample,now:0); try memory.recall(id:"desk")
        return try PersistentMemoryArchive(mapID:map,anchorID:anchor,mapData:Data([1,2,3]),snapshot:memory.snapshot)
    }
    func json() throws -> [String:Any] { try JSONSerialization.jsonObject(with:archive().encoded()) as! [String:Any] }
    func decode(_ object:[String:Any]) throws -> PersistentMemoryArchive { try .decode(JSONSerialization.data(withJSONObject:object)) }
    func sample(_ time:Double,tracking:Bool=true,session:String="restored",pose:CameraPose = .identity)->MemoryPose { .init(session:session,pose:pose,timestamp:time,tracking:tracking) }
    func testRoundTripOmitsActiveSelectionAndSession() throws {
        let value=try archive(); XCTAssertEqual(try PersistentMemoryArchive.decode(value.encoded()),value)
        let object=try json(); XCTAssertNil(object["session"]); XCTAssertNil(object["activeID"]); XCTAssertNil(object["selectedID"])
        XCTAssertEqual(value.mapData,Data([1,2,3]))
    }
    func testArchiveRejectsUnknownFieldsAtEveryLevel() throws {
        var value=try json(); value["activeID"]="desk"; XCTAssertThrowsError(try decode(value))
        value=try json(); var places=value["bookmarks"] as! [[String:Any]]; places[0]["extra"]=true; value["bookmarks"]=places; XCTAssertThrowsError(try decode(value))
        value=try json(); value["returnPoint"]=["x":0,"y":0,"z":0,"w":1]; XCTAssertThrowsError(try decode(value))
    }
    func testArchiveRejectsVersionsIDsBase64BoundsAndCoordinates() throws {
        for (key,bad) in [("version",2 as Any),("mapID","bad"),("anchorID",map),("mapDataBase64",""),("mapDataBase64","AQI=\n")] {
            var value=try json(); value[key]=bad; XCTAssertThrowsError(try decode(value),key)
        }
        var value=try json(); value["returnPoint"]=["x":10000.01,"y":0,"z":0]; XCTAssertThrowsError(try decode(value))
        XCTAssertThrowsError(try PersistentMemoryArchive.decode(Data(repeating:32,count:PersistentMemoryArchive.maxJSONBytes+1)))
    }
    func testArchiveRejectsDuplicateNamesIDsAndCapacity() throws {
        var value=try json(),places=value["bookmarks"] as! [[String:Any]]
        places.append(places[0]); value["bookmarks"]=places; XCTAssertThrowsError(try decode(value))
        places[1]["id"]="other"; places[1]["name"]="désk"; value["bookmarks"]=places; XCTAssertThrowsError(try decode(value))
        places[1]["name"]="Other\n"; value["bookmarks"]=places; XCTAssertThrowsError(try decode(value))
        value["bookmarks"]=(0..<65).map { ["id":"p\($0)","name":"Place \($0)","position":["x":0,"y":0,"z":0]] as [String:Any] }; XCTAssertThrowsError(try decode(value))
    }
    func testRestoreNeedsRelocalizationIdentityAndSettling() throws {
        var gate=WorldMapRestoreGate(); try gate.begin(archive:archive(),session:"restored",now:0)
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1,sample:sample(1),relocalizing:false),.awaitingRelocalization)
        XCTAssertEqual(gate.observe(session:"wrong",mapID:map,anchorID:nil,now:2,sample:sample(2,session:"wrong"),relocalizing:true),.awaitingRelocalization)
        _=gate.observe(session:"restored",mapID:map,anchorID:nil,now:3,sample:sample(3,tracking:false),relocalizing:true)
        _=gate.observe(session:"restored",mapID:map,anchorID:map,now:4,sample:sample(4),relocalizing:false)
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:4.5,sample:sample(4.5),relocalizing:false),.awaitingRelocalization)
        for t in [4.7,4.9] { _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:t,sample:sample(t),relocalizing:false) }
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:5,sample:sample(5),relocalizing:false),.ready)
    }
    func testTrackingLossStaleFutureAndInvalidPoseRestartSettling() throws {
        var gate=WorldMapRestoreGate(); try gate.begin(archive:archive(),session:"restored",now:0)
        _=gate.observe(session:"restored",mapID:map,anchorID:nil,now:0,sample:sample(0),relocalizing:true)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1,sample:sample(1),relocalizing:false)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1.4,sample:sample(1.4,tracking:false),relocalizing:false)
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1.5,sample:sample(1.5),relocalizing:false),.awaitingRelocalization)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1.9,sample:sample(1),relocalizing:false)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:2,sample:sample(2.1),relocalizing:false)
        let bad=CameraPose(position:.zero,right:.zero,up:Vector3(0,1,0),back:Vector3(0,0,1))
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:2.1,sample:sample(2.1,pose:bad),relocalizing:false)
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:3,sample:sample(3),relocalizing:false),.awaitingRelocalization)
        for t in [3.2,3.4] { _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:t,sample:sample(t),relocalizing:false) }
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:3.5,sample:sample(3.5),relocalizing:false),.ready)
    }
    func testTimeoutAndBackwardClockFailClosedAndCancelResets() throws {
        for now in [60.001,-1,Double.nan] {
            var gate=WorldMapRestoreGate(); try gate.begin(archive:archive(),session:"restored",now:0)
            XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:now,sample:sample(0),relocalizing:true),.failed)
            XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1,sample:sample(1),relocalizing:false),.failed)
            gate.cancel(); XCTAssertEqual(gate.state,.idle); XCTAssertNil(gate.archive)
        }
    }
    func testMirroredPoseCannotEstablishRelocalizationOrSettle() throws {
        var gate=WorldMapRestoreGate(); try gate.begin(archive:archive(),session:"restored",now:0)
        var mirrored=CameraPose.identity; mirrored.right=Vector3(-1,0,0)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:0,sample:sample(0,pose:mirrored),relocalizing:true)
        for step in 1...10 {
            let time=Double(step)/10
            _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:time,sample:sample(time),relocalizing:false)
        }
        XCTAssertEqual(gate.state,.awaitingRelocalization)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1.1,sample:sample(1.1),relocalizing:true)
        for step in 12...20 {
            let time=Double(step)/10
            _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:time,sample:sample(time,pose:mirrored),relocalizing:false)
        }
        XCTAssertEqual(gate.state,.awaitingRelocalization)
    }
    func testObservationGapCannotCountAsContinuousNormalTracking() throws {
        var gate=WorldMapRestoreGate(); try gate.begin(archive:archive(),session:"restored",now:0)
        _=gate.observe(session:"restored",mapID:map,anchorID:nil,now:0,sample:sample(0),relocalizing:true)
        _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:0.1,sample:sample(0.1),relocalizing:false)
        XCTAssertEqual(gate.observe(session:"restored",mapID:map,anchorID:anchor,now:1.1,sample:sample(1.1),relocalizing:false),.awaitingRelocalization)
        for t in [1.3,1.5,1.7] { _=gate.observe(session:"restored",mapID:map,anchorID:anchor,now:t,sample:sample(t),relocalizing:false) }
        XCTAssertEqual(gate.state,.ready)
    }
    func testRestoreIsInactiveAndCannotOverwriteExistingPlaces() throws {
        var memory=SpatialMemoryManager(); try memory.begin(session:"restored")
        try memory.restore(archive:archive(),session:"restored")
        XCTAssertNil(memory.activeID); XCTAssertNil(memory.selectedID); XCTAssertNotNil(memory.returnPoint)
        XCTAssertThrowsError(try memory.restore(archive:archive(),session:"restored"))
        try memory.recall(id:"desk"); XCTAssertEqual(memory.activeID,"desk")
        memory.end(); XCTAssertThrowsError(try memory.restore(archive:archive(),session:"restored"))
    }
}
