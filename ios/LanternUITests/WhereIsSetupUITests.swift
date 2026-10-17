import XCTest

final class WhereIsSetupUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Scrolls the Assistant panel until `element` can be tapped (the landscape keyboard covers the lower half).
    private func reveal(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<6 where !element.isHittable { app.scrollViews["cameraSettingsScroll"].swipeUp(velocity: .slow) }
        return element
    }

    /// Opens the Assistant panel and expands the collapsed Where-is row.
    private func openWhereIsRow() {
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
        let voice = app.buttons["voiceControl"]
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        voice.tap()
        let status = app.staticTexts["whereIsStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        reveal(status).tap()
        XCTAssertTrue(app.textFields["chalkEnvironment"].waitForExistence(timeout: 5), "Expanding the row shows the optional Chalk fields")
    }

    func testWhereIsSetupValidatesAndSaves() {
        openWhereIsRow()
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is: on-device only")
        XCTAssertEqual(app.textFields["chalkHost"].value as? String, "https://api.chalk.ai")
        XCTAssertEqual(app.textFields["chalkModel"].value as? String, "openai/gpt-6.1-sol")

        reveal(app.buttons["saveChalkSetup"]).tap()
        XCTAssertTrue(app.staticTexts["chalkSetupError"].waitForExistence(timeout: 3), "An empty key must be refused")

        // Done dismisses the keyboard after each entry; otherwise it covers the next field on a landscape phone.
        reveal(app.textFields["chalkEnvironment"]).tap()
        app.typeText("bnsb82aac313\n")
        XCTAssertEqual(app.textFields["chalkEnvironment"].value as? String, "bnsb82aac313")
        reveal(app.descendants(matching: .any)["chalkKey"].firstMatch).tap()
        app.typeText("uitest-key-0123456789\n")
        reveal(app.buttons["saveChalkSetup"]).tap()
        XCTAssertTrue(app.staticTexts["whereIsStatus"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is: Chalk ready")
        XCTAssertFalse(app.staticTexts["chalkSetupError"].exists)

        reveal(app.buttons["forgetChalkSetup"]).tap()
        XCTAssertEqual(app.staticTexts["whereIsStatus"].label, "Where-is: on-device only")
    }
}
