import XCTest
import AVFoundation
import UIKit
import ARKit
import FeelCore
@testable import Lantern

final class LanternTests:XCTestCase {
    func testCameraPreviewPreservesPerceptionSessionDelegate() {
        let perception = ARPerception()
        let preview = ARSCNView()
        preview.session = perception.session
        XCTAssertTrue(preview.session === perception.session)
        XCTAssertTrue(perception.session.delegate === perception)
    }
    func testBundledGeistFontsAreRegistered() {
        for name in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold", "GeistMono-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 17), "Missing bundled font: \(name)")
        }
    }
    func testProductionPacketIntegration() throws {
        let output=TactileEncoder.encode(sequence:42,now:5,frameTimestamp:5,tracking:true,distances:[0.3,0.9,1.6,2.5,4,nil,0.1],target:TargetObservation(bearingDegrees:40,distance:1,timestamp:5))
        XCTAssertEqual(output.packet.bytes,[42,1,2,3,4,4,0,1,6])
        XCTAssertEqual(try FeelPacket(bytes:Array(output.packet.data)),output.packet)
    }
    func testAllFindModesAreAccessibleNames() {
        XCTAssertEqual(FinderMode.allCases.count,6)
        XCTAssertTrue(FinderMode.allCases.allSatisfy { !$0.rawValue.isEmpty })
        XCTAssertEqual(FinderMode.door.rawValue,"Door candidate")
    }
    func testLossClearsHighlight() {
        let output=TactileEncoder.encode(sequence:5,now:6,frameTimestamp:5,tracking:true,distances:Array(repeating:1,count:7),target:.init(bearingDegrees:0,distance:1,timestamp:6))
        XCTAssertEqual(output.state,.staleDepth); XCTAssertEqual(output.packet.effectiveHighlight,255)
    }
}

@MainActor
final class MemoryCoordinatorTests:XCTestCase {
    func testRememberMoveRecallAndStopUsesProductionPackets() {
        let model=LanternModel(); defer { model.stop() }
        model.startSimulation(memory:true); model.placeName="Desk"; model.remember()
        XCTAssertEqual(model.spatialMemory.bookmarks.count,1)
        model.simulateMove(metres:-2); model.recall()
        XCTAssertEqual(model.memoryGuidance?.state,.guiding)
        XCTAssertEqual(model.packet.highlight,3)
        XCTAssertEqual(model.packet.bands[2],1) // Independent simulated closer obstacle survives.
        XCTAssertEqual(model.packet.bands[3],3)
        model.stopMemoryGuidance()
        XCTAssertEqual(model.packet.highlight,255); XCTAssertEqual(model.packet.bands[2],1)
        XCTAssertEqual(model.spatialMemory.bookmarks.count,1)
    }
    func testSimulatedTrackingLossReturnAndReset() {
        let model=LanternModel(); defer { model.stop() }
        model.startSimulation(memory:true); model.setReturnPoint()
        model.simulateMove(metres:-2); model.returnToPoint()
        XCTAssertEqual(model.packet.highlight,3)
        model.simulatedTracking=false
        XCTAssertEqual(model.packet.bands,[0,0,0,0,0,0,0]); XCTAssertEqual(model.packet.highlight,255)
        XCTAssertNotNil(model.spatialMemory.returnPoint)
        model.simulatedTracking=true; XCTAssertEqual(model.packet.highlight,3)
        let oldSession=model.spatialMemory.session
        model.resetSimulatedSession()
        XCTAssertNotEqual(model.spatialMemory.session,oldSession)
        XCTAssertNil(model.spatialMemory.returnPoint); XCTAssertNil(model.spatialMemory.activeID)
        XCTAssertEqual(model.packet.highlight,255)
    }
    func testChoosingFinderStopsMemoryImmediatelyAndModeSwitchClearsPlaces() {
        let model=LanternModel(); defer { model.stop() }
        model.startSimulation(memory:true); model.placeName="Desk"; model.remember()
        model.simulateMove(metres:-2); model.recall(); XCTAssertEqual(model.packet.highlight,3)
        model.finder = .person
        XCTAssertNil(model.spatialMemory.activeID); XCTAssertEqual(model.packet.highlight,255)
        model.startSimulation()
        XCTAssertTrue(model.spatialMemory.bookmarks.isEmpty); XCTAssertNil(model.spatialMemory.session)
    }
}

final class ChimeTests: XCTestCase {
    func testChimeIsAValidShortWav() throws {
        let data = Chime.wav()
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        // Two 110 ms notes at 44.1 kHz, 16-bit mono, plus a 44-byte header.
        XCTAssertEqual(data.count, 44 + 2 * 4851 * 2)
        let player = try AVAudioPlayer(data: data)
        XCTAssertEqual(player.duration, 0.22, accuracy: 0.01)
    }
    func testFailureAndListeningSoundsDiffer() throws {
        XCTAssertEqual(try AVAudioPlayer(data: Chime.wav(.failure)).duration, 0.28, accuracy: 0.01)
        XCTAssertEqual(try AVAudioPlayer(data: Chime.wav(.listening)).duration, 0.06, accuracy: 0.01)
        XCTAssertGreaterThan(Chime.notes(.success).frequencies.first!, Chime.notes(.failure).frequencies.first!)
        XCTAssertGreaterThan(Chime.notes(.failure).frequencies.first!, Chime.notes(.failure).frequencies.last!, "failure falls")
    }
}
