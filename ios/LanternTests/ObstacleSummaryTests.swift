import XCTest
@testable import Lantern

final class ObstacleSummaryTests: XCTestCase {
    func testNearestRangePerSideAndHonestEmptySides() {
        XCTAssertEqual(VoicePhrasing.obstacles([1.4, 2.0, 0.8, 0.9, 1.2, nil, nil]), "ahead 0.8 m, left 1.4 m, right nothing within 4 m")
        XCTAssertEqual(VoicePhrasing.obstacles([nil, nil, nil, nil, nil, nil, nil]), "ahead nothing within 4 m, left nothing within 4 m, right nothing within 4 m")
        XCTAssertEqual(VoicePhrasing.obstacles([5, 5, 5, 5, 5, 5, 0.3]), "ahead nothing within 4 m, left nothing within 4 m, right 0.3 m")
        XCTAssertEqual(VoicePhrasing.obstacles([1, 2]), "unknown")
    }
}
