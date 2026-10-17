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
}
