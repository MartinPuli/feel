import XCTest

final class WhereIsSetupUITests: XCTestCase {
    private func openAssistantPanel() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
        let voice = app.buttons["voiceControl"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        voice.tap()
        XCTAssertTrue(app.textFields["chalkEnvironment"].waitForExistence(timeout: 5))
        return app
    }

    func testWhereIsSetupValidatesAndSaves() {
        let app = openAssistantPanel()
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is not set up")
        XCTAssertEqual(app.textFields["chalkHost"].value as? String, "https://api.chalk.ai")
        XCTAssertEqual(app.textFields["chalkModel"].value as? String, "openai/gpt-6.1-sol")

        app.buttons["saveChalkSetup"].tap()
        XCTAssertTrue(app.staticTexts["chalkSetupError"].waitForExistence(timeout: 3), "An empty key must be refused")

        app.textFields["chalkEnvironment"].tap()
        app.textFields["chalkEnvironment"].typeText("bnsb82aac313")
        app.secureTextFields["chalkKey"].tap()
        app.secureTextFields["chalkKey"].typeText("uitest-key-0123456789")
        app.buttons["saveChalkSetup"].tap()
        XCTAssertTrue(app.staticTexts["whereIsStatus"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is ready")
        XCTAssertFalse(app.staticTexts["chalkSetupError"].exists)

        app.buttons["forgetChalkSetup"].tap()
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is not set up")
    }
}
