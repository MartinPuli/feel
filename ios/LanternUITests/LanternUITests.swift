import XCTest

final class LanternUITests: XCTestCase {
    private func launch(extraArguments: [String] = [], expandControls: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["controlsToggle"].waitForExistence(timeout: 10))
        if expandControls {
            app.buttons["controlsToggle"].tap()
            XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        }
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

    func testDrawerAndFloatingPanels() {
        let app = launch(expandControls: false)
        XCTAssertFalse(app.buttons["startCamera"].exists)
        XCTAssertFalse(app.otherElements["Virtual puck"].exists)
        capture("drawer-collapsed")
        app.buttons["controlsToggle"].tap()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["Virtual puck"].exists)
        capture("drawer-expanded")
        app.buttons["controlsToggle"].tap()
        XCTAssertFalse(app.buttons["startCamera"].exists)
        simulate(app)
        app.buttons["controlsToggle"].tap()
        XCTAssertFalse(app.otherElements["Virtual puck"].exists)
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        capture("drawer-collapsed-active")
        app.buttons["cameraSettings"].tap()
        let panel = app.descendants(matching: .any)["cameraFloatingPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertLessThan(panel.frame.width, app.frame.width - 100, "The panel must float over the camera in landscape")
        XCTAssertFalse(app.buttons["controlsToggle"].exists, "Background controls must be hidden from accessibility while a modal is open")
        capture("drawer-settings-modal")
        app.buttons["panelStop"].tap()
        assertStopped(app)
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
        for panel in ["cameraSettings", "connectPuck"] {
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

    func testStopRemainsAvailableInBothPanels() {
        let app = launch()
        for panel in ["cameraSettings", "connectPuck"] {
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
}
