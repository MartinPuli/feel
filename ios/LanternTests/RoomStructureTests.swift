import XCTest
import FeelCore
@testable import Lantern

/// Room structure on the phone: the floor grid a session learned is kept per tag as one visit when sensing stops or
/// tracking resets, and the merged structure of earlier visits seeds the route planner the first time the tag is seen
/// in a world. Memory seeds routes before the camera has seen the room; the pins always come from live depth.
final class RoomStructureTests: XCTestCase {
    private var directory: URL!
    private var store: RoomMemoryStore!
    /// The tag upright on the wall 3 m ahead of the identity camera: out of the tag is world +z, down is −y, right along it is +x.
    private let tagFrame = RoomFrame(origin: Vector3(0, 0, -3), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 0, 1), zAxis: Vector3(0, -1, 0))
    /// Two earlier visits (protocol/room-map-v1.json): a 6 × 6 room with a chair and a far wall, then the same room without the chair.
    private let visit1 = RoomMap(cellSize: 0.1, originX: 0, originY: 0, width: 6, height: 6, encoded: "14f2b4f2b8f6b")!
    private let visit2 = RoomMap(cellSize: 0.1, originX: -0.2, originY: 0, width: 8, height: 6, encoded: "40f2u6b")!
    /// What this session's camera saw: a 5 × 5 view of the same room, the chair's place free, the far wall blocked.
    private let seen = RoomMap(cellSize: 0.1, originX: 0.1, originY: 0.1, width: 5, height: 5, encoded: "20f5b")!
    /// Twenty free cells: the smallest session that counts as a visit.
    private let glance = RoomMap(cellSize: 0.1, originX: 0, originY: 0, width: 5, height: 4, encoded: "20f")!

    final class Seeds { var calls: [(map: RoomMap, frame: RoomFrame, worldEpoch: Int)] = [] }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RoomMemoryStore(directory: directory)
        try store.appendStructure(visit1, tagId: "feel-tag-01")
        try store.appendStructure(visit2, tagId: "feel-tag-01")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func sighting(_ tagId: String = "feel-tag-01", worldEpoch: Int = 1) -> TagSighting {
        TagSighting(tagId: tagId, frame: tagFrame, worldEpoch: worldEpoch, timestamp: 1)
    }
    private func makeModel() -> (LanternModel, RoomMemory, Seeds) {
        let memory = RoomMemory(store: store)
        let model = LanternModel(voice: RealtimeVoiceSession(configuration: nil, speaksLocally: false), chalkStore: MemoryChalkStore(),
                                 gatewayFactory: { _ in StubChatGateway() }, localFinder: StubLocalFinder(), roomMemory: memory)
        let seeds = Seeds()
        model.floorGridSeeder = { map, frame, worldEpoch in seeds.calls.append((map, frame, worldEpoch)) }
        return (model, memory, seeds)
    }
    private func structureStatus(_ model: LanternModel) throws -> [String: Any] {
        try XCTUnwrap(model.voiceSnapshot()["room_structure"] as? [String: Any])
    }

    func testTheFirstSightingOfATagSeedsThePlannerWithTheMergedVisitsOncePerWorld() {
        let (model, _, seeds) = makeModel()
        model.sawTag(sighting())
        XCTAssertEqual(seeds.calls.count, 1)
        XCTAssertEqual(seeds.calls.first?.map, RoomMap.merge([visit1, visit2]), "the planner gets the vote of the visits, not the last one")
        XCTAssertEqual(seeds.calls.first?.frame, tagFrame)
        XCTAssertEqual(seeds.calls.first?.worldEpoch, 1)
        model.sawTag(sighting())
        XCTAssertEqual(seeds.calls.count, 1, "the tag is seen twice a second; the grid is seeded once")
        model.sawTag(sighting(worldEpoch: 2))
        XCTAssertEqual(seeds.calls.count, 2, "a new world starts with an empty grid: seed it again")
        XCTAssertEqual(seeds.calls.last?.worldEpoch, 2)
    }
    func testAForgottenTagFrameSeedsAgainWhenTheTagComesBack() {
        let (model, memory, seeds) = makeModel()
        model.sawTag(sighting())
        model.perception.onInvalidated?(0)   // tracking reset: the grid and the tag frame are gone together
        XCTAssertNil(memory.sighting)
        model.sawTag(sighting(worldEpoch: 2))
        XCTAssertEqual(seeds.calls.count, 2)
        model.stop()
        model.sawTag(sighting(worldEpoch: 3))
        XCTAssertEqual(seeds.calls.count, 3, "after a stop the next session's grid is empty too")
    }
    func testATagWithoutRememberedStructureSeedsNothing() throws {
        let (model, _, seeds) = makeModel()
        model.sawTag(sighting("feel-tag-02"))
        XCTAssertTrue(seeds.calls.isEmpty)
        let status = try structureStatus(model)
        XCTAssertEqual(status["tag"] as? String, "feel-tag-02")
        XCTAssertEqual(status["visits"] as? Int, 0)
        XCTAssertEqual(status["seeded"] as? Bool, false)
    }
    func testAMapFromTheCameraIsKeptAsOneMoreVisit() throws {
        let (model, memory, _) = makeModel()
        model.sawTag(sighting())
        model.perception.onRoomMap?("feel-tag-01", seen)
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [visit1, visit2, seen])
        XCTAssertEqual(memory.structures, [visit1, visit2, seen], "the loaded tag's visits follow the store")
        let status = try structureStatus(model)
        XCTAssertEqual(status["visits"] as? Int, 3)
        XCTAssertEqual(status["cells"] as? Int, 46, "the three visits cover 8 × 6 cells but two the wall's left end")
        XCTAssertEqual(status["blocked"] as? Int, 6, "the wall; the chair seen on one visit of three is gone")
    }
    func testASessionThatSawAlmostNothingIsNotAVisit() {
        let (model, _, _) = makeModel()
        model.perception.onRoomMap?("feel-tag-01", RoomMap(cellSize: 0.1, originX: 0, originY: 0, width: 4, height: 5, encoded: "19f1u")!)
        XCTAssertEqual(store.structures(for: "feel-tag-01").count, 2, "nineteen cells are a glance, not a visit")
        XCTAssertEqual(RoomMemory.minimumVisitCells, 20)
        model.perception.onRoomMap?("feel-tag-01", glance)
        XCTAssertEqual(store.structures(for: "feel-tag-01").count, 3)
    }
    func testAMapKeptAfterStopBelongsToItsTagThoughTheFrameIsForgotten() {
        let (model, memory, _) = makeModel()
        model.sawTag(sighting())
        model.stop()
        XCTAssertNil(memory.sighting)
        model.perception.onRoomMap?("feel-tag-01", glance)
        XCTAssertEqual(store.structures(for: "feel-tag-01").count, 3)
        XCTAssertEqual(memory.structures.count, 3)
        model.perception.onRoomMap?("feel-tag-02", glance)
        XCTAssertEqual(store.structures(for: "feel-tag-02"), [glance])
        XCTAssertEqual(memory.structures.count, 3, "another tag's visit does not touch the loaded tag")
    }
    func testStatusReportsTheRememberedStructure() throws {
        let (model, _, _) = makeModel()
        var status = try structureStatus(model)
        XCTAssertEqual(status["tag"] as? String, "none")
        XCTAssertEqual(status["visits"] as? Int, 0)
        XCTAssertEqual(status["cells"] as? Int, 0)
        XCTAssertEqual(status["seeded"] as? Bool, false)
        model.sawTag(sighting())
        status = try structureStatus(model)
        XCTAssertEqual(status["tag"] as? String, "feel-tag-01")
        XCTAssertEqual(status["visits"] as? Int, 2)
        XCTAssertEqual(status["cells"] as? Int, RoomMap.merge([visit1, visit2])?.observedCount)
        XCTAssertEqual(status["seeded"] as? Bool, true)
        XCTAssertTrue((status["note"] as? String)?.contains("live depth") == true)
        XCTAssertNotNil(model.voiceSnapshot()["room_memory"], "the anchors' entry stays")
    }
    func testAKeptVisitLeavesThroughTheUploaderAndTheDownloadIsNotWiredYet() {
        let uploader = RecordingUploader()
        let memory = RoomMemory(store: store)
        memory.uploader = uploader
        XCTAssertTrue(memory.keepStructure(seen, tagId: "feel-tag-01"))
        XCTAssertEqual(uploader.structures.map { $0.tagId }, ["feel-tag-01"])
        XCTAssertEqual(uploader.structures.first?.map, seen, "the visit kept on the phone is the one uploaded")
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [visit1, visit2, seen], "the local store is the memory on the phone; the download from Chalk is not wired")
    }
    func testPerceptionOffersARoomMapCallbackAndASeedingEntryPoint() {
        let perception = ARPerception()
        var kept: [(String, RoomMap)] = []
        perception.onRoomMap = { kept.append(($0, $1)) }
        perception.onRoomMap?("feel-tag-01", visit1)
        XCTAssertEqual(kept.map(\.0), ["feel-tag-01"])
        XCTAssertEqual(kept.map(\.1), [visit1])
        perception.seedFloorGrid(visit1, frame: tagFrame, worldEpoch: 0)   // no session running: the AR queue ignores it
    }
}
