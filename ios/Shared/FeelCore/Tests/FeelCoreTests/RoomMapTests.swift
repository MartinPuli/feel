import XCTest
@testable import FeelCore

/// protocol/room-map-v1.json: the visit maps and the merged structure shared with chalk/feel_chalk/room_map.py.
func roomMapVector() throws -> [String: Any] {
    var url=URL(fileURLWithPath:#filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return try XCTUnwrap(JSONSerialization.jsonObject(with:try Data(contentsOf:url.appendingPathComponent("protocol/room-map-v1.json"))) as? [String:Any])
}

/// A map from rows written in +y order, each a string of u/f/b, for readable tests.
func roomMap(_ cellSize: Double=0.1,_ originX: Double,_ originY: Double,_ rows: [String]) -> RoomMap {
    let states: [FloorGrid.State]=rows.joined().map { $0 == "b" ? .blocked : $0 == "f" ? .free : .unknown }
    return RoomMap(cellSize:cellSize,originX:originX,originY:originY,width:rows[0].count,height:rows.count,cells:states)!
}

/// The three visits of the shared vector, by hand (see tests/test_room_map.py on the Chalk side).
let visit1=RoomMap(cellSize:0.1,originX:0,originY:0,width:6,height:6,encoded:"14f2b4f2b8f6b")!
let visit2=RoomMap(cellSize:0.1,originX:-0.2,originY:0,width:8,height:6,encoded:"40f2u6b")!
let visit3=RoomMap(cellSize:0.1,originX:0.1,originY:0.1,width:4,height:5,encoded:"9f1u1b5f4b")!

final class RoomMapEncodingTests: XCTestCase {
    func testCellsAreRunLengthEncodedOverTheRowMajorArray() {
        let states: [FloorGrid.State]=[.free,.free,.blocked,.unknown,.unknown,.unknown,.free,.free]
        XCTAssertEqual(RoomMap.encode(states),"2f1b3u2f")
        XCTAssertEqual(RoomMap.decode("2f1b3u2f",count:8),states)
        XCTAssertEqual(RoomMap.decode("2f2f",count:4),[.free,.free,.free,.free],"split runs decode; the encoding is canonical")
        XCTAssertEqual(RoomMap.encode(RoomMap.decode("2f2f",count:4)!),"4f")
        XCTAssertEqual(RoomMap.encode([]),"")
        XCTAssertEqual(RoomMap.decode("",count:0),[])
    }
    func testMalformedRunsDecodeToNothing() {
        for (text,count) in [("2f1b3u2f",7),("2f1b3u2f",9),("2x",2),("0f1f",1),("f",1),("1f 1f",2),("-1f",1),("1F",1),("",1)] {
            XCTAssertNil(RoomMap.decode(text,count:count),text)
        }
    }
    func testAMapIsValidatedAndMadeCanonicalOnCreation() {
        let map=RoomMap(cellSize:0.1,originX:-0.2,originY:0,width:8,height:6,encoded:"40f2u6b")
        XCTAssertEqual(map,visit2)
        XCTAssertEqual(RoomMap(cellSize:0.1,originX:-0.30000000000000004,originY:0,width:1,height:1,encoded:"1f")?.originX,-0.3,"origins are rounded onto the lattice")
        XCTAssertEqual(RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"1f1f")?.encoded,"2f")
        XCTAssertNil(RoomMap(cellSize:0.1,originX:-0.25,originY:0,width:8,height:6,encoded:"40f2u6b"),"origins sit on the cell lattice")
        XCTAssertNil(RoomMap(cellSize:0,originX:0,originY:0,width:1,height:1,encoded:"1f"))
        XCTAssertNil(RoomMap(cellSize:.nan,originX:0,originY:0,width:1,height:1,encoded:"1f"))
        XCTAssertNil(RoomMap(cellSize:1.5,originX:0,originY:0,width:1,height:1,encoded:"1f"))
        XCTAssertNil(RoomMap(cellSize:0.1,originX:0,originY:0,width:0,height:6,encoded:""))
        XCTAssertNil(RoomMap(cellSize:0.1,originX:0,originY:0,width:600,height:600,encoded:"360000f"),"too many cells")
        XCTAssertNil(RoomMap(cellSize:0.1,originX:.infinity,originY:0,width:1,height:1,encoded:"1f"))
        XCTAssertNil(RoomMap(cellSize:0.1,originX:-101,originY:0,width:1,height:1,encoded:"1f"))
        XCTAssertNil(RoomMap(cellSize:0.1,originX:0,originY:0,width:8,height:6,encoded:"40f2u5b"))
        XCTAssertNil(RoomMap(cellSize:0.1,originX:0,originY:0,width:8,height:6,cells:Array(repeating:.free,count:47)))
    }
    func testAMapKnowsItsCellsByIndex() {
        XCTAssertEqual(visit2.minIX,-2); XCTAssertEqual(visit2.minIY,0)
        XCTAssertEqual(visit3.minIX,1); XCTAssertEqual(visit3.minIY,1)
        XCTAssertEqual(visit1.state(ix:2,iy:2),.blocked)
        XCTAssertEqual(visit1.state(ix:0,iy:0),.free)
        XCTAssertEqual(visit1.state(ix:0,iy:5),.blocked)
        XCTAssertEqual(visit1.state(ix:6,iy:0),.unknown,"outside the map is unknown")
        XCTAssertEqual(visit2.state(ix:-2,iy:5),.unknown)
        XCTAssertEqual(visit2.state(ix:-2,iy:4),.free)
        XCTAssertEqual(visit1.observedCount,36); XCTAssertEqual(visit2.observedCount,46); XCTAssertEqual(visit1.blockedCount,10)
    }
    func testJSONUsesTheTableColumnNames() throws {
        let data=try JSONEncoder().encode(visit2)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(Set(object.keys),["schema","cell_size","origin_x","origin_y","width","height","cells"])
        XCTAssertEqual(object["schema"] as? Int,1)
        XCTAssertEqual(object["cells"] as? String,"40f2u6b")
        XCTAssertEqual(object["origin_x"] as? Double,-0.2)
        XCTAssertEqual(try JSONDecoder().decode(RoomMap.self,from:data),visit2)
        for malformed in [#"{"schema":1,"cell_size":0.1,"origin_x":0,"origin_y":0,"width":1,"height":1,"cells":"2f"}"#,
                          #"{"schema":2,"cell_size":0.1,"origin_x":0,"origin_y":0,"width":1,"height":1,"cells":"1f"}"#,
                          #"{"cell_size":0.1,"origin_x":0,"origin_y":0,"width":1,"height":1}"#,"[]"] {
            XCTAssertThrowsError(try JSONDecoder().decode(RoomMap.self,from:Data(malformed.utf8)),malformed)
        }
    }
}

