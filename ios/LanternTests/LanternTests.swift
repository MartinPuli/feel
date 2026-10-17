import XCTest
import UIKit
import FeelCore
@testable import Lantern

final class LanternTests:XCTestCase {
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
