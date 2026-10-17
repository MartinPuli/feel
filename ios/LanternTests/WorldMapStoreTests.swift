import XCTest
import ARKit
import FeelCore
@testable import Lantern

final class WorldMapStoreTests:XCTestCase {
    func testSecureMapDecoderRejectsNonMapData() throws {
        let data=try NSKeyedArchiver.archivedData(withRootObject:"not an AR map" as NSString,requiringSecureCoding:true)
        let archive=try PersistentMemoryArchive(mapID:UUID().uuidString,anchorID:UUID().uuidString,mapData:data,snapshot:SpatialMemoryManager().snapshot)
        XCTAssertThrowsError(try WorldMapStore.decodeMap(archive))
    }
    func testAtomicLocalEnvelopeRejectsInvalidMapAndDeletes() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url=directory.appendingPathComponent("map.json"),store=WorldMapStore(url:url)
        let archive=try PersistentMemoryArchive(mapID:UUID().uuidString,anchorID:UUID().uuidString,mapData:Data([1,2,3]),snapshot:SpatialMemoryManager().snapshot)
        try store.save(archive)
        XCTAssertEqual(try PersistentMemoryArchive.decode(Data(contentsOf:url)),archive)
        XCTAssertThrowsError(try store.load())
        try store.delete(); XCTAssertFalse(FileManager.default.fileExists(atPath:url.path)); XCTAssertNoThrow(try store.delete())
    }
}
