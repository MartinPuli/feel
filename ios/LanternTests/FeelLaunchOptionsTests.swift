import XCTest
@testable import Lantern

final class FeelLaunchOptionsTests: XCTestCase {
    func testNormalPhoneLaunchNeverExposesExamplesOrRestoresOldDemoPreference() {
        for saved in [false, true] {
            XCTAssertFalse(FeelLaunchOptions.diagnosticsEnabled(arguments: ["FEEL"]))
            XCTAssertFalse(FeelLaunchOptions.opensGridDemo(arguments: ["FEEL"], savedPreference: saved))
        }
    }
    func testDeveloperFixturesRequireExplicitLaunchAndCanBeHiddenInUITests() {
        XCTAssertTrue(FeelLaunchOptions.diagnosticsEnabled(arguments: ["FEEL", "--diagnostics"]))
        XCTAssertTrue(FeelLaunchOptions.opensGridDemo(arguments: ["FEEL", "--uitesting"], savedPreference: true))
        XCTAssertFalse(FeelLaunchOptions.opensGridDemo(arguments: ["FEEL", "--uitesting", "--hide-diagnostics"], savedPreference: true))
        XCTAssertFalse(FeelLaunchOptions.opensGridDemo(arguments: ["FEEL", "--diagnostics"], savedPreference: false))
    }
}
