import XCTest

final class LanternUITests: XCTestCase {
    private func launch(extraArguments: [String] = [], expandControls: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-directionArrowsEnabled", "YES"] + extraArguments
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
        for column in 1...6 { XCTAssertTrue(value.contains("Column \(column), band 0")) }
        XCTAssertFalse(value.contains("Column 7"))
    }

    func testVoiceSetupKeepsCameraAndMicrophoneUnderUserControl() {
        let app = launch(expandControls: false)
        let voice = app.buttons["voiceControl"]
        XCTAssertTrue(voice.exists)
        XCTAssertTrue(voice.isHittable)
        XCTAssertLessThan(voice.frame.maxY, app.frame.midY, "Assistant belongs in the header, outside the central camera area")
        XCTAssertFalse(voice.frame.intersects(app.buttons["cameraSettings"].frame))
        XCTAssertEqual(voice.value as? String, "Microphone off")
        voice.tap()
        XCTAssertTrue(app.textFields["voiceEndpoint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["controlsToggle"].exists)
        let save = app.buttons["saveVoiceSetup"]
        // Slow swipes scroll without momentum, so a longer panel cannot carry the button past the viewport.
        for _ in 0..<6 where !save.isHittable { app.scrollViews["cameraSettingsScroll"].swipeUp(velocity: .slow) }
        save.tap()
        XCTAssertTrue(app.staticTexts["voiceSetupError"].exists)
        capture("voice-setup")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.buttons["voiceControl"].value as? String, "Microphone off")
        XCTAssertFalse(app.staticTexts["sessionMode"].exists)
        capture("voice-camera")
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

    func testDirectionArrowPlaysOnSimulatedSign() {
        let app = launch()
        app.buttons["cameraSettings"].tap()
        let toggle = app.switches["directionArrowsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["closeCameraPanel"].tap()
        simulate(app)
        let title = app.staticTexts["guidanceTitle"]
        XCTAssertEqual(title.label, "SIMULATION", "no arrow plays without a request")
        let sign = app.buttons["simulateSign"]
        XCTAssertTrue(sign.waitForExistence(timeout: 5))
        // The simulated target is in view except during the 8–10 s tracking-loss window.
        sign.tap()
        let arrow = NSPredicate(format: "label BEGINSWITH 'SIMULATION · '")
        expectation(for: arrow, evaluatedWith: title)
        waitForExpectations(timeout: 3)
        capture("direction-arrow-simulation")
        app.buttons["stopSession"].tap()
        assertStopped(app)
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
