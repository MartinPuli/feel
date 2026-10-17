import XCTest
import CoreGraphics

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
        for column in 1...7 { XCTAssertTrue(value.contains("Column \(column), band 0")) }
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
        XCTAssertTrue(app.staticTexts["feelWordmark"].exists)
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
        for panel in ["cameraSettings", "connectPuck", "memoryPlaces"] {
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
        let panel = app.descendants(matching: .any)["cameraFloatingPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertLessThan(panel.frame.width, app.frame.width - 100)
        XCTAssertFalse(app.buttons["controlsToggle"].exists)
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
        simulate(app)
        app.buttons["cameraSettings"].tap()
        tapControl(app.buttons["Voice, saved map and feedback"])
        XCTAssertTrue(app.textFields["commandText"].exists)
        capture("advanced-largest-text")
        XCTAssertTrue(app.buttons["panelStop"].isHittable)
        app.buttons["panelStop"].tap()
        assertStopped(app)
    }
    func testTypedCommandFallbackRemembersWithoutMicrophone() {
        let app=launch()
        app.buttons["memoryPlaces"].tap()
        XCTAssertTrue(app.buttons["memorySimulation"].waitForExistence(timeout: 5))
        app.buttons["memorySimulation"].tap()
        app.buttons["closeCameraPanel"].tap()
        app.buttons["cameraSettings"].tap()
        tapControl(app.buttons["Voice, saved map and feedback"])
        let command=app.textFields["commandText"]
        // Native element targeting scrolls the field into view before focusing it.
        // Fixed swipes can overshoot in the short landscape scroll container.
        command.tap()
        let scroll = app.scrollViews["cameraSettingsScroll"]
        capture("advanced-field-position")
        print("Command frame: \(command.frame); scroll: \(scroll.frame); Stop: \(app.buttons["panelStop"].frame)")
        XCTAssertTrue(command.isHittable)
        XCTAssertLessThan(command.frame.maxY, app.buttons["panelStop"].frame.minY)
        capture("advanced-before-entry")
        enterText("remember Lab",in:command)
        tapControl(app.buttons["runCommand"])
        XCTAssertEqual(app.staticTexts["commandNotice"].label,"Remembered Lab.")
        capture("advanced-typed-command")
        XCTAssertFalse(app.buttons["Finish speaking"].isEnabled)
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.staticTexts["sessionMode"].label,"SIMULATION")
        app.buttons["memoryPlaces"].tap()
        XCTAssertEqual(app.staticTexts["placesCount"].label,"1 places in this session")
    }
    func testChalkSharingDefaultsOffAndStopStaysReachable() {
        let app=launch()
        simulate(app)
        app.buttons["cameraSettings"].tap()
        app.buttons["Voice, saved map and feedback"].tap()
        let chalk=app.buttons["Chalk understanding"]
        XCTAssertTrue(chalk.waitForExistence(timeout:5))
        // Reveal the disclosure inside this modal before tapping. Native automatic
        // scrolling can treat its Cancel speech control as an alert interruption.
        let scroll=app.scrollViews["cameraSettingsScroll"]
        for _ in 0..<24 {
            let viewport=scroll.frame
            if chalk.frame.minY >= viewport.minY && chalk.frame.maxY <= viewport.maxY { break }
            let upward=chalk.frame.midY > viewport.midY
            scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:upward ? 0.65 : 0.35))
                .press(forDuration:0.1,thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:upward ? 0.35 : 0.65)),withVelocity:.slow,thenHoldForDuration:0.1)
        }
        XCTAssertGreaterThanOrEqual(chalk.frame.minY,scroll.frame.minY)
        XCTAssertLessThanOrEqual(chalk.frame.maxY,scroll.frame.maxY)
        chalk.tap()
        XCTAssertTrue(chalk.isHittable)
        XCTAssertLessThan(chalk.frame.maxY,app.buttons["panelStop"].frame.minY)
        XCTAssertEqual(app.switches["cloudEnabled"].value as? String,"0")
        XCTAssertEqual(app.switches["cloudSharing"].value as? String,"0")
        XCTAssertEqual(app.switches["cloudRetention"].value as? String,"0")
        XCTAssertTrue(app.buttons["panelStop"].isHittable)
        capture("chalk-consent-defaults")
        app.buttons["panelStop"].tap()
        XCTAssertTrue(app.buttons["controlsToggle"].waitForExistence(timeout:5))
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
