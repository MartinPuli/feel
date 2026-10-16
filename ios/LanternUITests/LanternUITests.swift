import XCTest

final class LanternUITests:XCTestCase {
    func testSimulationAndStopAreClearlyLabeled() {
        let app=XCUIApplication(); app.launchArguments += ["--uitesting"]
        addUIInterruptionMonitor(withDescription:"System permissions") { alert in
            if alert.buttons["Don't Allow"].exists { alert.buttons["Don't Allow"].tap(); return true }; return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["Simulation"].waitForExistence(timeout:10)); app.buttons["Simulation"].tap()
        XCTAssertTrue(app.staticTexts["SIMULATION: Synthetic inputs. No simulated movement sent to hardware."].waitForExistence(timeout:5))
        XCTAssertTrue(app.otherElements["Virtual puck"].exists)
        app.buttons["Stop"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["STOPPED"].waitForExistence(timeout:5))
    }
    func testRememberMoveRecallAndTrackingLossInMemorySimulation() {
        let app=XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["memorySimulation"].waitForExistence(timeout:10))
        app.buttons["memorySimulation"].tap()
        let name=app.textFields["placeName"]
        reveal(name,in:app); name.tap(); name.typeText("Desk\n")
        reveal(app.buttons["rememberPlace"],in:app); app.buttons["rememberPlace"].tap()
        XCTAssertEqual(app.staticTexts["placesCount"].label,"1 places in this session")
        let back=app.buttons["simBack"]; reveal(back,in:app); back.tap(); back.tap()
        let recall=app.buttons["recallPlace"]; reveal(recall,in:app,up:false); recall.tap()
        XCTAssertTrue(app.staticTexts["Place guidance: guiding"].waitForExistence(timeout:3))
        let tracking=app.switches["simTracking"]; reveal(tracking,in:app); tracking.tap()
        XCTAssertTrue(app.staticTexts["Place guidance: trackingLost"].waitForExistence(timeout:3))
        tracking.tap()
        XCTAssertTrue(app.staticTexts["Place guidance: guiding"].waitForExistence(timeout:3))
        let reset=app.buttons["simResetSession"]; reveal(reset,in:app); reset.tap()
        XCTAssertEqual(app.staticTexts["placesCount"].label,"0 places in this session")
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication,up:Bool=true) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

}
