import XCTest
import FeelCore
@testable import Lantern

final class SavedWorldMapsTests:XCTestCase {
    private func archive() throws -> PersistentMemoryArchive {
        var memory=SpatialMemoryManager(); try memory.begin(session:"original")
        _=try memory.remember(id:"desk",name:"Desk",sample:MemoryPose(session:"original",pose:CameraPose(),timestamp:1,tracking:true),now:1)
        return try PersistentMemoryArchive(mapID:UUID().uuidString,anchorID:UUID().uuidString,mapData:Data([1]),snapshot:memory.snapshot)
    }
    private func observation(_ archive:PersistentMemoryArchive,time:Double,world:Int=2,anchor:String?=nil,relocalizing:Bool=false,tracking:Bool=true)->SavedMapObservation {
        SavedMapObservation(epoch:1,worldEpoch:world,mapID:archive.mapID,anchorID:anchor,pose:CameraPose(),timestamp:time,tracking:tracking,relocalizing:relocalizing)
    }
    func testRestoreRequiresActualRelocalizationAndMatchingMarkerThenFreshSettling() throws {
        var clock=1.0
        let maps=SavedWorldMaps(now:{ clock }),saved=try archive()
        var installed:[Int]=[]
        maps.onRestored={ archive,world in XCTAssertEqual(archive.bookmarks.count,1); installed.append(world) }
        maps.prepareRestore(saved); maps.worldStarted(epoch:1,worldEpoch:2,mapID:saved.mapID)
        // Normal tracking and a known anchor alone do not establish the restored coordinate frame.
        for _ in 0..<8 { clock += 0.1; maps.observe(observation(saved,time:clock,anchor:saved.anchorID)) }
        XCTAssertTrue(installed.isEmpty)
        clock += 0.1; maps.observe(observation(saved,time:clock,relocalizing:true,tracking:false))
        for _ in 0..<8 { clock += 0.1; maps.observe(observation(saved,time:clock,anchor:UUID().uuidString)) }
        XCTAssertTrue(installed.isEmpty)
        for _ in 0..<8 { clock += 0.1; maps.observe(observation(saved,time:clock,anchor:saved.anchorID)) }
        XCTAssertEqual(installed,[2]); XCTAssertFalse(maps.isRestoring)
        maps.observe(observation(saved,time:clock,anchor:saved.anchorID)); XCTAssertEqual(installed,[2])
    }
    func testStaleFramesAndOldWorldCannotInstall() throws {
        var clock=2.0
        let maps=SavedWorldMaps(now:{ clock }),saved=try archive()
        var installs=0; maps.onRestored={ _,_ in installs += 1 }
        maps.prepareRestore(saved); maps.worldStarted(epoch:1,worldEpoch:2,mapID:saved.mapID)
        maps.observe(observation(saved,time:clock,relocalizing:true,tracking:false))
        for _ in 0..<8 {
            clock += 0.1
            maps.observe(observation(saved,time:clock,world:1,anchor:saved.anchorID))
            maps.observe(observation(saved,time:clock-1,anchor:saved.anchorID))
        }
        XCTAssertEqual(installs,0); XCTAssertTrue(maps.isRestoring)
        maps.cancel()
        for _ in 0..<8 { clock += 0.1; maps.observe(observation(saved,time:clock,anchor:saved.anchorID)) }
        XCTAssertEqual(installs,0)
    }
    func testWorldResetAndInterruptionCancelRestoreButOldWorldEndDoesNot() throws {
        let maps=SavedWorldMaps(now:{ 1 }),saved=try archive()
        maps.prepareRestore(saved)
        maps.worldEnded(epoch:0,worldEpoch:1)
        XCTAssertTrue(maps.isRestoring)
        maps.worldStarted(epoch:1,worldEpoch:2,mapID:saved.mapID)
        maps.worldEnded(epoch:0,worldEpoch:1)
        XCTAssertTrue(maps.isRestoring)
        maps.worldEnded(epoch:1,worldEpoch:2)
        XCTAssertFalse(maps.isRestoring)
        maps.prepareRestore(saved); maps.worldStarted(epoch:1,worldEpoch:2,mapID:saved.mapID)
        maps.worldStarted(epoch:1,worldEpoch:3,mapID:nil)
        XCTAssertFalse(maps.isRestoring)
    }
    func testRestoreExpiresEvenWithNoFramesOrWorldStart() throws {
        var clock=1.0
        let maps=SavedWorldMaps(now:{ clock })
        maps.prepareRestore(try archive())
        clock=62; maps.checkDeadline()
        XCTAssertFalse(maps.isBusy); XCTAssertFalse(maps.isRestoring)
    }
    func testCancelledCaptureCannotWriteOrClaimSuccess() throws {
        let maps=SavedWorldMaps()
        var completion:((Result<CapturedWorldMap,Error>)->Void)?
        maps.capture={ _,callback in completion=callback }
        var memory=SpatialMemoryManager(); try memory.begin(session:"original")
        _=try memory.remember(id:"desk",name:"Desk",sample:MemoryPose(session:"original",pose:CameraPose(),timestamp:1,tracking:true),now:1)
        maps.save(snapshot:memory.snapshot,worldEpoch:2)
        XCTAssertTrue(maps.isBusy)
        maps.cancel()
        completion?(.success(CapturedWorldMap(data:Data([1]),mapID:UUID().uuidString,anchorID:UUID().uuidString)))
        XCTAssertFalse(maps.isBusy)
        XCTAssertNotEqual(maps.message,"Room and places saved on this iPhone.")
    }
}
