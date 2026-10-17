import XCTest

final class BeaconUITests: XCTestCase {
    func testSharingCanAlwaysBeStoppedOrRetried() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Start sharing"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Stop"].isEnabled)
        capture("beacon-light", app: app)
        app.buttons["Start sharing"].tap()
        // Capability reporting differs by simulator runtime. Neither branch
        // claims a measured range or a real peer connection.
        if app.staticTexts["Ultra Wideband unavailable on this device"].exists {
            XCTAssertTrue(app.buttons["Start sharing"].isEnabled)
            XCTAssertFalse(app.buttons["Stop"].isEnabled)
        } else {
            XCTAssertFalse(app.buttons["Start sharing"].isEnabled)
            XCTAssertTrue(app.buttons["Stop"].isEnabled)
            app.buttons["Stop"].tap()
            XCTAssertTrue(app.buttons["Start sharing"].isEnabled)
            XCTAssertFalse(app.buttons["Stop"].isEnabled)
            XCTAssertEqual(app.staticTexts["beaconStatus"].label, "Nearby Interaction stopped")
        }
    }

    func testLargeText() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Start sharing"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start sharing"].isHittable)
        capture("beacon-accessibility-text", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
