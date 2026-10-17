import XCTest
@testable import FeelCore

/// What a held Where-is target does on each frame, kept pure so the ARKit-driven tick stays thin.
final class HeldTargetGuidanceTests: XCTestCase {
    private let ahead=HeldTarget(position:Vector3(0,0,-3),label:"desk",worldEpoch:1,setAt:0)
    private let behind=HeldTarget(position:Vector3(0,0,3),label:"desk",worldEpoch:1,setAt:0)
    private let near=HeldTarget(position:Vector3(0,0,-0.3),label:"desk",worldEpoch:1,setAt:0)

    func testWorldChangeLosesTheTargetEvenWhenSensingIsNotLive() {
        XCTAssertEqual(HeldTargetGuidance.event(target:ahead,pose: .identity,worldEpoch:2,now:10,live:false,inField:false,lastSpokenAt: -.infinity), .lostTracking)
    }
    func testArrivalCountsOnlyWhileSensingIsLive() {
        XCTAssertEqual(HeldTargetGuidance.event(target:near,pose: .identity,worldEpoch:1,now:10,live:true,inField:true,lastSpokenAt: -.infinity), .reached)
        XCTAssertEqual(HeldTargetGuidance.event(target:near,pose: .identity,worldEpoch:1,now:10,live:false,inField:true,lastSpokenAt: -.infinity), .keep)
    }
    func testOutOfFieldTargetSpeaksItsDirectionEveryFiveSeconds() {
        XCTAssertEqual(HeldTargetGuidance.event(target:behind,pose: .identity,worldEpoch:1,now:10,live:true,inField:false,lastSpokenAt: -.infinity), .speak("desk is behind you."))
        XCTAssertEqual(HeldTargetGuidance.event(target:behind,pose: .identity,worldEpoch:1,now:10,live:true,inField:false,lastSpokenAt:6), .keep)
        XCTAssertEqual(HeldTargetGuidance.event(target:behind,pose: .identity,worldEpoch:1,now:11,live:true,inField:false,lastSpokenAt:6), .speak("desk is behind you."))
        XCTAssertEqual(HeldTargetGuidance.event(target:behind,pose: .identity,worldEpoch:1,now:11,live:false,inField:false,lastSpokenAt:6), .keep)
    }
    func testInFieldTargetIsLeftToThePins() {
        XCTAssertEqual(HeldTargetGuidance.event(target:ahead,pose: .identity,worldEpoch:1,now:10,live:true,inField:true,lastSpokenAt: -.infinity), .keep)
    }
    func testFinderTargetsNeverShadowAHeldTarget() {
        let finder=TargetObservation(bearingDegrees:10,distance:2,timestamp:1)
        let held=TargetObservation(bearingDegrees:-10,distance:3,timestamp:1,label:"desk")
        XCTAssertNil(HeldTargetGuidance.pins(held:nil,holding:true,finder:finder))
        XCTAssertEqual(HeldTargetGuidance.pins(held:nil,holding:false,finder:finder),finder)
        XCTAssertEqual(HeldTargetGuidance.pins(held:held,holding:true,finder:finder),held)
    }
    func testTargetLostIsOnlyAnnouncedForFinderTargets() {
        XCTAssertTrue(HeldTargetGuidance.announcesTargetLost(sawTarget:true,holding:false))
        XCTAssertFalse(HeldTargetGuidance.announcesTargetLost(sawTarget:true,holding:true))
        XCTAssertFalse(HeldTargetGuidance.announcesTargetLost(sawTarget:false,holding:false))
    }
}
