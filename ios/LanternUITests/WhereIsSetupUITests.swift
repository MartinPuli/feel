import XCTest

final class WhereIsSetupUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Reveals controls in either direction with bounded drags, excluding any keyboard overlap.
    /// Frames avoid Xcode's isHittable exception for a partly clipped control.
    @discardableResult
    private func reveal(_ element: XCUIElement) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !element.frame.isEmpty }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [laidOut], timeout: 5), .completed)
        let scroll = app.scrollViews["cameraSettingsScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        func visibleViewport() -> CGRect {
            var viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 12)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                viewport.size.height = max(0, min(viewport.maxY, keyboard.frame.minY) - viewport.minY)
            }
            return viewport
        }
        func inView() -> Bool {
            visibleViewport().contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
        }
        for _ in 0..<16 where !inView() {
            let viewport = visibleViewport()
            XCTAssertGreaterThan(viewport.height, 40)
            let shift = element.frame.midY - viewport.midY
            let travel = min(abs(shift), (viewport.height - 20) * 0.8)
            let startY = shift > 0 ? viewport.maxY - 10 : viewport.minY + 10
            let start = scroll.coordinate(withNormalizedOffset: CGVector(
                dx: 8 / scroll.frame.width, dy: (startY - scroll.frame.minY) / scroll.frame.height))
            let end = start.withOffset(CGVector(dx: 0, dy: shift > 0 ? -travel : travel))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(inView(), "Could not reveal \(element.identifier): \(element.label)")
        return element
    }

    /// Service credentials belong in Settings → Advanced tools, separate from everyday finding.
    private func openWhereIsRow() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout: 10))
        app.buttons["cameraMenu"].tap()
        let settings = app.buttons["cameraSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        reveal(app.buttons["advancedTools"]).tap()
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
