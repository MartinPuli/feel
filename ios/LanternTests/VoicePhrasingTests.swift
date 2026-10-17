import XCTest
import FeelCore
@testable import Lantern

final class VoicePhrasingTests: XCTestCase {
    func testPreservesDoorUncertaintyAndRelativeSide() {
        let target = TargetObservation(bearingDegrees: -25, distance: 1.24, timestamp: 10)
        XCTAssertEqual(VoicePhrasing.observation(target, finder: .door, now: 10.1),
                       "A possible door was 1.2 meters to your left.")
    }
    func testUsesSpokenUnitsAndNeverPromotesExitSignToSafeRoute() {
        let target = TargetObservation(bearingDegrees: 0, distance: 1, timestamp: 10)
        XCTAssertEqual(VoicePhrasing.observation(target, finder: .exit, now: 10), "An exit sign was 1 meter ahead.")
        let right = TargetObservation(bearingDegrees: 30, distance: 2, timestamp: 10)
        XCTAssertEqual(VoicePhrasing.observation(right, finder: .person, now: 10), "A person was 2 meters to your right.")
    }
    func testRejectsStaleInvalidAndUnselectedObservations() {
        let target = TargetObservation(bearingDegrees: 0, distance: 1, timestamp: 10)
        XCTAssertNil(VoicePhrasing.observation(target, finder: .chair, now: 10.6))
        XCTAssertNil(VoicePhrasing.observation(target, finder: .none, now: 10))
        for distance in [Double.nan, .infinity, -1, 5] {
            XCTAssertNil(VoicePhrasing.observation(.init(bearingDegrees: 0, distance: distance, timestamp: 10), finder: .chair, now: 10))
        }
    }
}