final class RoomMapMergeTests: XCTestCase {
    func testOneVisitMergesToItself() { XCTAssertEqual(RoomMap.merge([visit1]),visit1) }
    func testBlockedNeedsAtLeastHalfOfTheVisitsThatSawTheCell() {
        let seenBlocked=roomMap(0.1,0,0,["b"]), seenFree=roomMap(0.1,0,0,["f"]), unseen=roomMap(0.1,0,0,["u"])
        XCTAssertEqual(RoomMap.merge([seenBlocked,seenFree])?.encoded,"1b","a tie goes to blocked")
        XCTAssertEqual(RoomMap.merge([seenBlocked,seenFree,seenFree])?.encoded,"1f","one visit in three is not half")
        XCTAssertEqual(RoomMap.merge([seenBlocked,seenBlocked,seenFree,seenFree])?.encoded,"1b")
        XCTAssertEqual(RoomMap.merge([seenBlocked,seenFree,seenFree,seenFree])?.encoded,"1f")
        XCTAssertEqual(RoomMap.merge([seenBlocked,unseen,unseen])?.encoded,"1b","visits that did not see the cell do not vote")
        XCTAssertNil(RoomMap.merge([unseen,unseen]),"nothing observed is nothing remembered")
    }
    func testMergeKeepsTheWallAndDropsTheTransientObstacle() throws {
        let merged=try XCTUnwrap(RoomMap.merge([visit1,visit2,visit3]))
        XCTAssertEqual(merged,RoomMap(cellSize:0.1,originX:-0.2,originY:0,width:8,height:6,encoded:"28f2b10f2u6b"))
        XCTAssertEqual((-2..<6).map { merged.state(ix:$0,iy:5) },[.unknown,.unknown,.blocked,.blocked,.blocked,.blocked,.blocked,.blocked],"the far wall, wherever a visit saw it")
        XCTAssertEqual(merged.state(ix:2,iy:2),.free,"the chair seen once in three visits is gone")
        XCTAssertEqual(merged.state(ix:3,iy:2),.free)
        XCTAssertEqual(merged.state(ix:2,iy:3),.blocked,"blocked once, free once, unseen once: a tie stays blocked")
        XCTAssertEqual(merged.state(ix:3,iy:3),.blocked,"the bag seen twice in three visits stays")
    }
    func testMergeCoversTheUnionOfWhatWasObserved() throws {
        let merged=try XCTUnwrap(RoomMap.merge([roomMap(0.1,-0.3,0.2,["fb"]),roomMap(0.1,0.5,-0.1,["f","b"])]))
        XCTAssertEqual(merged.originX,-0.3); XCTAssertEqual(merged.originY,-0.1); XCTAssertEqual(merged.width,9); XCTAssertEqual(merged.height,4)
        XCTAssertEqual(merged.state(ix:-3,iy:2),.free); XCTAssertEqual(merged.state(ix:-2,iy:2),.blocked)
        XCTAssertEqual(merged.state(ix:5,iy:-1),.free); XCTAssertEqual(merged.state(ix:5,iy:0),.blocked)
        XCTAssertEqual(merged.state(ix:0,iy:0),.unknown); XCTAssertEqual(merged.observedCount,4)
    }
    func testMergeRefusesMixedCellSizesAndNothing() {
        XCTAssertNil(RoomMap.merge([]))
        XCTAssertNil(RoomMap.merge([visit1,roomMap(0.2,0,0,["f"])]))
    }
    func testSharedVectorMatchesChalk() throws {
        let vector=try roomMapVector()
        let encoding=try XCTUnwrap(vector["encoding"] as? [String:Any])
        let states=try XCTUnwrap(encoding["states"] as? [String]).map { $0 == "b" ? FloorGrid.State.blocked : $0 == "f" ? .free : .unknown }
        XCTAssertEqual(RoomMap.encode(states),encoding["cells"] as? String)
        XCTAssertEqual(RoomMap.decode(try XCTUnwrap(encoding["cells"] as? String),count:states.count),states)
        func map(_ row: [String:Any]) throws -> RoomMap {
            try XCTUnwrap(RoomMap(cellSize:try XCTUnwrap(row["cell_size"] as? Double),originX:try XCTUnwrap(row["origin_x"] as? Double),originY:try XCTUnwrap(row["origin_y"] as? Double),
                                  width:try XCTUnwrap(row["width"] as? Int),height:try XCTUnwrap(row["height"] as? Int),encoded:try XCTUnwrap(row["cells"] as? String)))
        }
        let visits=try XCTUnwrap(vector["visits"] as? [[String:Any]]).map { try map($0) }
        XCTAssertEqual(visits,[visit1,visit2,visit3])
        let want=try XCTUnwrap(vector["merged"] as? [String:Any])
        let merged=try XCTUnwrap(RoomMap.merge(visits))
        XCTAssertEqual(merged,try map(want))
        XCTAssertEqual(visits.count,want["visits"] as? Int)
    }
}

