import XCTest
import CryptoKit
@testable import FeelCore

/// Shared vector: protocol/venue-pack-v1.json, built by chalk/feel_chalk/venue_pack.py.
func venueVector() throws -> Data {
    var url=URL(fileURLWithPath:#filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return try Data(contentsOf:url.appendingPathComponent("protocol/venue-pack-v1.json"))
}

/// Re-wraps an edited payload with a correct hash, so a test reaches the rule it is about.
func venuePack(editing edit: (inout [String:Any]) -> Void) throws -> Data {
    let envelope=try XCTUnwrap(JSONSerialization.jsonObject(with:try venueVector()) as? [String:Any])
    var payload=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(try XCTUnwrap(envelope["payload"] as? String).utf8)) as? [String:Any])
    edit(&payload)
    let text=String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self)
    let hash=SHA256.hash(data:Data(text.utf8)).map { String(format:"%02x",$0) }.joined()
    return try JSONSerialization.data(withJSONObject:["schema":1,"sha256":hash,"payload":text])
}

func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from:text)! }

final class VenuePackTests: XCTestCase {
    private func pack() throws -> VenuePack { try VenuePack.decode(try venueVector()) }

    func testSharedVectorDecodesAndVerifies() throws {
        let pack=try pack()
        XCTAssertEqual(pack.venueName,"Example Hall")
        XCTAssertEqual(pack.entries.count,3)
        XCTAssertEqual(pack.expiresAt,utc("2026-10-24T12:00:00Z"))
    }
    func testTamperedPayloadIsRejected() throws {
        let text=String(decoding:try venueVector(),as:UTF8.self).replacingOccurrences(of:"Ground floor",with:"Top floor")
        XCTAssertThrowsError(try VenuePack.decode(Data(text.utf8)))
    }
    func testUnsupportedSchemaIsRejected() throws {
        let text=String(decoding:try venueVector(),as:UTF8.self).replacingOccurrences(of:"\"schema\": 1",with:"\"schema\": 2")
        XCTAssertThrowsError(try VenuePack.decode(Data(text.utf8)))
    }
    func testRestrictionOnAnUnknownPlaceIsRejected() throws {
        let data=try venuePack { payload in
            var entries=payload["entries"] as! [[String:Any]]
            entries[2]["applies_to"]="nowhere"
            payload["entries"]=entries
        }
        XCTAssertThrowsError(try VenuePack.decode(data))
    }
    func testAnswerCitesTheSourceDate() throws {
        let answer=try pack().answer("where is the accessible restroom",at:utc("2026-10-18T09:00:00Z"))
        guard case .found(let entry)=answer else { return XCTFail("expected the restroom") }
        XCTAssertEqual(entry.id,"accessible-restroom")
        XCTAssertEqual(answer.spoken(timeZone:TimeZone(identifier:"UTC")!),"Ground floor, past the elevators on the left. Source checked October 17.")
    }
    func testAliasesMatch() throws {
        guard case .found(let entry)=try pack().answer("Is there a bathroom?",at:utc("2026-10-18T09:00:00Z")) else { return XCTFail() }
        XCTAssertEqual(entry.id,"accessible-restroom")
    }
    func testActiveRestrictionOverridesThePlace() throws {
        let answer=try pack().answer("front door",at:utc("2026-10-18T09:00:00Z"))
        guard case .restricted(let place,let restriction)=answer else { return XCTFail("expected the repair notice") }
        XCTAssertEqual(place.id,"main-entrance")
        XCTAssertEqual(restriction.id,"north-door-repair")
        XCTAssertTrue(answer.spoken(timeZone:TimeZone(identifier:"UTC")!).hasPrefix("The north automatic door is out of service."))
    }
    func testEndedRestrictionNoLongerApplies() throws {
        guard case .found(let entry)=try pack().answer("main entrance",at:utc("2026-10-20T09:00:00Z")) else { return XCTFail() }
        XCTAssertEqual(entry.id,"main-entrance")
    }
    func testExpiredPackNeverAnswers() throws {
        let answer=try pack().answer("restroom",at:utc("2026-10-24T12:00:00Z"))
        XCTAssertEqual(answer,.expired(venueName:"Example Hall",expiresAt:utc("2026-10-24T12:00:00Z")))
        XCTAssertEqual(answer.spoken(timeZone:TimeZone(identifier:"UTC")!),"The downloaded information for Example Hall expired on October 24, so I can't confirm it.")
    }
    func testPlaceOutsideItsWindowIsNotCurrent() throws {
        let data=try venuePack { payload in
            var entries=payload["entries"] as! [[String:Any]]
            entries[1]["effective_until"]="2026-10-18T00:00:00Z"
            payload["entries"]=entries
        }
        let answer=try VenuePack.decode(data).answer("restroom",at:utc("2026-10-18T09:00:00Z"))
        guard case .notCurrent(let entry)=answer else { return XCTFail("expected not current") }
        XCTAssertEqual(entry.id,"accessible-restroom")
    }
    func testUnknownQuestion() throws {
        XCTAssertEqual(try pack().answer("where is the pool",at:utc("2026-10-18T09:00:00Z")),.unknown)
    }
}
