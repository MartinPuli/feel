import XCTest
import FeelCore
@testable import Lantern

final class SharedMemoryTests: XCTestCase {
    private final class Reader: SharedMemoryReading {
        var isEnabled = true
        var sessionIdentity: UUID? = UUID()
        var structure: ((Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void)?
        var targets: ((Result<[RoomAnchor], ChalkQueryError>) -> Void)?
        var calls = 0
        func fetchStructure(venueId: String, tagId: String, completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void) { calls += 1; structure = completion }
        func fetchAnchors(venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void) { calls += 1; targets = completion }
    }
    private let frame = RoomFrame(origin: Vector3(0,0,-3), xAxis: Vector3(1,0,0), yAxis: Vector3(0,0,1), zAxis: Vector3(0,-1,0))
    private var directory: URL!
    private var store: RoomMemoryStore!
    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); store = RoomMemoryStore(directory: directory) }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    private func tag(_ world: Int = 1) -> TagSighting { TagSighting(tagId: "room-01", frame: frame, worldEpoch: world, timestamp: 1) }
    private var map: RoomMap { RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"1b1f")! }
    private func setup() -> (RoomMemory, Reader) {
        let memory = RoomMemory(store:store), reader = Reader()
        memory.reader = reader; memory.venue = { "venue-01" }; memory.isLive = { true }; memory.sawTag(tag())
        return (memory,reader)
    }
    func testSharedReadRequiresConsentLiveTagAndSelectedVenue() {
        let (memory,reader) = setup()
        reader.isEnabled = false; memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        reader.isEnabled = true; memory.isLive = { false }; memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        memory.isLive = { true }; memory.venue = { nil }; memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        memory.venue = { "venue-01" }; memory.forgetTag(); memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        XCTAssertEqual(reader.calls,0)
    }
    func testLateWorldReplyCannotSeedOrPersist() {
        let (memory,reader) = setup(); var seeded = 0; memory.onSharedStructure = { _ in seeded += 1 }
        memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        memory.forgetTag(); memory.sawTag(tag(2)); reader.structure?(.success((map,1)))
        XCTAssertEqual(seeded,0); XCTAssertTrue(store.structures(for:"room-01").isEmpty)
        XCTAssertNil(memory.structureToSeed(for:tag(2)))
    }
    func testAccountConsentAndVenueChangesDiscardPendingReplies() {
        for change in 0..<3 {
            let (memory,reader) = setup(); var seeded = 0; memory.onSharedStructure = { _ in seeded += 1 }
            memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
            if change == 0 { reader.sessionIdentity = UUID() }
            if change == 1 { reader.isEnabled = false }
            if change == 2 { memory.venue = { "other-venue" } }
            reader.structure?(.success((map,1)))
            XCTAssertEqual(seeded,0)
        }
    }
    func testSharedResultsAreEphemeralAndSeedOnlyOncePerWorld() {
        let (memory,reader) = setup(); var seeds: [RoomMap] = []
        memory.onSharedStructure = { sighting in if let map = memory.structureToSeed(for:sighting) { seeds.append(map) } }
        memory.fetchSharedStructure(venueId:nil,tagId:"room-01"); reader.structure?(.success((map,1)))
        XCTAssertEqual(seeds,[map]); XCTAssertTrue(store.structures(for:"room-01").isEmpty)
        memory.fetchSharedStructure(venueId:nil,tagId:"room-01"); XCTAssertEqual(reader.calls,2)
        XCTAssertNil(memory.structureToSeed(for:tag()))
        var cleared = 0; memory.onSharedInvalidated = { cleared += 1 }; memory.invalidateSharedMemory()
        XCTAssertEqual(cleared,1); XCTAssertNil(memory.structureToSeed(for:tag()))
    }
    func testDelayedSharedMapReseedsOnlyNewSpaceAfterLocalSeed() throws {
        let own = RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"1b1u")!
        try store.appendStructure(own, tagId:"room-01")
        let (memory,reader) = setup()
        XCTAssertEqual(memory.structureToSeed(for:tag())?.encoded, "1b")
        var updates: [RoomMap] = []
        memory.onSharedStructure = { sighting in if let next = memory.structureToSeed(for:sighting) { updates.append(next) } }
        memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        reader.structure?(.success((RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"2f")!,1)))
        XCTAssertEqual(updates.first?.encoded,"1b1f")
        XCTAssertNil(memory.structureToSeed(for:tag()))
        XCTAssertEqual(store.structures(for:"room-01"),[own])
    }
    func testLocalCellsOverrideSharedVotesAndUnknownCellsCanUseSharedPrior() {
        let own = RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"1b1u")!
        let shared = RoomMap(cellSize:0.1,originX:0,originY:0,width:2,height:1,encoded:"2f")!
        XCTAssertEqual(RoomMemory.mergePrior(local:own,shared:shared)?.encoded,"1b1f")
    }
    func testSharedTargetsDoNotOverwriteOwnConfirmedTargetOrPersist() throws {
        let own = RoomAnchor(label:"exit",position:Vector3(1,0,0),confidence:0.9,seenAt:Date(timeIntervalSince1970:1_800_000_000))
        try store.append(own,tagId:"room-01")
        let (memory,reader) = setup(); memory.fetchSharedStructure(venueId:nil,tagId:"room-01")
        reader.targets?(.success([RoomAnchor(label:"exit",position:Vector3(-1,0,0),confidence:0.5,seenAt:Date()),RoomAnchor(label:"chair",position:Vector3(0,0,0),confidence:0.5,seenAt:Date())]))
        XCTAssertEqual(memory.recall("exit",worldEpoch:1,now:2)?.position,frame.worldPoint(tag:own.position))
        XCTAssertTrue(memory.remembers("chair",worldEpoch:1)); XCTAssertEqual(store.anchors(for:"room-01"),[own])
        reader.sessionIdentity = UUID(); XCTAssertFalse(memory.remembers("chair",worldEpoch:1))
    }
}
