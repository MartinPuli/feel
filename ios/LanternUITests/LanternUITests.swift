import XCTest

final class LanternUITests: XCTestCase {
    private func launch(extraArguments: [String] = [], expandControls: Bool = true, cameraHome: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-directionArrowsEnabled", "YES"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startCamera"].isHittable)
        if !cameraHome {
            app.buttons["cameraMenu"].tap()
            XCTAssertTrue(app.buttons["task_surroundings"].waitForExistence(timeout: 5))
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
        app.buttons["task_surroundings"].tap()
        XCTAssertTrue((app.buttons["sensingStatus"].value as? String ?? "").hasPrefix("STOPPED."))
        app.buttons["sensingStatus"].tap()
        let value = app.otherElements["Virtual puck"].value as? String ?? ""
        XCTAssertTrue(value.contains("No target highlight"))
        for column in 1...6 { XCTAssertTrue(value.contains("Column \(column), band 0")) }
        XCTAssertFalse(value.contains("Column 7"))
        app.buttons["closeCameraPanel"].tap()
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
        XCTAssertFalse(app.buttons["task_find"].exists)
        let save = app.buttons["saveVoiceSetup"]
        // Slow swipes scroll without momentum, so a longer panel cannot carry the button past the viewport.
        for _ in 0..<6 where !save.isHittable { app.scrollViews["cameraSettingsScroll"].swipeUp(velocity: .slow) }
        save.tap()
        XCTAssertTrue(app.staticTexts["voiceSetupError"].exists)
        capture("voice-setup")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.buttons["voiceControl"].value as? String, "Microphone off")
        XCTAssertTrue((app.buttons["sensingStatus"].value as? String ?? "").hasPrefix("STOPPED."))
        capture("voice-camera")
    }

    func testTaskNavigationAndModalIsolation() {
        let app = launch(expandControls: false)
        XCTAssertTrue(app.buttons["startCamera"].isHittable)
        XCTAssertFalse(app.otherElements["Virtual puck"].exists, "Detailed geometry is requested, not forced into the main reading order")
        XCTAssertTrue(app.buttons["sensingStatus"].isHittable)
        capture("feel-surroundings")
        app.buttons["task_find"].tap()
        app.buttons["typeFindRequest"].tap()
        XCTAssertTrue(app.textFields["findQuery"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["findRequestedObject"].isEnabled)
        capture("feel-find")
        app.buttons["task_places"].tap()
        app.buttons["rememberPlaceForm"].tap()
        XCTAssertTrue(app.textFields["placeName"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rememberPlace"].isEnabled)
        capture("feel-places")
        simulate(app)
        for task in ["task_find", "task_places"] {
            app.buttons[task].tap()
            XCTAssertTrue(app.buttons["stopSession"].isHittable)
        }
        app.buttons["cameraSettings"].tap()
        let panel = app.descendants(matching: .any)["cameraFloatingPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task_find"].exists, "Background navigation must be hidden from accessibility while a modal is open")
        capture("feel-settings-modal")
        app.buttons["panelStop"].tap()
        assertStopped(app)
    }

    func testCameraLayoutSimulationAndStop() {
        let app = launch()
        XCTAssertFalse(app.buttons["Simulation"].exists, "Simulation belongs in Settings")
        capture("camera-stopped")
        simulate(app)
        XCTAssertTrue((app.buttons["sensingStatus"].value as? String ?? "").hasPrefix("SIMULATION."))
        XCTAssertFalse(app.buttons["Simulation"].exists)
        app.buttons["sensingStatus"].tap()
        XCTAssertTrue(app.staticTexts["simulationNotice"].label.contains("No simulated movement sent to hardware"))
        let puck = app.otherElements["Virtual puck"]
        XCTAssertTrue(puck.exists)
        let scroll = app.scrollViews["cameraSettingsScroll"]
        let stop = app.buttons["panelStop"]
        XCTAssertLessThanOrEqual(scroll.frame.maxY, stop.frame.minY,
                                 "The fixed Stop control must stay outside the scrolling viewport")
        // Accessibility reports the full rectangle even when its lower rows are clipped.
        // Reveal the entire packet readout before checking its separation from Stop.
        for _ in 0..<6 {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 4)
            let frame = puck.frame
            if viewport.contains(frame) { break }
            let shift = frame.maxY > viewport.maxY ? frame.maxY - viewport.maxY : frame.minY - viewport.minY
            // Tiny residual drags can stay below UIKit's pan-recognition threshold.
            let travel = min(max(abs(shift) + 16, 32), viewport.height * 0.7)
            let startY = shift > 0 ? viewport.maxY - 8 : viewport.minY + 8
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: 8 / scroll.frame.width, dy: (startY - scroll.frame.minY) / scroll.frame.height))
            let end = start.withOffset(CGVector(dx: 0, dy: shift > 0 ? -travel : travel))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(scroll.frame.intersection(app.frame).contains(puck.frame),
                      "All four pin bands must be reachable inside the scrolling viewport")
        XCTAssertFalse(puck.frame.intersects(stop.frame))
        XCTAssertTrue(stop.isHittable)
        capture("camera-simulation")
        app.buttons["panelStop"].tap()
        assertStopped(app)
        for panel in ["cameraSettings", "connectPuck"] {
            app.buttons[panel].tap()
            XCTAssertTrue(app.buttons["closeCameraPanel"].waitForExistence(timeout: 5))
            app.buttons["closeCameraPanel"].tap()
            assertStopped(app)
        }
    }

    func testNormalInterfaceKeepsLiveScanVisibleAndHidesSyntheticTools() {
        let app = launch(extraArguments: ["--hide-diagnostics", "-feelGridWalkDemo", "YES"], cameraHome: true)
        let status = app.buttons["sensingStatus"]
        XCTAssertTrue((status.value as? String ?? "").hasPrefix("STOPPED."))
        XCTAssertLessThanOrEqual(status.frame.width, 260, "The packet preview must leave the camera visible")
        for id in ["startCamera", "talkToFeel", "sensingStatus", "cameraMenu"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable, "Camera controls must be reachable without opening the menu")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        }
        for id in ["task_surroundings", "task_find", "task_places", "cameraSettings", "describeAhead", "homeSpatialMap", "cameraPreview"] {
            XCTAssertFalse(app.buttons[id].exists, "Secondary actions belong behind Menu")
        }
        XCTAssertFalse(app.staticTexts["guidanceTitle"].exists)
        XCTAssertFalse(app.staticTexts["sessionStatus"].exists)
        XCTAssertEqual(status.label, "Camera off, sensing status")
        let value = status.value as? String ?? ""
        XCTAssertFalse(value.contains("Column "), "Home speaks useful state; pin-by-pin diagnostics are available on request")
        capture("camera-first-home")
        status.tap()
        XCTAssertTrue(app.buttons["closeCameraPanel"].waitForExistence(timeout: 5))
        let pins = app.otherElements["Virtual puck"].value as? String ?? ""
        for column in 1...6 { XCTAssertTrue(pins.contains("Column \(column), band 0"), pins) }
        XCTAssertFalse(pins.contains("Column 0,"))
        XCTAssertFalse(pins.contains("Column 7,"))
        XCTAssertFalse(app.buttons["cameraMenu"].exists, "The camera controls must leave the accessibility tree while a modal is open")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout: 5))
        app.buttons["cameraMenu"].tap()
        XCTAssertTrue(app.buttons["task_find"].isHittable)
        XCTAssertTrue(app.buttons["task_places"].isHittable)
        XCTAssertTrue(app.buttons["homeSpatialMap"].isHittable)
        app.buttons["closeCameraMenu"].tap()
        XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task_find"].exists)
        app.buttons["cameraMenu"].tap()
        app.buttons["cameraSettings"].tap()
        XCTAssertTrue(app.buttons["openSpatialMap"].isHittable)
        XCTAssertFalse(app.buttons["Simulation"].exists)
        XCTAssertFalse(app.buttons["gridWalk"].exists)
        app.buttons["openSpatialMap"].tap()
        XCTAssertTrue(app.buttons["startSpatialMap"].isHittable, "The real scan action should be visible without scrolling")
        XCTAssertFalse(app.buttons["simulateSpatialMap"].exists)
        XCTAssertFalse(app.buttons["spatialMapTracking"].exists)
        // The accessibility tree switches before the 160 ms panel fade finishes.
        Thread.sleep(forTimeInterval: 0.3)
        capture("camera-menu-live-scan-entry")
        app.buttons["closeCameraPanel"].tap()
        app.buttons["cameraSettings"].tap()
        app.buttons["advancedTools"].tap()
        XCTAssertFalse(app.buttons["Simulate saved places"].exists)
    }

    func testDirectionArrowPlaysOnSimulatedSign() {
        let app = launch()
        app.buttons["cameraSettings"].tap()
        let disclosure = app.buttons["Tactile guidance"]
        for _ in 0..<5 where !disclosure.isHittable { app.scrollViews["cameraSettingsScroll"].swipeUp(velocity: .slow) }
        disclosure.tap()
        let toggle = app.switches["directionArrowsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["closeCameraPanel"].tap()
        simulate(app)
        let status = app.buttons["sensingStatus"]
        XCTAssertFalse((status.value as? String ?? "").contains("Guiding:"), "No arrow plays without a request")
        let sign = app.buttons["simulateSign"]
        XCTAssertTrue(sign.waitForExistence(timeout: 5))
        // The simulated target is in view except during the 8–10 s tracking-loss window.
        sign.tap()
        let arrow = NSPredicate(format: "value CONTAINS 'Guiding:'")
        expectation(for: arrow, evaluatedWith: status)
        waitForExpectations(timeout: 3)
        capture("direction-arrow-simulation")
        app.buttons["stopSession"].tap()
        assertStopped(app)
    }

    func testLargestTextKeepsStopReachable() {
        let app = launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        simulate(app)
        app.buttons["closeCameraMenu"].tap()
        XCTAssertTrue(app.buttons["stopSession"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stopSession"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["stopSession"].frame.height, 44)
        XCTAssertTrue(app.buttons["talkToFeel"].isHittable)
        XCTAssertTrue(app.buttons["cameraMenu"].isHittable)
        capture("camera-home-accessibility-text")
        app.buttons["cameraMenu"].tap()
        XCTAssertGreaterThanOrEqual(app.scrollViews["cameraReadingScroll"].frame.height, 44)
        for task in ["task_surroundings", "task_find", "task_places"] {
            XCTAssertTrue(app.buttons[task].isHittable)
            app.buttons[task].tap()
            app.scrollViews["cameraReadingScroll"].swipeUp()
            XCTAssertTrue(app.buttons["stopSession"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["stopSession"].frame.height, 44)
        }
        capture("camera-accessibility-text")
        app.buttons["cameraSettings"].tap()
        XCTAssertTrue(app.buttons["panelStop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["panelStop"].isHittable)
        app.buttons["panelStop"].tap()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
    }

    func testStopRemainsAvailableInBothPanels() {
        let app = launch()
        for panel in ["cameraSettings", "connectPuck", "voiceControl"] {
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

    func testResultAlertsKeepStopAvailable() {
        let app = launch()
        for (task, result) in [("task_find", "findResult"), ("task_places", "placeStatus")] {
            simulate(app)
            app.buttons[task].tap()
            let button = app.buttons[result]
            for _ in 0..<4 where !button.isHittable { app.scrollViews["cameraReadingScroll"].swipeUp(velocity: .slow) }
            button.tap()
            let stop = app.alerts.buttons["Stop sensing"]
            XCTAssertTrue(stop.waitForExistence(timeout: 5))
            XCTAssertTrue(stop.isHittable)
            stop.tap()
            assertStopped(app)
        }
    }

    func testDraftsSurvivePanelsAndTaskChanges() {
        let app = launch()
        app.buttons["task_find"].tap()
        app.buttons["typeFindRequest"].tap()
        let query = app.textFields["findQuery"]
        query.tap(); query.typeText("My backpack")
        XCTAssertTrue(app.buttons["startCamera"].isHittable, "Session controls must remain reachable above the keyboard")
        XCTAssertTrue(query.isHittable, "The edited field must remain visible, not just the session controls")
        XCTAssertGreaterThanOrEqual(app.scrollViews["cameraReadingScroll"].frame.height, 48)
        capture("feel-find-keyboard")
        query.typeText("\n")
        app.buttons["cameraSettings"].tap()
        app.buttons["closeCameraPanel"].tap()
        if !query.exists { app.buttons["typeFindRequest"].tap() }
        XCTAssertEqual(query.value as? String, "My backpack")
        app.buttons["task_places"].tap()
        app.buttons["rememberPlaceForm"].tap()
        let name = app.textFields["placeName"]
        name.tap(); name.typeText("Entrance")
        XCTAssertTrue(app.buttons["startCamera"].isHittable)
        XCTAssertTrue(name.isHittable)
        name.typeText("\n")
        app.buttons["voiceControl"].tap()
        app.buttons["closeCameraPanel"].tap()
        if !name.exists { app.buttons["rememberPlaceForm"].tap() }
        XCTAssertEqual(name.value as? String, "Entrance")
        app.buttons["task_find"].tap()
        if !query.exists { app.buttons["typeFindRequest"].tap() }
        XCTAssertEqual(query.value as? String, "My backpack")
        app.buttons["task_places"].tap()
        if !name.exists { app.buttons["rememberPlaceForm"].tap() }
        XCTAssertEqual(name.value as? String, "Entrance")
    }

    func testDiagnosticUsesSixActiveColumnsAndCanStop() {
        let app = launch()
        simulate(app)
        app.buttons["cameraSettings"].tap()
        let gridButton = app.buttons["gridWalk"]
        for _ in 0..<4 where !gridButton.isHittable {
            app.scrollViews["cameraSettingsScroll"].swipeUp(velocity: .slow)
        }
        gridButton.tap()
        let grid = app.otherElements["Pin grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let value = grid.value as? String ?? ""
        for column in 1...6 { XCTAssertTrue(value.contains("Column \(column),"), value) }
        XCTAssertFalse(value.contains("Column 0,"))
        XCTAssertFalse(value.contains("Column 7,"))
        XCTAssertTrue(app.buttons["gridStop"].isHittable)
        app.buttons["gridStop"].tap()
        assertStopped(app)
    }

    func testUnavailableCameraShowsRecovery() {
        let app = launch()
        app.buttons["startCamera"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = system.alerts.buttons["Don't Allow"]
        if deny.waitForExistence(timeout: 3) { deny.tap() }
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        let status = app.buttons["sensingStatus"].value as? String ?? ""
        XCTAssertTrue(status.contains("permission denied") || status.contains("LiDAR"), status)
        XCTAssertTrue((app.buttons["sensingStatus"].value as? String ?? "").hasPrefix("STOPPED."))
        capture("camera-unavailable")
        app.buttons["cameraSettings"].tap()
        app.buttons["openSpatialMap"].tap()
        let scanError = app.staticTexts["spatialMapSessionStatus"].label
        XCTAssertFalse(scanError.isEmpty)
        XCTAssertTrue(status.contains(scanError), "The scan panel must expose the camera failure instead of only saying Map stopped")
    }
}
