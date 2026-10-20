import XCTest
@testable import Lantern

final class VoiceAudioTests: XCTestCase {
    func testPCMDecodesSignedLittleEndianExtremes() throws {
        let decoded = try VoicePCM.decode(Data([0, 128, 255, 255, 0, 0, 1, 0, 255, 127]))
        let scale: Float = 32_768
        XCTAssertEqual(decoded, [-1, -1 / scale, 0, 1 / scale, 32_767 / scale])
    }

    func testPCMRejectsIncompleteSampleAndOversizedBuffer() {
        XCTAssertThrowsError(try VoicePCM.decode(Data([1])))
        XCTAssertThrowsError(try VoicePCM.decode(Data(count: (VoicePCM.maximumQueuedFrames + 1) * 2)))
    }

    func testPCMHandlesDataSliceWithoutAlignmentAssumptions() throws {
        let prefixed = Data([99, 0, 128, 255, 127])
        let scale: Float = 32_768
        XCTAssertEqual(try VoicePCM.decode(prefixed.dropFirst()), [-1, 32_767 / scale])
        XCTAssertEqual(try VoicePCM.decode(Data()), [])
    }

    func testPCMEncodesSignedSamplesInLittleEndianOrder() {
        let samples: [Int16] = [.min, -1, 0, 1, .max]
        let encoded = samples.withUnsafeBufferPointer { VoicePCM.encode($0) }
        XCTAssertEqual(encoded, Data([0, 128, 255, 255, 0, 0, 1, 0, 255, 127]))
    }
}
