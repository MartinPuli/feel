import XCTest
import FeelCore
@testable import Lantern

/// A shared-memory reader fed by hand: records what room was asked for and answers when the test says.
final class ScriptedSharedMemory: SharedMemoryReading {
    private(set) var structureCalls: [(venueId: String, tagId: String)] = []
    private(set) var anchorCalls: [(venueId: String, tagId: String)] = []
    private var structureCompletions: [(Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void] = []
    private var anchorCompletions: [(Result<[RoomAnchor], ChalkQueryError>) -> Void] = []
    func fetchStructure(venueId: String, tagId: String, completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void) {
        structureCalls.append((venueId, tagId)); structureCompletions.append(completion)
    }
    func fetchAnchors(venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void) {
        anchorCalls.append((venueId, tagId)); anchorCompletions.append(completion)
    }
    func answerStructure(_ map: RoomMap?, visits: Int) { structureCompletions.removeFirst()(.success((map, visits))) }
    func failStructure(_ error: ChalkQueryError) { structureCompletions.removeFirst()(.failure(error)) }
    func answerAnchors(_ anchors: [RoomAnchor]) { anchorCompletions.removeFirst()(.success(anchors)) }
}

/// The download side of room memory: the structure Chalk merged from every phone's shared visits becomes one visit in
/// the local store, so a first visit to a room can route, and the targets remembered there become sightings. Fetched
/// once per tag per run; the phone's own stores stay the memory when nothing comes back.
final class SharedMemoryTests: XCTestCase {
    private var directory: URL!
    private var store: RoomMemoryStore!
    private var now = ISO8601DateFormatter().date(from: "2026-10-18T14:00:00Z")!
    private let tagFrame = RoomFrame(origin: Vector3(0, 0, -3), xAxis: Vector3(1, 0, 0), yAxis: Vector3(0, 0, 1), zAxis: Vector3(0, -1, 0))
    /// The merged 8 × 6 map of protocol/room-map-v1.json, as Chalk serves it.
    private let merged = RoomMap(cellSize: 0.1, originX: -0.2, originY: 0, width: 8, height: 6, encoded: "28f2b10f2u6b")!
    private let own = RoomMap(cellSize: 0.1, originX: 0, originY: 0, width: 6, height: 6, encoded: "14f2b4f2b8f6b")!
    private let exit = RoomAnchor(label: "exit", position: Vector3(1.5, 6, 0), confidence: 0.5, seenAt: ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!)

    final class Seeds { var calls: [(map: RoomMap, frame: RoomFrame, worldEpoch: Int)] = [] }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RoomMemoryStore(directory: directory)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func sighting(_ tagId: String = "feel-tag-01", worldEpoch: Int = 1) -> TagSighting {
        TagSighting(tagId: tagId, frame: tagFrame, worldEpoch: worldEpoch, timestamp: 1)
    }
    private func makeMemory() -> (RoomMemory, ScriptedSharedMemory) {
        let reader = ScriptedSharedMemory()
        let memory = RoomMemory(store: store, now: { self.now })
        memory.reader = reader
        return (memory, reader)
    }
    private func makeModel() -> (LanternModel, RoomMemory, ScriptedSharedMemory, Seeds) {
        let (memory, reader) = makeMemory()
        let model = LanternModel(voice: RealtimeVoiceSession(configuration: nil, speaksLocally: false), chalkStore: MemoryChalkStore(),
                                 gatewayFactory: { _ in StubChatGateway() }, localFinder: StubLocalFinder(), roomMemory: memory, uploader: RecordingUploader(), chalkQuery: nil)
        let seeds = Seeds()
        model.floorGridSeeder = { map, frame, worldEpoch in seeds.calls.append((map, frame, worldEpoch)) }
        return (model, memory, reader, seeds)
    }

    func testTheDownloadedStructureBecomesOneVisitInTheLocalStore() {
        let (memory, reader) = makeMemory()
        memory.sawTag(sighting())
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        XCTAssertEqual(reader.structureCalls.map { "\($0.venueId):\($0.tagId)" }, ["harvard-yard:feel-tag-01"])
        XCTAssertEqual(memory.structureStatus["shared"] as? String, "fetching")
        reader.answerStructure(merged, visits: 3)
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [merged], "Chalk's vote is one visit among this phone's own")
        XCTAssertEqual(memory.structures, [merged], "the loaded tag's visits follow the store")
        XCTAssertEqual(memory.structureStatus["shared"] as? String, "3 shared visits merged")
        XCTAssertEqual(memory.structureStatus["visits"] as? Int, 1)
    }

