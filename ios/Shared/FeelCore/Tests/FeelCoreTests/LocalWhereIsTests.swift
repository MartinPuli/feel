import XCTest
@testable import FeelCore

/// The on-device fallback only knows a fixed vocabulary; the user's words must map onto it predictably.
final class LocalWhereIsTests: XCTestCase {
    private let table=LocalQuery.object(labels:["diningtable","table","desk"],spoken:"table")

    func testEverydayThingsMapToAQueryTheDetectorCanRun() {
        XCTAssertEqual(LocalVocabulary.query(for:"exit"), .exitSign)
        XCTAssertEqual(LocalVocabulary.query(for:"the Exit sign"), .exitSign)
        XCTAssertEqual(LocalVocabulary.query(for:"way out"), .exitSign)
        XCTAssertEqual(LocalVocabulary.query(for:"door"), .doorCandidate)
        XCTAssertEqual(LocalVocabulary.query(for:"a doorway"), .doorCandidate)
        XCTAssertEqual(LocalVocabulary.query(for:"my friend"), .person)
        XCTAssertEqual(LocalVocabulary.query(for:"people"), .person)
        XCTAssertEqual(LocalVocabulary.query(for:"chairs"), .object(labels:["chair"],spoken:"chair"))
        XCTAssertEqual(LocalVocabulary.query(for:"my laptop"), .object(labels:["laptop"],spoken:"laptop"))
        XCTAssertEqual(LocalVocabulary.query(for:"water bottle"), .object(labels:["bottle"],spoken:"bottle"))
        XCTAssertEqual(LocalVocabulary.query(for:"sofa"), .object(labels:["couch","sofa"],spoken:"couch"))
        XCTAssertEqual(LocalVocabulary.query(for:"desk"), table)
        XCTAssertEqual(LocalVocabulary.query(for:"phone"), .object(labels:["cellphone","phone","mobilephone"],spoken:"phone"))
    }
    func testUnknownThingsHaveNoLocalQuery() {
        XCTAssertNil(LocalVocabulary.query(for:"unicorn"))
        XCTAssertNil(LocalVocabulary.query(for:"3D puck model"))
        XCTAssertNil(LocalVocabulary.query(for:"   "))
    }
    func testLastWordFallsBackToAKnownThing() {
        XCTAssertEqual(LocalVocabulary.query(for:"registration desk"), table)
        XCTAssertEqual(LocalVocabulary.query(for:"fire exit"), .exitSign)
        XCTAssertEqual(LocalVocabulary.query(for:"front door"), .doorCandidate)
    }
    func testModelLabelsMatchAcrossNamingStyles() {
        XCTAssertEqual(LocalVocabulary.normalized("Dining Table"), "diningtable")
        XCTAssertEqual(LocalVocabulary.normalized("cell phone"), "cellphone")
        XCTAssertTrue(LocalVocabulary.matches(label:"diningtable",query:table))
        XCTAssertTrue(LocalVocabulary.matches(label:"Desk",query:table))
        XCTAssertFalse(LocalVocabulary.matches(label:"chair",query:table))
        XCTAssertFalse(LocalVocabulary.matches(label:"chair",query: .exitSign))
    }
    func testVisionBoxConvertsToTopLeftOrigin() {
        // Vision boxes are normalized with a bottom-left origin; this one sits in the lower part of the image.
        let box=NormalizedBox(bottomLeftX:0.2,y:0.1,width:0.3,height:0.3)
        XCTAssertEqual(box.xMin,0.2,accuracy:1e-9); XCTAssertEqual(box.xMax,0.5,accuracy:1e-9)
        XCTAssertEqual(box.yMin,0.6,accuracy:1e-9); XCTAssertEqual(box.yMax,0.9,accuracy:1e-9)
        XCTAssertEqual(box.center.y,0.75,accuracy:1e-9)
        let clamped=NormalizedBox(bottomLeftX:-0.1,y:0.9,width:0.5,height:0.5)
        XCTAssertEqual(clamped.xMin,0,accuracy:1e-9); XCTAssertEqual(clamped.xMax,0.4,accuracy:1e-9)
        XCTAssertEqual(clamped.yMin,0,accuracy:1e-9); XCTAssertEqual(clamped.yMax,0.1,accuracy:1e-9)
    }
}
