import XCTest

final class WhereIsSetupUITests: XCTestCase {
    /// Opens the Assistant panel and expands the collapsed Where-is row.
    private func openWhereIsRow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
        let voice = app.buttons["voiceControl"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        voice.tap()
        let status = app.staticTexts["whereIsStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        for _ in 0..<6 where !status.isHittable { app.scrollViews["cameraSettingsScroll"].swipeUp(velocity: .slow) }
        status.tap()
        XCTAssertTrue(app.textFields["chalkEnvironment"].waitForExistence(timeout: 5), "Expanding the row shows the optional Chalk fields")
        return app
    }

    func testWhereIsSetupValidatesAndSaves() {
        let app = openWhereIsRow()
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is: on-device only")
        XCTAssertEqual(app.textFields["chalkHost"].value as? String, "https://api.chalk.ai")
        XCTAssertEqual(app.textFields["chalkModel"].value as? String, "openai/gpt-6.1-sol")

        app.buttons["saveChalkSetup"].tap()
        XCTAssertTrue(app.staticTexts["chalkSetupError"].waitForExistence(timeout: 3), "An empty key must be refused")

        app.textFields["chalkEnvironment"].tap()
        app.textFields["chalkEnvironment"].typeText("bnsb82aac313")
        let keyField = app.secureTextFields["chalkKey"]
        keyField.tap()
        if (keyField.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            // Inside the disclosure the first tap can land during layout; retry on the field's centre.
            keyField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = keyField.waitForExistence(timeout: 1)
        }
        keyField.typeText("uitest-key-0123456789")
        app.buttons["saveChalkSetup"].tap()
        XCTAssertTrue(app.staticTexts["whereIsStatus"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is: Chalk ready")
        XCTAssertFalse(app.staticTexts["chalkSetupError"].exists)

        app.buttons["forgetChalkSetup"].tap()
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is: on-device only")
    }
}
