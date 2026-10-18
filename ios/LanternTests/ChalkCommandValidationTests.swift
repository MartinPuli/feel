import XCTest
@testable import Lantern

final class ChalkCommandValidationTests: XCTestCase {
    private func request(tracking: Bool = true, restoring: Bool = false,
                         returnPoint: Bool = false, duplicate: Bool = false) -> ChalkRequest {
        ChalkRequest(requestId: "request", sessionId: "session", utterance: "Find entrance", language: "en",
                     context: ChalkContext(places: [ChalkPlace(id: "a", name: "Entrance"),
                                                    ChalkPlace(id: "b", name: duplicate ? "entrance" : "Desk")],
                                           trackingValid: tracking, restoring: restoring, mode: "live",
                                           hasReturnPoint: returnPoint), consent: false)
    }
    private func response(_ action: ChalkDecision.Action, place: String? = nil,
                          name: String? = nil, session: String = "session") -> ChalkResponse {
        ChalkResponse(requestId: "request", sessionId: session,
                      decision: ChalkDecision(action: action, placeId: place, name: name, message: "Selected."),
                      traceId: "trace", latencyMs: 100)
    }
    func testKnownDestinationAcceptedAndUnknownRejected() throws {
        XCTAssertNoThrow(try response(.recall, place: "a").validate(for: request()))
        XCTAssertThrowsError(try response(.recall, place: "invented").validate(for: request()))
    }
    func testOtherSessionAndDuplicateNamesRejected() {
        XCTAssertThrowsError(try response(.recall, place: "a", session: "old").validate(for: request()))
        XCTAssertThrowsError(try response(.recall, place: "a").validate(for: request(duplicate: true)))
    }
    func testTrackingAndRestoringPreventSpatialActions() {
        for context in [request(tracking: false, returnPoint: true), request(restoring: true, returnPoint: true)] {
            XCTAssertThrowsError(try response(.recall, place: "a").validate(for: context))
            XCTAssertThrowsError(try response(.remember, name: "Door").validate(for: context))
            XCTAssertThrowsError(try response(.returnToPoint).validate(for: context))
            XCTAssertNoThrow(try response(.stop).validate(for: context))
            XCTAssertNoThrow(try response(.listPlaces).validate(for: context))
        }
    }
    func testReturnPointMustExist() {
        XCTAssertThrowsError(try response(.returnToPoint).validate(for: request()))
        XCTAssertNoThrow(try response(.returnToPoint).validate(for: request(returnPoint: true)))
    }
    func testRememberHasBoundedNameAndNoPlaceIdentifier() {
        XCTAssertThrowsError(try response(.remember, name: "\nDoor").validate(for: request()))
        XCTAssertThrowsError(try response(.remember, place: "a", name: "Door").validate(for: request()))
        XCTAssertNoThrow(try response(.remember, name: "Door").validate(for: request()))
    }
}