    func testTheRoomIsFetchedOncePerTagPerRunAndTheSameMapIsNeverStoredTwice() throws {
        let (memory, reader) = makeMemory()
        try store.appendStructure(merged, tagId: "feel-tag-01")
        memory.sawTag(sighting())
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        memory.sawTag(sighting("feel-tag-02"))
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-02")
        XCTAssertEqual(reader.structureCalls.map(\.tagId), ["feel-tag-01", "feel-tag-02"], "the tag is seen twice a second; the room is fetched once")
        reader.answerStructure(merged, visits: 3)
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [merged], "the map already stored is not a second visit")
        reader.answerStructure(nil, visits: 0)
        XCTAssertEqual(store.structures(for: "feel-tag-02"), [], "nobody shared a visit to this room")
        XCTAssertEqual(memory.structureStatus["shared"] as? String, "nothing shared yet")
    }

    func testAFailedFetchIsSaidAndRetriedAMinuteLater() {
        let (memory, reader) = makeMemory()
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        reader.failStructure(.http(401))
        XCTAssertEqual(memory.structureStatus["shared"] as? String, "failed: http(401)")
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        XCTAssertEqual(reader.structureCalls.count, 1, "not hammered: the tag is seen every frame")
        now = now.addingTimeInterval(RoomMemory.retryAfterFailure)
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        XCTAssertEqual(reader.structureCalls.count, 2)
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [], "a failure changes nothing on the phone")
    }

    func testWithoutAReaderTheLocalStoreIsTheMemory() throws {
        let memory = RoomMemory(store: store)
        try store.appendStructure(own, tagId: "feel-tag-01")
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [own])
        XCTAssertEqual(memory.structureStatus["shared"] as? String, "no reader in this build")
    }

    func testSharedTargetsBecomeSightingsOnceAndThisPhonesStayFirst() throws {
        let (memory, reader) = makeMemory()
        let mine = RoomAnchor(label: "exit", position: Vector3(1.4, 6.1, 0), confidence: 0.9, seenAt: now)
        try store.append(mine, tagId: "feel-tag-01")
        memory.sawTag(sighting())
        memory.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        XCTAssertEqual(reader.anchorCalls.map(\.tagId), ["feel-tag-01"])
        reader.answerAnchors([exit])
        XCTAssertEqual(store.anchors(for: "feel-tag-01"), [mine, exit])
        XCTAssertEqual(memory.anchors, [mine, exit])
        XCTAssertNotNil(RememberedTarget.remembered("exit", in: memory.anchors))
        reader.answerStructure(nil, visits: 0)
        let again = RoomMemory(store: store, now: { self.now }); again.reader = reader
        again.fetchSharedStructure(venueId: "harvard-yard", tagId: "feel-tag-01")
        reader.answerAnchors([exit])
        XCTAssertEqual(store.anchors(for: "feel-tag-01"), [mine, exit], "the same shared sighting is not appended again")
    }

    func testAFirstVisitRoutesOnceTheSharedStructureArrives() {
        let (model, memory, reader, seeds) = makeModel()
        model.sawTag(sighting())   // the model's own path: a live frame delivers the tag here
        XCTAssertTrue(seeds.calls.isEmpty, "nothing is remembered locally on a first visit")
        XCTAssertEqual(reader.structureCalls.map { "\($0.venueId):\($0.tagId)" }, ["rubenstein-treehouse:feel-tag-01"], "filed under the demo venue without a venue pack")
        reader.answerStructure(merged, visits: 3)
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [merged])
        XCTAssertEqual(seeds.calls.count, 1, "the shared structure arrives while the tag is in view: the planner gets it now")
        XCTAssertEqual(seeds.calls.first?.map, merged)
        XCTAssertEqual(seeds.calls.first?.frame, tagFrame)
        XCTAssertEqual(seeds.calls.first?.worldEpoch, 1)
        model.sawTag(sighting())
        XCTAssertEqual(seeds.calls.count, 1, "seeded once per world")
        XCTAssertEqual(reader.structureCalls.count, 1, "fetched once per tag")
        XCTAssertEqual(memory.structureStatus["seeded"] as? Bool, true)
        XCTAssertEqual(memory.structureStatus["shared"] as? String, "3 shared visits merged")
    }

    func testAWorldSeededFromLocalVisitsWaitsForTheNextWorldToUseTheSharedStructure() throws {
        let (model, _, reader, seeds) = makeModel()
        try store.appendStructure(own, tagId: "feel-tag-02")
        model.sawTag(sighting("feel-tag-02"))
        XCTAssertEqual(seeds.calls.count, 1)
        XCTAssertEqual(seeds.calls.first?.map, own)
        reader.answerStructure(merged, visits: 3)
        XCTAssertEqual(seeds.calls.count, 1, "this world already has its prior; the camera overrides it as it goes")
        XCTAssertEqual(store.structures(for: "feel-tag-02"), [own, merged])
        model.sawTag(sighting("feel-tag-02", worldEpoch: 2))
        XCTAssertEqual(seeds.calls.count, 2)
        XCTAssertEqual(seeds.calls.last?.map, RoomMap.merge([own, merged]), "the next world gets the vote of this phone's visit and Chalk's")
    }

    func testAMapArrivingAfterAStopIsKeptButSeedsNothing() {
        let (model, memory, reader, seeds) = makeModel()
        model.sawTag(sighting())
        model.stop()
        XCTAssertNil(memory.sighting)
        reader.answerStructure(merged, visits: 3)
        XCTAssertEqual(store.structures(for: "feel-tag-01"), [merged], "a visit is a fact about the room, kept for next time")
        XCTAssertTrue(seeds.calls.isEmpty, "no world to seed")
        model.sawTag(sighting(worldEpoch: 2))
        XCTAssertEqual(seeds.calls.count, 1, "the next session starts with it")
        XCTAssertEqual(reader.structureCalls.count, 1, "and does not fetch the room again this run")
    }
}
