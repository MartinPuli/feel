import XCTest
@testable import FeelCore

final class VenuePackStoreTests: XCTestCase {
    private var directory: URL!
    private var store: VenuePackStore!
    private let now=utc("2026-10-18T09:00:00Z")

    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store=VenuePackStore(directory:directory)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:directory) }

    func testInstalledPackLoadsAfterRestart() throws {
        try store.install(try venueVector(),now:now)
        XCTAssertEqual(VenuePackStore(directory:directory).load()?.venueId,"example-hall")
    }
    func testInvalidDownloadKeepsThePreviousPack() throws {
        try store.install(try venueVector(),now:now)
        XCTAssertThrowsError(try store.install(Data("{\"schema\":1".utf8),now:now))
        XCTAssertEqual(store.load()?.venueId,"example-hall")
    }
    func testExpiredDownloadIsRefused() throws {
        XCTAssertThrowsError(try store.install(try venueVector(),now:utc("2026-10-25T00:00:00Z")))
        XCTAssertNil(store.load())
    }
    func testOlderPackForTheSameVenueIsRefused() throws {
        try store.install(try venueVector(),now:now)
        let older=try venuePack { $0["generated_at"]="2026-10-17T11:30:00Z" }
        XCTAssertNoThrow(try VenuePack.decode(older))
        XCTAssertThrowsError(try store.install(older,now:now))
        XCTAssertEqual(store.load()?.generatedAt,utc("2026-10-17T12:00:00Z"))
    }
    func testCorruptFileOnDiskIsIgnored() throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try Data("not a pack".utf8).write(to:directory.appendingPathComponent("venue-pack.json"))
        XCTAssertNil(store.load())
    }
    func testRemoveDeletesThePack() throws {
        try store.install(try venueVector(),now:now)
        try store.remove()
        XCTAssertNil(store.load())
    }
}
