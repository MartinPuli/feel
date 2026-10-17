import XCTest
import CoreGraphics

final class LanternUITests: XCTestCase {
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 10))
        return app
    }

    private func simulate(_ app: XCUIApplication) {
        app.buttons["cameraSettings"].tap()
        let simulation = app.buttons["Simulation"]
        XCTAssertTrue(simulation.waitForExistence(timeout: 5))
        for _ in 0..<4 where !simulation.isHittable {
            app.scrollViews["cameraSettingsScroll"].swipeUp()
        }
        simulation.tap()
        XCTAssertTrue(app.buttons["stopSession"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertStopped(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sessionMode"].label, "STOPPED")
        let value = app.otherElements["Virtual puck"].value as? String ?? ""
        XCTAssertTrue(value.contains("No target highlight"))
        for column in 1...7 { XCTAssertTrue(value.contains("Column \(column), band 0")) }
    }

    func testCameraLayoutSimulationAndStop() {
        let app = launch()
        XCTAssertFalse(app.buttons["Simulation"].exists, "Simulation belongs in Settings")
        capture("camera-stopped")
        simulate(app)
        XCTAssertEqual(app.staticTexts["sessionMode"].label, "SIMULATION")
        XCTAssertTrue(app.staticTexts["simulationNotice"].label.contains("No simulated movement sent to hardware"))
        XCTAssertFalse(app.buttons["Simulation"].exists)
        let puck = app.otherElements["Virtual puck"]
        XCTAssertTrue(puck.exists)
        XCTAssertFalse(puck.frame.intersects(app.buttons["stopSession"].frame))
        capture("camera-simulation")
        app.buttons["stopSession"].tap()
        assertStopped(app)
        for panel in ["cameraSettings", "connectPuck", "memoryPlaces"] {
            app.buttons[panel].tap()
            XCTAssertTrue(app.buttons["closeCameraPanel"].waitForExistence(timeout: 5))
            app.buttons["closeCameraPanel"].tap()
            assertStopped(app)
        }
    }

    func testLargestTextKeepsStopReachable() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        simulate(app)
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        XCTAssertGreaterThan(app.scrollViews["cameraReadingScroll"].frame.height, 100)
        app.scrollViews["cameraReadingScroll"].swipeUp()
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        capture("camera-accessibility-text")
        app.buttons["cameraSettings"].tap()
        XCTAssertTrue(app.buttons["panelStop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["panelStop"].isHittable)
        app.buttons["panelStop"].tap()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
    }

    func testStopRemainsAvailableInAllPanels() {
        let app = launch()
        for panel in ["cameraSettings", "connectPuck", "memoryPlaces"] {
            simulate(app)
            app.buttons[panel].tap()
            XCTAssertTrue(app.buttons["panelStop"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["panelStop"].isHittable)
            app.buttons["panelStop"].tap()
            assertStopped(app)
        }
    }

    func testBackgroundingDoesNotRestartCamera() {
        let app = launch()
        simulate(app)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertStopped(app)
    }

    func testUnavailableCameraShowsRecovery() {
        let app = launch()
        app.buttons["startCamera"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = system.alerts.buttons["Don't Allow"]
        if deny.waitForExistence(timeout: 3) { deny.tap() }
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        let status = app.staticTexts["sessionStatus"].label
        XCTAssertTrue(status.contains("permission denied") || status.contains("LiDAR"), status)
        XCTAssertEqual(app.staticTexts["sessionMode"].label, "STOPPED")
        capture("camera-unavailable")
    }
    func testRememberMoveRecallAndTrackingLossInMemorySimulation() {
        let app = launch()
        app.buttons["memoryPlaces"].tap()
        XCTAssertTrue(app.buttons["memorySimulation"].waitForExistence(timeout:10))
        app.buttons["memorySimulation"].tap()
        let name=app.textFields["placeName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        // Focusing opens the landscape keyboard and changes the sheet geometry.
        // Verify actual text entry instead of post-focus hit testing its old frame.
        name.tap()
        capture("memory-name-entry")
        name.typeText("Desk\n")
        XCTAssertEqual(name.value as? String, "Desk")
        tapControl(app.buttons["rememberPlace"])
        XCTAssertEqual(app.staticTexts["placesCount"].label,"1 places in this session")
        let back=app.buttons["simBack"]; tapControl(back); tapControl(back)
        tapControl(app.buttons["recallPlace"])
        XCTAssertTrue(app.staticTexts["Place guidance: guiding"].waitForExistence(timeout:3))
        capture("memory-guiding")
        let tracking=app.switches["simTracking"]
        XCTAssertEqual(tracking.value as? String,"1")
        setSwitch(tracking,to:false)
        XCTAssertTrue(app.staticTexts["Place guidance: trackingLost"].waitForExistence(timeout:3))
        let neutral=(1...7).map { "Column \($0), band 0" }.joined(separator:". ") + ". No target highlight"
        XCTAssertEqual(app.otherElements["memoryPuck"].value as? String,neutral)
        setSwitch(tracking,to:true)
        XCTAssertTrue(app.staticTexts["Place guidance: guiding"].waitForExistence(timeout:3))
        XCTAssertTrue((app.otherElements["memoryPuck"].value as? String)?.contains("Target column 4") == true)
        tapControl(app.buttons["simResetSession"])
        XCTAssertEqual(app.staticTexts["placesCount"].label,"0 places in this session")
    }
    func testAdvancedPanelKeepsStopReachableAtLargestText() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["cameraSettings"].tap()
        tapControl(app.buttons["Voice, saved map and feedback"])
        XCTAssertTrue(app.textFields["commandText"].exists)
        XCTAssertTrue(app.buttons["panelStop"].isHittable)
        app.buttons["panelStop"].tap()
        assertStopped(app)
    }
    func testTypedCommandFallbackRemembersWithoutMicrophone() {
        let app=launch()
        tapControl(app.buttons["memoryPlaces"])
        tapControl(app.buttons["memorySimulation"])
        tapControl(app.buttons["closeCameraPanel"])
        tapControl(app.buttons["cameraSettings"])
        tapControl(app.buttons["Voice, saved map and feedback"])
        let command=app.textFields["commandText"]
        enterText("remember Lab",in:command)
        tapControl(app.buttons["runCommand"])
        XCTAssertEqual(app.staticTexts["commandNotice"].label,"Remembered Lab.")
        XCTAssertFalse(app.buttons["Finish speaking"].isEnabled)
        tapControl(app.buttons["closeCameraPanel"])
        XCTAssertEqual(app.staticTexts["sessionMode"].label,"SIMULATION")
        tapControl(app.buttons["memoryPlaces"])
        XCTAssertEqual(app.staticTexts["placesCount"].label,"1 places in this session")
    }
    private func tapControl(_ element:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertTrue(element.waitForExistence(timeout:5),file:file,line:line)
        // XCUI's native tap scrolls this exact control into view. App-wide swipes
        // did not move the landscape SwiftUI scroll container in hosted CI.
        element.tap()
        XCTAssertTrue(element.isHittable,file:file,line:line)
    }
    private func enterText(_ text:String,in element:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertTrue(element.waitForExistence(timeout:5),file:file,line:line)
        // A focused SwiftUI field can report isHittable=false despite a visible
        // caret. Real typing requires focus; verify the resulting field value.
        element.tap(); element.typeText(text + "\n")
        XCTAssertEqual(element.value as? String,text,file:file,line:line)
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
