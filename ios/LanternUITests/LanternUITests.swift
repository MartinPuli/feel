import XCTest
import CoreGraphics

final class LanternUITests: XCTestCase {
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting"] + extraArguments
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            if alert.buttons["Don't Allow"].exists { alert.buttons["Don't Allow"].tap(); return true }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["Simulation"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSimulationAndStopAreClearlyLabeled() {
        let app = launch()
        capture("lantern-light-stopped", app: app)
        app.buttons["Simulation"].tap()
        let notice = app.staticTexts["simulationNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("SIMULATION"))
        XCTAssertTrue(notice.label.contains("No simulated movement sent to hardware"))
        XCTAssertFalse(app.buttons["Simulation"].isEnabled, "An active simulation must not restart on a duplicate tap")
        XCTAssertTrue(app.otherElements["Virtual puck"].exists)
        XCTAssertLessThanOrEqual(app.otherElements["Virtual puck"].frame.maxY, app.buttons["stopSession"].frame.minY, "The tactile display must be visible above Stop")
        capture("lantern-light-simulation", app: app)
        app.scrollViews["sessionScroll"].swipeUp()
        XCTAssertTrue(app.buttons["stopSession"].isHittable, "Stop must remain available after scrolling")
        app.buttons["stopSession"].tap()
        app.scrollViews["sessionScroll"].swipeDown()
        XCTAssertTrue(app.staticTexts["STOPPED"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Simulation"].isEnabled)
        let value = app.otherElements["Virtual puck"].value as? String ?? ""
        XCTAssertTrue(value.contains("No target highlight"))
        for column in 1...7 { XCTAssertTrue(value.contains("Column \(column), band 0")) }
    }

    func testLargestTextKeepsStopReachable() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        if !app.buttons["Simulation"].isHittable { app.scrollViews["sessionScroll"].swipeUp() }
        XCTAssertTrue(app.buttons["Simulation"].isHittable)
        XCTAssertGreaterThan(app.scrollViews["sessionScroll"].frame.height, 150, "Large text must retain usable reading space")
        app.buttons["Simulation"].tap()
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        app.scrollViews["sessionScroll"].swipeUp()
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        capture("lantern-accessibility-text", app: app)
        app.buttons["stopSession"].tap()
        XCTAssertTrue(app.buttons["Simulation"].isEnabled)
    }

    func testSimulationControls() {
        let app = launch()
        app.buttons["Simulation"].tap()
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        capture("lantern-simulation-controls", app: app)
    }
    func testRememberMoveRecallAndTrackingLossInMemorySimulation() {
        let app = launch()
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