final class RoomMapGridTests: XCTestCase {
    /// The tag upright on the wall 3 m ahead of the identity camera, facing it: out of the tag is world +z, right along it is +x, down is −y.
    /// Tag-floor coordinates are then x = world x, y = world z + 3.
    let tagOnFarWall=RoomFrame(origin:Vector3(0,1,-3),xAxis:Vector3(1,0,0),yAxis:Vector3(0,0,1),zAxis:Vector3(0,-1,0))
    /// The same physical tag in another session's world, where the wall faces −x: a quarter turn and a move.
    let tagInNextWorld=RoomFrame(origin:Vector3(4,1,2),xAxis:Vector3(0,0,1),yAxis:Vector3(-1,0,0),zAxis:Vector3(0,-1,0))

    /// Free floor 2 m wide (cells x −10…9) from 0.1 m to 2.9 m ahead (cells z −29…−2) and the wall the tag hangs on (cell z −30).
    /// Sample points sit on cell centres, so no count depends on a floating-point cell boundary.
    func seenRoom() -> FloorGrid {
        var grid=FloorGrid()
        FloorGridTests.paint(&grid,x:(-0.95)...0.95,z:(-2.85)...(-0.15),height:0)
        FloorGridTests.paint(&grid,x:(-0.95)...0.95,z:(-2.95)...(-2.95),height:1.0)
        return grid
    }

