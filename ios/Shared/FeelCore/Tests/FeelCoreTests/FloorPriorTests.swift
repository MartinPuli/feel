import XCTest
@testable import FeelCore

final class FloorPriorTests: XCTestCase {
    func testWithdrawingPriorPreservesLiveCameraClassifications() {
        var grid = FloorGrid()
        FloorGridTests.paint(&grid,x:0.05...0.25,z:(-0.25)...(-0.05),height:1,camera:.zero)
        let observations = grid.observedCells
        XCTAssertFalse(observations.isEmpty)
        let frame = RoomFrame(origin:Vector3(0,0,-3),xAxis:Vector3(1,0,0),yAxis:Vector3(0,0,1),zAxis:Vector3(0,-1,0))
        let map = RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"2f")!
        XCTAssertTrue(grid.setPrior(map,frame:frame)); XCTAssertGreaterThan(grid.priorCellCount,0)
        grid.clearPrior()
        XCTAssertEqual(grid.priorCellCount,0); XCTAssertEqual(grid.observedCells,observations)
        for (cell,state) in observations { XCTAssertEqual(grid.state(cell),state) }
    }
}
