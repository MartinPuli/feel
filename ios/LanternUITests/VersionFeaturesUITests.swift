import XCTest

/// Real simulator UI interactions with the explicitly synthetic memory scene.
/// These checks never request a camera, microphone, cloud response or BLE connection.
final class VersionFeaturesUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "-directionArrowsEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["controlsToggle"].waitForExistence(timeout: 10))
        app.buttons["controlsToggle"].tap()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        app.buttons["voiceControl"].tap()
        XCTAssertTrue(app.scrollViews["cameraSettingsScroll"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let scroll = app.scrollViews["cameraSettingsScroll"]
        for _ in 0..<18 where !element.isHittable {
            if !element.frame.isEmpty && element.frame.maxY <= scroll.frame.minY + 15 {
                scroll.swipeDown(velocity: .slow)
            } else {
                scroll.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(element.isHittable, "Could not reach \(element.identifier): \(element.label)", file: file, line: line)
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        reveal(button, in: app)
        button.tap()
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    private func expectLabel(_ element: XCUIElement, contains text: String) {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed)
    }

    private func assertNeutral(_ app: XCUIApplication) {
        let value = app.otherElements["Virtual puck"].value as? String ?? ""
        XCTAssertTrue(value.contains("No target highlight"), value)
        for column in 1...6 { XCTAssertTrue(value.contains("Column \(column), band 0"), value) }
        XCTAssertFalse(value.contains("Column 7"), value)
    }

    func testMemorySimulationRememberMoveRecallTrackingLossAndStop() {
        let app = launch()
        tap("Simulate saved places", in: app)
        tap("Start memory simulation", in: app)
        tap("Saved places", in: app)
        let name = app.textFields["placeName"]
        reveal(name, in: app); name.tap(); name.typeText("Entrance\n")
        tap("rememberPlace", in: app)
        expectLabel(app.staticTexts["placeStatus"], contains: "Remembered Entrance")
        tap("Move back 1 meter", in: app)
        tap("Recall Entrance", in: app)
        expectLabel(app.staticTexts["placeStatus"], contains: "Pointing toward")
        capture("memory-recall-controls")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.staticTexts["sessionMode"].label, "SIMULATION")
        XCTAssertTrue(app.staticTexts["simulationNotice"].label.contains("No simulated movement sent to hardware"))
        let puck = app.otherElements["Virtual puck"]
        let pointing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'Target column'"), object: puck)
        XCTAssertEqual(XCTWaiter.wait(for: [pointing], timeout: 5), .completed)
        XCTAssertTrue((puck.value as? String ?? "").contains("Column 4, band 2"))
        capture("memory-recall-simulation")

        app.buttons["voiceControl"].tap()
        tap("Simulate saved places", in: app)
        tap("Lose tracking", in: app)
        app.buttons["closeCameraPanel"].tap()
        expectLabel(app.staticTexts["guidanceTitle"], contains: "Tracking lost")
        assertNeutral(app)
        capture("memory-simulation-tracking-lost")
        app.buttons["stopSession"].tap()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sessionMode"].label, "STOPPED")
        assertNeutral(app)
        app.buttons["voiceControl"].tap()
        tap("Saved places", in: app)
        XCTAssertFalse(app.buttons["Recall Entrance"].exists, "Stopping ends the synthetic world and its saved places")
    }

    func testTypedLocalMuteChangesSpokenRepliesWithoutMicrophoneSetup() {
        let app = launch()
        let spoken = app.switches["spokenReplies"]
        reveal(spoken, in: app)
        XCTAssertEqual(spoken.value as? String, "1")
        tap("Commands without internet", in: app)
        let command = app.textFields["localCommandText"]
        reveal(command, in: app); command.tap(); command.typeText("mute\n")
        tap("Run local command", in: app)
        expectLabel(app.staticTexts["localCommandResult"], contains: "Spoken replies muted")
        capture("offline-typed-mute")
        reveal(spoken, in: app)
        XCTAssertEqual(spoken.value as? String, "0", "The command must mutate the actual voice setting")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.buttons["voiceControl"].value as? String, "Microphone off")
        XCTAssertEqual(app.staticTexts["sessionMode"].label, "STOPPED")
    }
}