    func testExportAndImportRoundTripInTheTagFrame() throws {
        let grid=seenRoom()
        XCTAssertEqual(grid.observedCells.count,580)
        let map=try XCTUnwrap(RoomMap(grid:grid,frame:tagOnFarWall))
        XCTAssertEqual(map.cellSize,0.1); XCTAssertEqual(map.width,20); XCTAssertEqual(map.height,29)
        XCTAssertEqual(map.originX,-1.0); XCTAssertEqual(map.originY,0)
        XCTAssertEqual(map.observedCount,580); XCTAssertEqual(map.blockedCount,20)
        XCTAssertTrue((-10...9).allSatisfy { map.state(ix:$0,iy:0) == .blocked },"the wall is the row at the tag")
        XCTAssertTrue((-10...9).allSatisfy { map.state(ix:$0,iy:15) == .free })
        var fresh=FloorGrid()
        XCTAssertTrue(fresh.setPrior(map,frame:tagOnFarWall))
        XCTAssertEqual(fresh.priorCellCount,580)
        XCTAssertTrue(fresh.observedCells.isEmpty,"a prior is not an observation")
        for (cell,state) in grid.observedCells { XCTAssertEqual(fresh.state(cell),state,"\(cell)") }
        XCTAssertEqual(fresh.liveState(FloorGrid.Cell(0,-30)),.unknown)
        XCTAssertEqual(fresh.state(FloorGrid.Cell(0,-31)),.unknown,"beyond the wall nothing is remembered")
        XCTAssertEqual(RoomMap(grid:fresh,frame:tagOnFarWall),nil,"a prior alone is not a visit")
    }
    func testExportIsWhatTheCameraSawNotWhatItWasTold() throws {
        var grid=FloorGrid()
        XCTAssertNil(RoomMap(grid:grid,frame:tagOnFarWall),"nothing seen, no map")
        XCTAssertTrue(grid.setPrior(visit1,frame:tagOnFarWall))
        XCTAssertNil(RoomMap(grid:grid,frame:tagOnFarWall))
        FloorGridTests.paint(&grid,x:0.05...0.35,z:(-1.25)...(-1.05),height:0)
        let map=try XCTUnwrap(RoomMap(grid:grid,frame:tagOnFarWall))
        XCTAssertEqual(map.observedCount,grid.observedCells.count)
        XCTAssertEqual(map.observedCount,12)
    }
    func testLiveObservationsOverrideThePrior() throws {
        var grid=FloorGrid()
        XCTAssertTrue(grid.setPrior(try XCTUnwrap(RoomMap(grid:seenRoom(),frame:tagOnFarWall)),frame:tagOnFarWall))
        let wall=FloorGrid.Cell(0,-30), floor=FloorGrid.Cell(0,-10)
        XCTAssertEqual(grid.state(wall),.blocked); XCTAssertEqual(grid.state(floor),.free)
        // One floor hit is not yet an observation: the remembered wall stands until the camera has classified the cell.
        grid.integrate(points:[Vector3(0.05,0,-2.95)],floorY:0,camera:.zero)
        XCTAssertEqual(grid.state(wall),.blocked)
        grid.integrate(points:[Vector3(0.05,0,-2.95)],floorY:0,camera:.zero)
        XCTAssertEqual(grid.state(wall),.free,"the camera sees floor where the wall was remembered: the camera wins")
        FloorGridTests.paint(&grid,x:0.05...0.05,z:(-0.95)...(-0.95),height:1.0)
        XCTAssertEqual(grid.state(floor),.blocked,"a new obstacle on remembered floor blocks")
        XCTAssertEqual(grid.state(FloorGrid.Cell(5,-30)),.blocked,"cells the camera has not classified keep the prior")
    }
    func testCalibrationClearsObservationsButKeepsThePriorAndResetDropsBoth() throws {
        var grid=seenRoom()
        XCTAssertTrue(grid.setPrior(visit1,frame:tagOnFarWall))
        XCTAssertEqual(grid.priorCellCount,36); XCTAssertEqual(grid.observedCells.count,580)
        let atTag=FloorGrid.Cell(0,-30), visit1Wall=FloorGrid.Cell(0,-25)
        XCTAssertEqual(grid.state(atTag),.blocked,"the camera sees the wall there; visit1 remembers floor")
        grid.clearObservations()
        XCTAssertEqual(grid.priorCellCount,36); XCTAssertEqual(grid.observedCells.count,0); XCTAssertEqual(grid.cellCount,0)
        XCTAssertEqual(grid.state(atTag),.free,"without the observation the prior speaks")
        XCTAssertEqual(grid.state(visit1Wall),.blocked,"visit1's wall row lies 0.5 m out from the tag")
        grid.reset()
        XCTAssertEqual(grid.priorCellCount,0)
        XCTAssertEqual(grid.state(visit1Wall),.unknown)
    }
    func testRouteUsesTheRememberedWallBeforeTheCameraSeesIt() throws {
        // Last visit: a wall across the room 2 m ahead from x = −2 to 2, open beyond its ends.
        var seen=FloorGrid()
        FloorGridTests.paint(&seen,x:(-1.95)...1.95,z:(-2.05)...(-1.95),height:1.0,camera:Vector3(0,0,-1))
        let map=try XCTUnwrap(RoomMap(grid:seen,frame:tagOnFarWall))
        var grid=FloorGrid()
        XCTAssertTrue(grid.setPrior(map,frame:tagOnFarWall))
        let path=try XCTUnwrap(grid.route(from:.zero,to:Vector3(0,0,-3)),"a route exists around the remembered wall")
        for p in path { XCTAssertNotEqual(grid.state(grid.cell(p)),.blocked) }
        XCTAssertTrue(path.contains { abs($0.x)>2.0 },"the route goes around the end of a wall the camera has not seen yet")
        let straight=try XCTUnwrap(FloorGrid().route(from:.zero,to:Vector3(0,0,-3)))
        XCTAssertTrue(straight.allSatisfy { abs($0.x)<0.2 },"without memory the planner walks straight through the unknown")
    }
    func testTheSameRoomComesBackInAnotherSessionsWorldAfterAQuarterTurn() throws {
        let map=try XCTUnwrap(RoomMap(grid:seenRoom(),frame:tagOnFarWall))
        var next=FloorGrid()
        XCTAssertTrue(next.setPrior(map,frame:tagInNextWorld))
        XCTAssertEqual(next.priorCellCount,580,"a quarter turn maps cells one to one")
        // A cell at tag (ix, iy) is at world (4 − 0.05 − iy·0.1, ·, 2 + 0.05 + ix·0.1) in the next world.
        for ix in -10...9 {
            XCTAssertEqual(next.state(FloorGrid.Cell(39,20+ix)),.blocked,"wall at ix \(ix)")
            XCTAssertEqual(next.state(FloorGrid.Cell(39-15,20+ix)),.free,"floor 1.5 m out at ix \(ix)")
            XCTAssertEqual(next.state(FloorGrid.Cell(39-28,20+ix)),.free,"floor 2.8 m out at ix \(ix)")
        }
        XCTAssertEqual(next.state(FloorGrid.Cell(39,30)),.unknown)
        XCTAssertEqual(next.state(FloorGrid.Cell(39-29,20)),.unknown)
        XCTAssertEqual(next.state(FloorGrid.Cell(40,20)),.unknown,"behind the wall")
    }
    func testAnArbitraryTurnKeepsWallsConnectedAndFloorNearby() throws {
        // The tag seen at 30° to the world axes: cells no longer map one to one, but every wall cell lands within one cell of itself and the wall still blocks.
        let s=0.5, c=(0.75).squareRoot()
        let turned=RoomFrame(origin:Vector3(0.37,1,-3.21),xAxis:Vector3(c,0,-s),yAxis:Vector3(s,0,c),zAxis:Vector3(0,-1,0))
        XCTAssertTrue(turned.isValid)
        var seen=FloorGrid()
        FloorGridTests.paint(&seen,x:(-1.95)...1.95,z:(-2.25)...(-1.95),height:1.0,camera:Vector3(0,0,-1))
        FloorGridTests.paint(&seen,x:(-1.95)...1.95,z:(-1.85)...(-0.15),height:0,camera:Vector3(0,0,-1))
        let map=try XCTUnwrap(RoomMap(grid:seen,frame:turned))
        var back=FloorGrid()
        XCTAssertTrue(back.setPrior(map,frame:turned))
        let seenCells=seen.observedCells
        func near(_ cell: FloorGrid.Cell,_ state: FloorGrid.State,in grid: FloorGrid) -> Bool {
            (-1...1).contains { dx in (-1...1).contains { dz in grid.state(FloorGrid.Cell(cell.x+dx,cell.z+dz)) == state } }
        }
        for (cell,state) in seenCells where state == .blocked { XCTAssertTrue(near(cell,.blocked,in:back),"wall cell \(cell) came back nearby") }
        for (cell,state) in back.priorCells where state == .blocked {
            XCTAssertTrue((-1...1).contains { dx in (-1...1).contains { dz in seenCells[FloorGrid.Cell(cell.x+dx,cell.z+dz)] == .blocked } },"no wall appears where none was seen: \(cell)")
        }
        let path=try XCTUnwrap(back.route(from:.zero,to:Vector3(0,0,-3)))
        for p in path { XCTAssertNotEqual(back.state(back.cell(p)),.blocked) }
        XCTAssertTrue(path.contains { abs($0.x)>2.0 },"the remembered wall still has to be walked around")
    }
    func testATiltedTagIsLevelledAndATagOffTheWallIsRefused() throws {
        XCTAssertEqual(tagOnFarWall.levelled,tagOnFarWall)
        let s=sin(10.0 * .pi/180), c=cos(10.0 * .pi/180)
        let leaning=RoomFrame(origin:Vector3(0,1,-3),xAxis:Vector3(1,0,0),yAxis:Vector3(0,s,c),zAxis:Vector3(0,-c,s))
        XCTAssertTrue(leaning.isValid)
        let level=try XCTUnwrap(leaning.levelled)
        XCTAssertEqual(level.origin,tagOnFarWall.origin)
        for (got,want) in [(level.xAxis,tagOnFarWall.xAxis),(level.yAxis,tagOnFarWall.yAxis),(level.zAxis,tagOnFarWall.zAxis)] {
            XCTAssertEqual(got.x,want.x,accuracy:1e-12); XCTAssertEqual(got.y,want.y,accuracy:1e-12); XCTAssertEqual(got.z,want.z,accuracy:1e-12)
        }
        XCTAssertTrue(level.isValid)
        let upsideDown=RoomFrame(origin:Vector3(0,1,-3),xAxis:Vector3(-1,0,0),yAxis:Vector3(0,0,1),zAxis:Vector3(0,1,0))
        XCTAssertTrue(upsideDown.isValid)
        XCTAssertEqual(upsideDown.levelled,upsideDown,"a tag hung upside down keeps its own right and down")
        let flat=RoomFrame(origin:Vector3(0,1,-3),xAxis:Vector3(1,0,0),yAxis:Vector3(0,1,0),zAxis:Vector3(0,0,1))
        XCTAssertTrue(flat.isValid)
        XCTAssertNil(flat.levelled,"a tag lying on a table is not a room frame for a floor plan")
        let sideways=RoomFrame(origin:Vector3(0,1,-3),xAxis:Vector3(0,-1,0),yAxis:Vector3(0,0,1),zAxis:Vector3(-1,0,0))
        XCTAssertTrue(sideways.isValid)
        XCTAssertNil(sideways.levelled)
        XCTAssertNil(RoomMap(grid:seenRoom(),frame:flat))
        var grid=FloorGrid()
        XCTAssertFalse(grid.setPrior(visit1,frame:flat))
        XCTAssertEqual(grid.priorCellCount,0)
        XCTAssertFalse(grid.setPrior(RoomMap(cellSize:0.2,originX:0,originY:0,width:1,height:1,encoded:"1f")!,frame:tagOnFarWall),"the prior's cells must be the grid's cells")
    }
}

