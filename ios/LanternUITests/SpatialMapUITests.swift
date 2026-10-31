import XCTest

final class SpatialMapUITests: XCTestCase {
    func testMapSimulationTrackingLossAndClearStayExplicit() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout: 10))
        app.buttons["cameraMenu"].tap()
        XCTAssertTrue(app.buttons["cameraSettings"].waitForExistence(timeout: 10))
        app.buttons["cameraSettings"].tap()
        let open = app.buttons["openSpatialMap"]
        let scroll = app.scrollViews["cameraSettingsScroll"]
        for _ in 0..<4 where !open.isHittable { scroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(app.staticTexts["spatialMapStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["spatialMapStatus"].label, "Map stopped")
        let simulate = app.buttons["simulateSpatialMap"]
        for _ in 0..<6 where !simulate.isHittable { scroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(simulate.isHittable); simulate.tap()
        XCTAssertTrue(app.staticTexts["spatialMapNotice"].label.contains("SIMULATION"))
        XCTAssertTrue(app.staticTexts["spatialMapNotice"].label.contains("Camera off"))
        // Static text can report hittable even outside the visible scroll viewport.
        let mapStatus = app.staticTexts["spatialMapStatus"]
        for _ in 0..<6 where !scroll.frame.contains(mapStatus.frame) { scroll.swipeDown(velocity: .slow) }
        XCTAssertTrue(scroll.frame.contains(mapStatus.frame))
        XCTAssertEqual(app.staticTexts["spatialMapStatus"].label, "SIMULATION — synthetic room")
        capture("spatial-map-simulation")
        let tracking = app.buttons["spatialMapTracking"]
        for _ in 0..<6 where !tracking.isHittable { scroll.swipeUp(velocity: .slow) }
        tracking.tap()
        XCTAssertTrue(app.staticTexts["spatialMapStatus"].label.contains("Tracking unavailable"))
        let stop = app.buttons["stopSpatialMap"]
        for _ in 0..<4 where !stop.isHittable { scroll.swipeUp(velocity: .slow) }
        stop.tap()
        XCTAssertEqual(app.staticTexts["spatialMapStatus"].label, "Map stopped")
        XCTAssertTrue(app.staticTexts["spatialMapCounts"].label.contains("0 triangles"))
        app.buttons["closeCameraPanel"].tap()
        XCTAssertTrue(app.buttons["startCamera"].isHittable)
        let sensing = app.buttons["sensingStatus"]
        XCTAssertTrue(sensing.waitForExistence(timeout: 5))
        XCTAssertTrue((sensing.value as? String ?? "").hasPrefix("STOPPED. "))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
