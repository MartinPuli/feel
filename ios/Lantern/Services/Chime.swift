import Foundation
import AVFoundation

/// A short rising two-note chime, synthesized in memory (no bundled audio).
/// Plays when a V sign successfully starts direction guidance.
final class Chime {
    private var player: AVAudioPlayer?
    private lazy var data = Chime.wav()

    func play() {
        let session = AVAudioSession.sharedInstance()
        // Keep the assistant's microphone session if it is running; otherwise use playback,
        // which stays audible with the ring/silent switch on, like the app's spoken fallback.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
        player = try? AVAudioPlayer(data: data)
        player?.volume = 0.8
        player?.play()
    }

    /// 16-bit mono PCM WAV: E6 then A6, 110 ms each, with short fades so neither note clicks.
    static func wav(sampleRate: Int = 44_100) -> Data {
        let notes: [Double] = [1318.5, 1760.0]
        let noteSamples = sampleRate * 110 / 1000
        let fade = sampleRate * 8 / 1000
        var samples: [Int16] = []
        samples.reserveCapacity(noteSamples * notes.count)
        for frequency in notes {
            for i in 0..<noteSamples {
                let t = Double(i) / Double(sampleRate)
                let edge = min(1, Double(min(i, noteSamples - 1 - i)) / Double(fade))
                // Gentle decay with a quiet octave overtone reads as a chime rather than a beep.
                let decay = exp(-t * 14)
                let value = (sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)) / 1.25
                samples.append(Int16(value * edge * decay * 0.6 * Double(Int16.max)))
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
