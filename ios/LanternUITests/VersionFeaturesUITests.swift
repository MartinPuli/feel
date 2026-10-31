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
        XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout: 10))
        app.buttons["cameraMenu"].tap()
        XCTAssertTrue(app.buttons["task_surroundings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        return app
    }

    /// Uses the actual main or modal viewport and excludes the keyboard. Bounded, momentum-free
    /// drags avoid overshooting short rows; querying isHittable can throw for clipped elements.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        scrollID: String = "cameraSettingsScroll",
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !element.frame.isEmpty }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [laidOut], timeout: 5), .completed,
                       "\(element.identifier) never got a frame: \(element.label)", file: file, line: line)
        let scroll = app.scrollViews[scrollID]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), file: file, line: line)
        func visibleViewport() -> CGRect {
            var viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                viewport.size.height = max(0, min(viewport.maxY, keyboard.frame.minY) - viewport.minY)
            }
            return viewport
        }
        func inView() -> Bool {
            let frame = element.frame
            return !frame.isEmpty && visibleViewport().contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        let name = element.identifier.isEmpty ? element.label : element.identifier
        for _ in 0..<16 where !inView() {
            let viewport = visibleViewport()
            XCTAssertGreaterThan(viewport.height, 40, "No scrollable viewport for \(name)", file: file, line: line)
            XCTContext.runActivity(named: "reveal \(name): element=\(element.frame) viewport=\(viewport)") { _ in }
            let shift = element.frame.midY - viewport.midY
            let travel = min(abs(shift), (viewport.height - 20) * 0.8)
            let startY = shift > 0 ? viewport.maxY - 10 : viewport.minY + 10
            // Main-scroll bounds include the landscape safe-area margin. Its full-width
            // fields/actions start inside that margin plus 16pt padding, so derive the
            // gutter from the target instead of dragging at the physical screen edge.
            // Modal bounds already exclude that margin. Avoid starting on a text field,
            // which can consume the gesture without scrolling (cloud-consent regression).
            let dragX = scrollID == "cameraReadingScroll"
                ? max(scroll.frame.minX + 8, min(element.frame.minX - 8, scroll.frame.maxX - 8))
                : scroll.frame.minX + 8
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: (dragX - scroll.frame.minX) / scroll.frame.width,
                dy: (startY - scroll.frame.minY) / scroll.frame.height))
            let end = start.withOffset(CGVector(dx: 0, dy: shift > 0 ? -travel : travel))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(inView(), "Could not reach \(element.identifier): \(element.label)", file: file, line: line)
    }

    private func tap(_ label: String, in app: XCUIApplication, scrollID: String = "cameraSettingsScroll") {
        let button = app.buttons[label]
        reveal(button, in: app, scrollID: scrollID)
        button.tap()
    }

    private func openAdvanced(_ app: XCUIApplication) {
        app.buttons["cameraSettings"].tap()
        tap("advancedTools", in: app)
        XCTAssertTrue(app.staticTexts["whereIsStatus"].waitForExistence(timeout: 5))
    }

    private func closePanel(_ app: XCUIApplication) {
        app.buttons["closeCameraPanel"].tap()
        XCTAssertTrue(app.buttons["task_surroundings"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    private func expectLabel(_ element: XCUIElement, contains text: String) {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed)
    }

    private func expectValue(_ element: XCUIElement, contains text: String) {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed)
    }

    private func expectMode(_ mode: String, in app: XCUIApplication) {
        app.buttons["task_surroundings"].tap()
        let status = app.buttons["sensingStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", mode + ". "), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed)
    }

    private func inspectStatus(_ app: XCUIApplication, assertions: () -> Void) {
        app.buttons["task_surroundings"].tap()
        app.buttons["sensingStatus"].tap()
        XCTAssertTrue(app.staticTexts["guidanceTitle"].waitForExistence(timeout: 5))
        assertions()
        closePanel(app)
    }

    /// Called inside the status panel; this remains the production packet's accessible value.
    private func assertNeutral(_ app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["Virtual puck"].waitForExistence(timeout: 5))
        let value = app.otherElements["Virtual puck"].value as? String ?? ""
        XCTAssertTrue(value.contains("No target highlight"), value)
        for column in 1...6 { XCTAssertTrue(value.contains("Column \(column), band 0"), value) }
        XCTAssertFalse(value.contains("Column 7"), value)
    }

    func testMemorySimulationRememberMoveRecallTrackingLossAndStop() {
        let app = launch()
        openAdvanced(app)
        tap("Simulate saved places", in: app)
        tap("Start memory simulation", in: app)
        closePanel(app)
        app.buttons["task_places"].tap()
        let name = app.textFields["placeName"]
        if !name.exists { tap("rememberPlaceForm", in: app, scrollID: "cameraReadingScroll") }
        reveal(name, in: app, scrollID: "cameraReadingScroll"); name.tap(); name.typeText("Entrance\n")
        tap("rememberPlace", in: app, scrollID: "cameraReadingScroll")
        expectValue(app.buttons["placeStatus"], contains: "Remembered Entrance")
        openAdvanced(app)
        tap("Simulate saved places", in: app)
        tap("Move back 1 meter", in: app)
        closePanel(app)
        tap("Recall Entrance", in: app, scrollID: "cameraReadingScroll")
        expectValue(app.buttons["placeStatus"], contains: "Pointing toward")
        capture("memory-recall-controls")
        expectMode("SIMULATION", in: app)
        inspectStatus(app) {
            XCTAssertTrue(app.staticTexts["simulationNotice"].label.contains("No simulated movement sent to hardware"))
            let puck = app.otherElements["Virtual puck"]
            let pointing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'Target column'"), object: puck)
            XCTAssertEqual(XCTWaiter.wait(for: [pointing], timeout: 5), .completed)
            XCTAssertTrue((puck.value as? String ?? "").contains("Column 4, band 2"))
            capture("memory-recall-simulation")
        }

        openAdvanced(app)
        tap("Simulate saved places", in: app)
        tap("Lose tracking", in: app)
        closePanel(app)
        inspectStatus(app) {
            expectLabel(app.staticTexts["guidanceTitle"], contains: "Tracking lost")
            assertNeutral(app)
            capture("memory-simulation-tracking-lost")
        }
        app.buttons["stopSession"].tap()
        XCTAssertTrue(app.buttons["startCamera"].waitForExistence(timeout: 5))
        expectMode("STOPPED", in: app)
        inspectStatus(app) { assertNeutral(app) }
        app.buttons["task_places"].tap()
        XCTAssertFalse(app.buttons["Recall Entrance"].exists, "Stopping ends the synthetic world and its saved places")
    }

    func testTypedLocalMuteChangesSpokenRepliesWithoutMicrophoneSetup() {
        let app = launch()
        app.buttons["voiceControl"].tap()
        let spoken = app.switches["spokenReplies"]
        reveal(spoken, in: app)
        XCTAssertEqual(spoken.value as? String, "1")
        closePanel(app)
        app.buttons["task_find"].tap()
        tap("openLocalCommands", in: app, scrollID: "cameraReadingScroll")
        tap("Commands without internet", in: app)
        let command = app.textFields["localCommandText"]
        reveal(command, in: app); command.tap(); command.typeText("mute\n")
        tap("Run local command", in: app)
        expectLabel(app.staticTexts["localCommandResult"], contains: "Spoken replies muted")
        capture("offline-typed-mute")
        closePanel(app)
        app.buttons["voiceControl"].tap()
        reveal(spoken, in: app)
        XCTAssertEqual(spoken.value as? String, "0", "The command must mutate the actual voice setting")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.buttons["voiceControl"].value as? String, "Microphone off")
        expectMode("STOPPED", in: app)
    }
    /// Requires the simulator test app's fresh consent preferences. This test never
    /// forces a consent value through launch arguments or switches uploads on.
    func testCloudMemoryUploadAndSharingDefaultOff() {
        let app = launch()
        openAdvanced(app)
        tap("Cloud memory", in: app)
        let uploads = app.switches["memoryUploadConsent"]
        reveal(uploads, in: app)
        XCTAssertEqual(uploads.value as? String, "0", "A fresh installation must not upload memories without consent")
        let shared = app.switches["Share future room records"]
        reveal(shared, in: app)
        XCTAssertEqual(shared.value as? String, "0")
        XCTAssertFalse(shared.isEnabled, "Sharing cannot be enabled while uploads are off")
        tap("Check upload status", in: app)
        expectLabel(app.staticTexts["cloudMemoryResult"], contains: "Sent: 0")
        capture("cloud-memory-consent-default-off")
        app.buttons["closeCameraPanel"].tap()
        XCTAssertEqual(app.buttons["voiceControl"].value as? String, "Microphone off")
    }

}
