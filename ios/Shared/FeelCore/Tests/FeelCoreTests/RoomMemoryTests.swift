import XCTest
@testable import FeelCore

/// protocol/room-memory-v1.json: the anchors and remembered targets shared with chalk/feel_chalk/anchors.py.
func roomMemoryVector() throws -> [String: Any] {
    var url=URL(fileURLWithPath:#filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return try XCTUnwrap(JSONSerialization.jsonObject(with:try Data(contentsOf:url.appendingPathComponent("protocol/room-memory-v1.json"))) as? [String:Any])
}

final class RoomFrameTests: XCTestCase {
    /// A tag upright on a wall that faces world −x: out of the tag is −x, down is −y, so right along the tag is +z.
    private let frame=RoomFrame(origin:Vector3(2,1,3),xAxis:Vector3(0,0,1),yAxis:Vector3(-1,0,0),zAxis:Vector3(0,-1,0))

    func testWorldAndTagPointsAreInverses() {
        XCTAssertTrue(frame.isValid)
        let world=Vector3(-4,1.5,2)
        XCTAssertEqual(frame.tagPoint(world:world),Vector3(-1,6,-0.5))
        XCTAssertEqual(frame.worldPoint(tag:Vector3(-1,6,-0.5)),world)
    }
    func testIdentityFrameChangesNothing() {
        let identity=RoomFrame(origin:.zero,xAxis:Vector3(1,0,0),yAxis:Vector3(0,1,0),zAxis:Vector3(0,0,1))
        XCTAssertEqual(identity.tagPoint(world:Vector3(1,2,3)),Vector3(1,2,3))
        XCTAssertEqual(identity.worldPoint(tag:Vector3(1,2,3)),Vector3(1,2,3))
    }
    func testFrameFromColumnMajorTransform() {
        // ARAnchor.transform flattened column by column: x axis, y axis, z axis, origin.
        XCTAssertEqual(RoomFrame(columnMajor:[0,0,1,0, -1,0,0,0, 0,-1,0,0, 2,1,3,1]),frame)
        XCTAssertNil(RoomFrame(columnMajor:[0,0,1,0, -2,0,0,0, 0,-1,0,0, 2,1,3,1]),"a stretched axis is not a rigid frame")
        XCTAssertNil(RoomFrame(columnMajor:Array(repeating:0,count:12)))
        XCTAssertNil(RoomFrame(columnMajor:[Double.nan]+Array(repeating:0,count:15)))
    }
    func testMirroredFramesAreInvalid() {
        // A reflection would swap left and right for the user; ARKit never produces one, so refuse it outright.
        XCTAssertFalse(RoomFrame(origin:.zero,xAxis:Vector3(1,0,0),yAxis:Vector3(0,1,0),zAxis:Vector3(0,0,-1)).isValid)
        XCTAssertNil(RoomFrame(columnMajor:[1,0,0,0, 0,1,0,0, 0,0,-1,0, 0,0,0,1]))
    }
    func testTheSameRoomPointComesBackInAnotherSessionsWorld() {
        // Session one saw the tag at `frame`; the next session's world origin and heading differ. Tag coordinates persist.
        let later=RoomFrame(origin:.zero,xAxis:Vector3(-1,0,0),yAxis:Vector3(0,0,-1),zAxis:Vector3(0,-1,0))
        XCTAssertTrue(later.isValid)
        let stored=frame.tagPoint(world:Vector3(-4,1.5,2))
        XCTAssertEqual(later.worldPoint(tag:stored),Vector3(1,0.5,-6))
    }
}

final class RememberedTargetTests: XCTestCase {
    private func anchor(_ label: String,_ x: Double,_ y: Double,_ z: Double,_ seenAt: String,confidence: Double=0.9) -> RoomAnchor {
        RoomAnchor(label:label,position:Vector3(x,y,z),confidence:confidence,seenAt:utc(seenAt))
    }
    func testSharedVectorMatchesChalk() throws {
        let vector=try roomMemoryVector()
        let rows=try XCTUnwrap(vector["anchors"] as? [[String:Any]])
        // Rows the phone could never hold (a missing coordinate or time) are left out here; the rest go through the real filter.
        let anchors=rows.compactMap { row -> RoomAnchor? in
            guard let label=row["label"] as? String,let x=row["x"] as? Double,let y=row["y"] as? Double,let z=row["z"] as? Double,
                  let confidence=row["confidence"] as? Double,let seen=row["seen_at"] as? String else { return nil }
            return RoomAnchor(label:label,position:Vector3(x,y,z),confidence:confidence,seenAt:utc(seen))
        }
        XCTAssertEqual(anchors.count,8)
        let remembered=RememberedTarget.remember(anchors)
        let expected=try XCTUnwrap(vector["remembered"] as? [[String:Any]])
        XCTAssertEqual(remembered.count,expected.count)
        for (got,want) in zip(remembered,expected) {
            XCTAssertEqual(got.label,want["label"] as? String)
            XCTAssertEqual(got.position.x,try XCTUnwrap(want["x"] as? Double),accuracy:1e-9)
            XCTAssertEqual(got.position.y,try XCTUnwrap(want["y"] as? Double),accuracy:1e-9)
            XCTAssertEqual(got.position.z,try XCTUnwrap(want["z"] as? Double),accuracy:1e-9)
            XCTAssertEqual(got.sightings,want["sightings"] as? Int)
            XCTAssertEqual(got.lastSeenAt,utc(try XCTUnwrap(want["last_seen_at"] as? String)))
        }
    }
    func testOnlyTheLastTwentySightingsShapeThePosition() throws {
        let anchors=(0..<25).map { i in anchor("door",Double(i),1,0,String(format:"2026-10-17T10:%02d:00Z",i)) }   // minute i; i = 24 is the newest
        let door=try XCTUnwrap(RememberedTarget.remembered("Door",in:anchors))
        XCTAssertEqual(door.position.x,14.5,"median of x = 5 … 24")
        XCTAssertEqual(door.sightings,25)
        XCTAssertEqual(door.lastSeenAt,utc("2026-10-17T10:24:00Z"))
    }
    func testUnusableAnchorsAreIgnoredNotGuessed() {
        let anchors=[anchor("  ",0,1,0,"2026-10-17T10:00:00Z"),anchor("chair",.nan,1,0,"2026-10-17T10:00:00Z"),
                     anchor("chair",101,1,0,"2026-10-17T10:00:00Z"),anchor("chair",1,1,0,"2026-10-17T10:00:00Z")]
        XCTAssertEqual(RememberedTarget.remember(anchors),[RememberedTarget(label:"chair",position:Vector3(1,1,0),sightings:1,lastSeenAt:utc("2026-10-17T10:00:00Z"))])
        XCTAssertNil(RememberedTarget.remembered("desk",in:anchors))
    }
    func testLabelsNormalizeLikeChalkObjectNames() {
        XCTAssertEqual(RoomAnchor.normalized("  Water   Fountain "),"water fountain")
    }
    func testMedianOfEvenAndOddCounts() {
        XCTAssertEqual(RememberedTarget.median([3,1,2]),2)
        XCTAssertEqual(RememberedTarget.median([4,1,3,2]),2.5)
        XCTAssertEqual(RememberedTarget.median([7]),7)
    }
}

final class RoomMemoryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: RoomMemoryStore!
    private let exit=RoomAnchor(label:"exit",position:Vector3(-4,5.1,0.05),confidence:0.9,seenAt:utc("2026-10-17T20:00:00Z"))

    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store=RoomMemoryStore(directory:directory)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:directory) }

    func testAppendedAnchorsLoadAfterRestartPerTag() throws {
        try store.append(exit,tagId:"feel-tag-01")
        try store.append(RoomAnchor(label:"desk",position:Vector3(1,2,0),confidence:0.8,seenAt:utc("2026-10-17T20:05:00Z")),tagId:"feel-tag-01")
        try store.append(exit,tagId:"feel-tag-02")
        XCTAssertEqual(RoomMemoryStore(directory:directory).anchors(for:"feel-tag-01").map(\.label),["exit","desk"])
        XCTAssertEqual(RoomMemoryStore(directory:directory).anchors(for:"feel-tag-02"),[exit])
        XCTAssertEqual(store.anchors(for:"feel-tag-03"),[])
    }
    func testFileUsesTheTableColumnNames() throws {
        try store.append(exit,tagId:"feel-tag-01")
        let rows=try XCTUnwrap(JSONSerialization.jsonObject(with:try Data(contentsOf:directory.appendingPathComponent("feel-tag-01.json"))) as? [[String:Any]])
        XCTAssertEqual(rows.count,1)
        XCTAssertEqual(Set(rows[0].keys),["label","x","y","z","confidence","seen_at"])
        XCTAssertEqual(rows[0]["seen_at"] as? String,"2026-10-17T20:00:00Z")
    }
    func testCorruptFileReadsAsNothingRemembered() throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try Data("not anchors".utf8).write(to:directory.appendingPathComponent("feel-tag-01.json"))
        XCTAssertEqual(store.anchors(for:"feel-tag-01"),[])
        try store.append(exit,tagId:"feel-tag-01")   // a corrupt file is replaced, not appended to
        XCTAssertEqual(store.anchors(for:"feel-tag-01"),[exit])
    }
    func testTagIdsAreSlugsOnly() {
        for bad in ["","../x","FEEL","tag id","-tag",String(repeating:"a",count:65)] {
            XCTAssertThrowsError(try store.append(exit,tagId:bad),bad)
        }
        XCTAssertEqual(store.anchors(for:"../x"),[])
    }
    func testAppendKeepsTheNewestTwoHundred() throws {
        for i in 0..<205 { try store.append(RoomAnchor(label:"exit",position:Vector3(Double(i),0,0),confidence:1,seenAt:utc("2026-10-17T20:00:00Z")),tagId:"feel-tag-01") }
        let kept=store.anchors(for:"feel-tag-01")
        XCTAssertEqual(kept.count,200)
        XCTAssertEqual(kept.first?.position.x,5)
    }
    func testReplaceAndRemove() throws {
        try store.append(exit,tagId:"feel-tag-01")
        try store.replace([],tagId:"feel-tag-01")
        XCTAssertEqual(store.anchors(for:"feel-tag-01"),[])
        try store.replace([exit,exit],tagId:"feel-tag-01")
        XCTAssertEqual(store.anchors(for:"feel-tag-01").count,2)
        try store.remove(tagId:"feel-tag-01")
        XCTAssertEqual(store.anchors(for:"feel-tag-01"),[])
        XCTAssertNoThrow(try store.remove(tagId:"feel-tag-01"))
    }
}
