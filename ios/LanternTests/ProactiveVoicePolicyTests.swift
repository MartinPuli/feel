import XCTest
import FeelCore
@testable import Lantern

final class ProactiveVoicePolicyTests: XCTestCase {
    private let empty = [Double?](repeating: nil, count: 7)

    func testObstaclesAreSilentByDefault() {
        var policy = ProactiveVoicePolicy()
        let wall: [Double?] = [3, 3, 0.4, 0.4, 0.4, 3, 3]
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: wall, now: 0))
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: wall, now: 1))
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: wall, now: 2))
    }

    func testObstacleNoticeNamesTheSideWithMoreRoom() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        let wall: [Double?] = [nil, 3, 3, 0.8, 0.8, 3, 0.8]
        var finder = OpenSideFinder()
        let open = finder.update(distances: wall, now: 0)
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: wall, openSide: open, now: 0))
        let notice = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: wall, openSide: open, now: 0.8))
        XCTAssertEqual(notice.text, "An obstacle was about 0.8 meters ahead. More room to your left.")
        XCTAssertTrue(notice.isSupported(target: nil, finder: .none, distances: wall, now: 0.9))
        var open2 = OpenSideFinder()
        XCTAssertNil(open2.update(distances: [0.8, 0.8, 3, 3, 3, 3, 3], now: 0), "an obstacle to the side with an open way ahead adds nothing")
    }

    func testTargetRequiresStabilityAndUnchangedObservationStaysSilent() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        XCTAssertNil(policy.propose(target: target(at: 0), finder: .door, distances: empty, now: 0))
        XCTAssertNil(policy.propose(target: target(at: 0.7), finder: .door, distances: empty, now: 0.7))
        let notice = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .door, distances: empty, now: 0.8))
        XCTAssertEqual(notice.kind, .target)
        XCTAssertEqual(notice.text, "A possible door was 2 meters ahead.")
        XCTAssertTrue(notice.sceneBound)
        policy.acknowledge(notice, now: 0.8)
        XCTAssertNil(policy.propose(target: target(at: 20), finder: .door, distances: empty, now: 20))
        XCTAssertNil(policy.propose(target: target(at: 21), finder: .door, distances: empty, now: 21))
    }

    func testTargetMaterialMovementRequiresStabilityAndEightSecondGap() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(at: 0), finder: .person, distances: empty, now: 0)
        let first = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: empty, now: 0.8))
        policy.acknowledge(first, now: 0.8)
        XCTAssertNil(policy.propose(target: target(distance: 1.5, at: 1), finder: .person, distances: empty, now: 1))
        XCTAssertNil(policy.propose(target: target(distance: 1.5, at: 8.7), finder: .person, distances: empty, now: 8.7))
        let closer = try XCTUnwrap(policy.propose(target: target(distance: 1.5, at: 8.8), finder: .person, distances: empty, now: 8.8))
        XCTAssertNotEqual(closer.key, first.key)
        policy.acknowledge(closer, now: 8.8)
        XCTAssertNil(policy.propose(target: target(distance: 1.99, at: 17), finder: .person, distances: empty, now: 17))
        XCTAssertNil(policy.propose(target: target(distance: 2, at: 18), finder: .person, distances: empty, now: 18))
        XCTAssertNotNil(policy.propose(target: target(distance: 2, at: 18.8), finder: .person, distances: empty, now: 18.8))
    }

    func testSideJitterRestartsStabilityAndStaleTargetCannotTrigger() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(bearing: 16, at: 0), finder: .chair, distances: empty, now: 0)
        XCTAssertNil(policy.propose(target: target(bearing: 15, at: 0.5), finder: .chair, distances: empty, now: 0.5))
        XCTAssertNil(policy.propose(target: target(bearing: 16, at: 0.8), finder: .chair, distances: empty, now: 0.8))
        XCTAssertNil(policy.propose(target: target(bearing: 16, at: 1.5), finder: .chair, distances: empty, now: 1.5))
        let notice = try XCTUnwrap(policy.propose(target: target(bearing: 16, at: 1.6), finder: .chair, distances: empty, now: 1.6))
        XCTAssertEqual(notice.side, .right)
        policy.acknowledge(notice, now: 1.6)
        XCTAssertNil(policy.propose(target: target(bearing: -25, at: 1.6), finder: .chair, distances: empty, now: 10))
        XCTAssertNil(policy.propose(target: target(bearing: -25, at: 10), finder: .none, distances: empty, now: 10))
    }

    func testCloseObstacleHasPriorityThenTargetMayFollowAfterGap() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        let close = sectors(0.7, column: 1)
        _ = policy.propose(target: target(at: 0), finder: .person, distances: close, now: 0)
        let obstacle = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: close, now: 0.8))
        XCTAssertEqual(obstacle.kind, .obstacle)
        XCTAssertEqual(obstacle.text, "An obstacle was about 0.7 meters to your left.")
        policy.acknowledge(obstacle, now: 0.8)
        XCTAssertNil(policy.propose(target: target(at: 8.79), finder: .person, distances: close, now: 8.79))
        let person = try XCTUnwrap(policy.propose(target: target(at: 8.8), finder: .person, distances: close, now: 8.8))
        XCTAssertEqual(person.kind, .target)
    }

    func testObstacleApproachAndSideChangeAreMaterialButRecessionIsSilent() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: nil, finder: .none, distances: sectors(0.9), now: 0)
        let first = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.9), now: 0.8))
        policy.acknowledge(first, now: 0.8)
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.51), now: 9))
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.5), now: 10))
        let closer = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.5), now: 10.8))
        XCTAssertEqual(closer.side, .ahead)
        policy.acknowledge(closer, now: 10.8)
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.9), now: 20))
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.9, column: 6), now: 21))
        XCTAssertNotNil(policy.propose(target: nil, finder: .none, distances: sectors(0.9, column: 6), now: 21.8))
    }

    func testFarInvalidAndMalformedObstacleDataNeverProducesNotice() {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        for now in [0.0, 1, 10] {
            XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.91), now: now))
        }
        for distances in [[nil, Double.nan, .infinity, -1, 0, 1.61, nil], [Double?](repeating: 0.5, count: 6)] {
            XCTAssertNil(policy.propose(target: nil, finder: .none, distances: distances, now: 11))
            XCTAssertNil(policy.propose(target: nil, finder: .none, distances: distances, now: 12))
        }
    }

    func testSubThirtyCentimeterObstacleRemainsSupportedAndHasPriority() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(at: 0), finder: .person, distances: sectors(0.3), now: 0)
        let first = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: sectors(0.3), now: 0.8))
        XCTAssertEqual(first.kind, .obstacle)
        XCTAssertTrue(first.isSupported(target: nil, finder: .none, distances: sectors(0.29), now: 1))
        XCTAssertTrue(first.isSupported(target: nil, finder: .none, distances: sectors(0.1), now: 1))
        // Without delivery acknowledgement, the increasingly close observation remains first.
        for (time, distance) in [(1.0, 0.29), (1.1, 0.1), (1.2, 0.01)] {
            let notice = try XCTUnwrap(policy.propose(target: target(at: time), finder: .person, distances: sectors(distance), now: time))
            XCTAssertEqual(notice.kind, .obstacle)
            XCTAssertEqual(notice.text, "An obstacle was less than 0.3 meters ahead.")
            XCTAssertEqual(notice.key, first.key)
        }
        XCTAssertFalse(first.isSupported(target: nil, finder: .none, distances: sectors(0), now: 2))
        XCTAssertFalse(first.isSupported(target: nil, finder: .none, distances: sectors(-0.1), now: 2))
    }

    func testUnacknowledgedNoticeRetriesWithoutStartingCooldown() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0)
        let first = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0.8))
        let retry = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0.9))
        XCTAssertEqual(first, retry)
        policy.acknowledge(retry, now: 0.9)
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 20))
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 21))
    }

    func testObstacleEpisodeRequiresTwoSecondsOfAbsence() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0)
        let first = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0.8))
        policy.acknowledge(first, now: 0.8)
        _ = policy.propose(target: nil, finder: .none, distances: empty, now: 9)
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 10.9))
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 12))
        _ = policy.propose(target: nil, finder: .none, distances: empty, now: 20)
        XCTAssertNil(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 22))
        let returned = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 22.8))
        XCTAssertNotEqual(first.key, returned.key)
    }

    func testTargetAbsenceAndFinderChangePermitNewDetection() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(at: 0), finder: .person, distances: empty, now: 0)
        let first = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: empty, now: 0.8))
        policy.acknowledge(first, now: 0.8)
        _ = policy.propose(target: nil, finder: .person, distances: empty, now: 9)
        XCTAssertNil(policy.propose(target: target(at: 9.5), finder: .person, distances: empty, now: 9.5))
        _ = policy.propose(target: nil, finder: .person, distances: empty, now: 10)
        XCTAssertNil(policy.propose(target: target(at: 10.6), finder: .person, distances: empty, now: 10.6))
        let returned = try XCTUnwrap(policy.propose(target: target(at: 11.4), finder: .person, distances: empty, now: 11.4))
        policy.acknowledge(returned, now: 11.4)
        XCTAssertNil(policy.propose(target: target(at: 20), finder: .chair, distances: empty, now: 20))
        let chair = try XCTUnwrap(policy.propose(target: target(at: 20.8), finder: .chair, distances: empty, now: 20.8))
        XCTAssertTrue(chair.text.hasPrefix("A chair"))
    }

    func testSupportRejectsChangedSceneButDoesNotRequireTargetForObstacle() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0)
        let obstacle = try XCTUnwrap(policy.propose(target: nil, finder: .none, distances: sectors(0.8), now: 0.8))
        XCTAssertTrue(obstacle.isSupported(target: nil, finder: .none, distances: sectors(0.75), now: 1))
        XCTAssertFalse(obstacle.isSupported(target: nil, finder: .none, distances: sectors(0.3), now: 1))
        XCTAssertFalse(obstacle.isSupported(target: nil, finder: .none, distances: sectors(0.8, column: 1), now: 1))
        XCTAssertFalse(obstacle.isSupported(target: nil, finder: .none, distances: empty, now: 1))
        policy.reset()
        _ = policy.propose(target: target(at: 2), finder: .door, distances: empty, now: 2)
        let door = try XCTUnwrap(policy.propose(target: target(at: 2.8), finder: .door, distances: empty, now: 2.8))
        XCTAssertTrue(door.isSupported(target: target(distance: 2.2, at: 3), finder: .door, distances: empty, now: 3))
        XCTAssertFalse(door.isSupported(target: target(at: 2), finder: .door, distances: empty, now: 3))
        XCTAssertFalse(door.isSupported(target: target(at: 3), finder: .chair, distances: empty, now: 3))
        XCTAssertFalse(door.isSupported(target: target(bearing: 16, at: 3), finder: .door, distances: empty, now: 3))
    }

    func testResetClearsCooldownAndRejectsAcknowledgementFromOldScene() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(at: 0), finder: .person, distances: empty, now: 0)
        let old = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: empty, now: 0.8))
        policy.acknowledge(old, now: 0.8)
        policy.reset()
        _ = policy.propose(target: target(at: 1), finder: .person, distances: empty, now: 1)
        let fresh = try XCTUnwrap(policy.propose(target: target(at: 1.8), finder: .person, distances: empty, now: 1.8))
        XCTAssertNotEqual(old.key, fresh.key)
        policy.acknowledge(old, now: 1.8)
        XCTAssertNotNil(policy.propose(target: target(at: 1.9), finder: .person, distances: empty, now: 1.9))
    }

    func testDeliveryAfterFreshSamplesAcknowledgesTheSpokenObservation() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(at: 0), finder: .person, distances: empty, now: 0)
        let spoken = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: empty, now: 0.8))
        _ = policy.propose(target: target(distance: 2.1, at: 1), finder: .person, distances: empty, now: 1)
        policy.acknowledge(spoken, now: 1.1)
        XCTAssertNil(policy.propose(target: target(distance: 2.1, at: 20), finder: .person, distances: empty, now: 20))
    }

    func testUndeliveredObservationRemainsEligibleAfterNetworkDelay() throws {
        var policy = ProactiveVoicePolicy(); policy.announcesObstacles = true
        _ = policy.propose(target: target(at: 0), finder: .person, distances: empty, now: 0)
        let first = try XCTUnwrap(policy.propose(target: target(at: 0.8), finder: .person, distances: empty, now: 0.8))
        // A request canceled before playback never acknowledges the proposal.
        let retried = try XCTUnwrap(policy.propose(target: target(at: 10), finder: .person, distances: empty, now: 10))
        XCTAssertEqual(first.key, retried.key)
    }

    private func target(distance: Double = 2, bearing: Double = 0, at now: TimeInterval) -> TargetObservation {
        TargetObservation(bearingDegrees: bearing, distance: distance, timestamp: now)
    }

    private func sectors(_ distance: Double, column: Int = 3) -> [Double?] {
        var values = empty
        values[column] = distance
        return values
    }
}
