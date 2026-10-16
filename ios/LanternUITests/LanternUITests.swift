import XCTest
import CoreGraphics

final class LanternUITests:XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    func testSimulationAndStopAreClearlyLabeled() {
        let app=XCUIApplication(); app.launchArguments += ["--uitesting"]
        addUIInterruptionMonitor(withDescription:"System permissions") { alert in
            if alert.buttons["Don't Allow"].exists { alert.buttons["Don't Allow"].tap(); return true }; return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["Simulation"].waitForExistence(timeout:10)); app.buttons["Simulation"].tap()
        XCTAssertTrue(app.staticTexts["SIMULATION: Synthetic inputs. No simulated movement sent to hardware."].waitForExistence(timeout:5))
        XCTAssertTrue(app.otherElements["Virtual puck"].exists)
        app.buttons["Stop"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["STOPPED"].waitForExistence(timeout:5))
    }
    func testRememberMoveRecallAndTrackingLossInMemorySimulation() {
        let app=XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["memorySimulation"].waitForExistence(timeout:10))
        app.buttons["memorySimulation"].tap()
        let name=app.textFields["placeName"]
        tapControl(name); name.typeText("Desk\n")
        tapControl(app.buttons["rememberPlace"])
        XCTAssertEqual(app.staticTexts["placesCount"].label,"1 places in this session")
        let back=app.buttons["simBack"]; tapControl(back); tapControl(back)
        tapControl(app.buttons["recallPlace"])
        XCTAssertTrue(app.staticTexts["Place guidance: guiding"].waitForExistence(timeout:3))
        let tracking=app.switches["simTracking"]
        XCTAssertEqual(tracking.value as? String,"1")
        setSwitch(tracking,to:false)
        XCTAssertTrue(app.staticTexts["Place guidance: trackingLost"].waitForExistence(timeout:3))
        let neutral=(1...7).map { "Column \($0), band 0" }.joined(separator:". ") + ". No target highlight"
        XCTAssertEqual(app.otherElements["Virtual puck"].value as? String,neutral)
        setSwitch(tracking,to:true)
        XCTAssertTrue(app.staticTexts["Place guidance: guiding"].waitForExistence(timeout:3))
        XCTAssertTrue((app.otherElements["Virtual puck"].value as? String)?.contains("Target column 4") == true)
        tapControl(app.buttons["simResetSession"])
        XCTAssertEqual(app.staticTexts["placesCount"].label,"0 places in this session")
    }
    private func tapControl(_ element:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertTrue(element.waitForExistence(timeout:5),file:file,line:line)
        // XCUI's native tap scrolls this exact control into view. App-wide swipes
        // did not move the landscape SwiftUI scroll container in hosted CI.
        element.tap()
        XCTAssertTrue(element.isHittable,file:file,line:line)
    }
    private func setSwitch(_ element:XCUIElement,to enabled:Bool,file:StaticString=#filePath,line:UInt=#line) {
        let expected=enabled ? "1" : "0"
        XCTAssertTrue(element.waitForExistence(timeout:5),file:file,line:line)
        if element.value as? String != expected {
            // Native tap first reveals an offscreen switch. SwiftUI may expose
            // the entire labeled row as the switch, whose centre is not the thumb.
            element.tap()
            XCTAssertTrue(element.isHittable,file:file,line:line)
            if element.value as? String != expected {
                element.coordinate(withNormalizedOffset:CGVector(dx:1,dy:0.5))
                    .withOffset(CGVector(dx:-20,dy:0)).tap()
            }
        }
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",expected),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:3),.completed,file:file,line:line)
        XCTAssertEqual(element.value as? String,expected,file:file,line:line)
    }

}
