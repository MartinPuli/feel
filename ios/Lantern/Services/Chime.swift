import Foundation
import AVFoundation
import FeelCore

/// Short feedback tones, synthesized in memory (no bundled audio). Direction guidance uses
/// only these, never speech: a rising chime for success, a soft falling pair for failure, and a
/// quiet blip when the phone starts listening for the target word.
final class Chime {
    private var player: AVAudioPlayer?
    private var cache: [RequestSound: Data] = [:]

    func play(_ sound: RequestSound = .success) {
        let session = AVAudioSession.sharedInstance()
        // Keep the microphone session (assistant or target-word listening) if one is running;
        // otherwise use playback, which stays audible with the ring/silent switch on.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        }
        try? session.setActive(true)
        let data = cache[sound] ?? Self.wav(sound)
        cache[sound] = data
        player = try? AVAudioPlayer(data: data)
        player?.volume = sound == .listening ? 0.5 : 0.8
        player?.play()
    }

    static func notes(_ sound: RequestSound) -> (frequencies: [Double], milliseconds: Int, decay: Double) {
        switch sound {
        case .success: return ([1318.5, 1760.0], 110, 14)   // E6 → A6
        case .failure: return ([466.2, 349.2], 140, 9)       // B♭4 → F4
        case .listening: return ([1046.5], 60, 30)           // C6 blip
        }
    }

    /// 16-bit mono PCM WAV with short fades so no note clicks.
    static func wav(_ sound: RequestSound = .success, sampleRate: Int = 44_100) -> Data {
        let (frequencies, milliseconds, decayRate) = notes(sound)
        let noteSamples = sampleRate * milliseconds / 1000
        let fade = sampleRate * 8 / 1000
        var samples: [Int16] = []
        samples.reserveCapacity(noteSamples * frequencies.count)
        for frequency in frequencies {
            for i in 0..<noteSamples {
                let t = Double(i) / Double(sampleRate)
                let edge = min(1, Double(min(i, noteSamples - 1 - i)) / Double(fade))
                // A quiet octave overtone with a fast decay reads as a modern chime rather than a beep.
                let value = (sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)) / 1.25
                samples.append(Int16(value * edge * exp(-t * decayRate) * 0.6 * Double(Int16.max)))
            }
        }
        var out = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        let dataBytes = samples.count * 2
        out.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataBytes))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        out.append(contentsOf: Array("data".utf8)); append(UInt32(dataBytes))
        for s in samples { append(s) }
        return out
    }
}
