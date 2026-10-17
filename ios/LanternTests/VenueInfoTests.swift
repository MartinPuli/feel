import XCTest
import FeelCore
@testable import Lantern

final class VenueInfoTests: XCTestCase {
    private var directory: URL!
    private var vector: Data!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        vector = try Data(contentsOf: url.appendingPathComponent("protocol/venue-pack-v1.json"))
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.handler = nil; StubURLProtocol.lastRequest = nil
    }

    private func venue() -> VenueInfo {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return VenueInfo(store: VenuePackStore(directory: directory), session: URLSession(configuration: config),
                         now: { ISO8601DateFormatter().date(from: "2026-10-18T09:00:00Z")! })
    }
    private func download(_ venue: VenueInfo, from address: String = "https://packs.example.test/example-hall.json", status: Int = 200) {
        let vector = vector!
        StubURLProtocol.handler = { _, _ in (status, vector) }
        let done = expectation(description: "download")
        venue.download(from: address) { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testDownloadInstallsThePackAndSurvivesRestart() {
        download(venue())
        XCTAssertEqual(venue().pack?.venueName, "Example Hall")
    }
    func testFailedDownloadKeepsThePreviousPack() {
        let venue = venue()
        download(venue)
        download(venue, status: 500)
        XCTAssertEqual(venue.pack?.venueName, "Example Hall")
        XCTAssertTrue(venue.status.contains("previous pack for Example Hall is kept"), venue.status)
    }
    func testOnlyHTTPSAddressesAreFetched() {
        let venue = venue()
        download(venue, from: "http://packs.example.test/example-hall.json")
        XCTAssertNil(StubURLProtocol.lastRequest)
        XCTAssertNil(venue.pack)
    }
    func testVoiceAnswerReadsTheInstalledPack() {
        let venue = venue()
        download(venue)
        let reply = venue.answer("where is the bathroom")
        XCTAssertTrue((reply["answer"] as? String)?.hasPrefix("Ground floor, past the elevators on the left. Source checked") == true)
    }
    func testVoiceAnswerWithoutAPackSaysSo() {
        XCTAssertNotNil(venue().answer("restroom")["error"])
    }
    func testOverviewListsEveryPlaceWithItsCurrentAnswer() {
        let venue = venue()
        download(venue)
        XCTAssertEqual(venue.overview.count, 2)
        XCTAssertTrue(venue.overview[0].hasPrefix("Main entrance: The north automatic door is out of service."), venue.overview[0])
    }
    func testRemoveDeletesThePack() {
        let venue = venue()
        download(venue)
        venue.remove()
        XCTAssertNil(venue.pack)
        XCTAssertNil(self.venue().pack)
    }
    func testVenueToolDecodesAQuestion() throws {
        XCTAssertEqual(try VoiceCommand.decode(name: "venue_info", arguments: #"{"question":" where is the restroom "}"#), .venueInfo("where is the restroom"))
        for arguments in [#"{}"#, #"{"question":""}"#, #"{"question":"a\nb"}"#, #"{"question":"x","extra":1}"#] {
            XCTAssertThrowsError(try VoiceCommand.decode(name: "venue_info", arguments: arguments), arguments)
        }
        XCTAssertTrue(VoiceCommand.tools.contains { ($0["name"] as? String) == "venue_info" })
        XCTAssertTrue(VoiceCommand.instructions.contains("venue_info"))
    }
}
