import XCTest
import UIKit
import ARKit
import AVFoundation
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
}