final class RoomStructureStoreTests: XCTestCase {
    private var directory: URL!
    private var store: RoomMemoryStore!

    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store=RoomMemoryStore(directory:directory)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:directory) }

    func testVisitsLoadAfterRestartPerTagNewestLast() throws {
        try store.appendStructure(visit1,tagId:"feel-tag-01")
        try store.appendStructure(visit2,tagId:"feel-tag-01")
        try store.appendStructure(visit3,tagId:"feel-tag-02")
        XCTAssertEqual(RoomMemoryStore(directory:directory).structures(for:"feel-tag-01"),[visit1,visit2])
        XCTAssertEqual(RoomMemoryStore(directory:directory).structures(for:"feel-tag-02"),[visit3])
        XCTAssertEqual(store.structures(for:"feel-tag-03"),[])
        XCTAssertEqual(store.anchors(for:"feel-tag-01"),[],"maps and anchors are separate files")
    }
    func testFileUsesTheTableColumnNames() throws {
        try store.appendStructure(visit2,tagId:"feel-tag-01")
        let rows=try XCTUnwrap(JSONSerialization.jsonObject(with:try Data(contentsOf:directory.appendingPathComponent("feel-tag-01.structure.json"))) as? [[String:Any]])
        XCTAssertEqual(rows.count,1)
        XCTAssertEqual(Set(rows[0].keys),["schema","cell_size","origin_x","origin_y","width","height","cells"])
        XCTAssertEqual(rows[0]["cells"] as? String,"40f2u6b")
    }
    func testOnlyTheNewestTenVisitsAreKept() throws {
        for i in 1...12 { try store.appendStructure(roomMap(0.1,0,0,[String(repeating:"f",count:i)]),tagId:"feel-tag-01") }
        let kept=store.structures(for:"feel-tag-01")
        XCTAssertEqual(kept.count,RoomMemoryStore.keepStructures)
        XCTAssertEqual(RoomMemoryStore.keepStructures,10)
        XCTAssertEqual(kept.first?.width,3); XCTAssertEqual(kept.last?.width,12)
    }
    func testCorruptFileReadsAsNoVisitsAndIsReplaced() throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try Data("not maps".utf8).write(to:directory.appendingPathComponent("feel-tag-01.structure.json"))
        XCTAssertEqual(store.structures(for:"feel-tag-01"),[])
        try store.appendStructure(visit1,tagId:"feel-tag-01")
        XCTAssertEqual(store.structures(for:"feel-tag-01"),[visit1])
    }
    func testTagIdsAreSlugsOnlyAndRemoveDropsTheVisitsToo() throws {
        for bad in ["","../x","FEEL","tag id"] { XCTAssertThrowsError(try store.appendStructure(visit1,tagId:bad),bad) }
        XCTAssertEqual(store.structures(for:"../x"),[])
        try store.appendStructure(visit1,tagId:"feel-tag-01")
        try store.append(RoomAnchor(label:"exit",position:Vector3(-4,5.1,0.05),confidence:0.9,seenAt:utc("2026-10-17T20:00:00Z")),tagId:"feel-tag-01")
        try store.remove(tagId:"feel-tag-01")
        XCTAssertEqual(store.structures(for:"feel-tag-01"),[])
        XCTAssertEqual(store.anchors(for:"feel-tag-01"),[])
        try store.replaceStructures([visit2,visit3],tagId:"feel-tag-01")
        XCTAssertEqual(store.structures(for:"feel-tag-01"),[visit2,visit3])
    }
}
