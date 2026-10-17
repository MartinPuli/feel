import XCTest

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
}
