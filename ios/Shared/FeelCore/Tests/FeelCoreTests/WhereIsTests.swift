import XCTest
@testable import FeelCore

final class WhereIsTests: XCTestCase {
    private var protocolDir: URL {
        var url=URL(fileURLWithPath:#filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("protocol")
    }
    func testPromptMatchesSharedFile() throws {
        let text=try String(contentsOf:protocolDir.appendingPathComponent("where-is-prompt.txt"),encoding:.utf8)
        XCTAssertEqual(WhereIs.prompt,text.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    func testDeadlineMatchesSharedFile() throws {
        let data=try Data(contentsOf:protocolDir.appendingPathComponent("where-is-cases.json"))
        let shared=try XCTUnwrap((JSONSerialization.jsonObject(with:data) as? [String:Any])?["deadline_seconds"] as? Double)
        XCTAssertEqual(WhereIs.deadline,shared)
    }
    func testSharedParserCases() throws {
        let data=try Data(contentsOf:protocolDir.appendingPathComponent("where-is-cases.json"))
        let cases=try XCTUnwrap((JSONSerialization.jsonObject(with:data) as? [String:Any])?["cases"] as? [[String:Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let name=item["name"] as? String ?? "?", text=try XCTUnwrap(item["text"] as? String)
            if item["error"] as? Bool == true { XCTAssertThrowsError(try WhereIs.parse(text),name); continue }
            let answer=try WhereIs.parse(text), expect=try XCTUnwrap(item["expect"] as? [String:Any])
            XCTAssertEqual(answer.found,expect["found"] as? Bool,name)
            XCTAssertEqual(answer.label,expect["label"] as? String,name)
            if let box=expect["box"] as? [Double] {
                XCTAssertEqual(answer.box,NormalizedBox(xMin:box[0],yMin:box[1],xMax:box[2],yMax:box[3]),name)
            } else { XCTAssertNil(answer.box,name) }
            XCTAssertEqual(answer.confidence,try XCTUnwrap((expect["confidence"] as? NSNumber)?.doubleValue),accuracy:1e-9,name)
        }
    }
    func testRequestBodyCarriesPromptQuestionAndImage() throws {
        let body=try WhereIs.requestBody(model:"anthropic/example",question:"Where is the desk?",jpegBase64:"QUJD")
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:body) as? [String:Any])
        XCTAssertEqual(json["model"] as? String,"anthropic/example")
        let messages=try XCTUnwrap(json["messages"] as? [[String:Any]])
        XCTAssertEqual(messages[0]["content"] as? String,WhereIs.prompt)
        let parts=try XCTUnwrap(messages[1]["content"] as? [[String:Any]])
        XCTAssertEqual(parts[0]["text"] as? String,"Where is the desk?")
        XCTAssertEqual((parts[1]["image_url"] as? [String:Any])?["url"] as? String,"data:image/jpeg;base64,QUJD")
    }
}
