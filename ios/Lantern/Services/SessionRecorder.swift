import Foundation
import FeelCore

/// Writes processed AR frames to Documents/Recordings/*.feelrec for offline replay with
/// simulation/run.py. Stores depth, confidence, pose, floor height and the cached detection:
/// never the camera image or audio. Files stay on the phone until the user shares them
/// (Files app → On My iPhone → FEEL → Recordings).
final class SessionRecorder {
    /// About ten minutes at 10 Hz and ~250 kB per frame.
    static let maxBytes = 1_500_000_000
    private let queue = DispatchQueue(label: "feel.recorder", qos: .utility)
    private var handle: FileHandle?
    private var bytes = 0, frames = 0
    /// Frames waiting for the recorder queue, counted by the AR queue at enqueue time.
    private let lock = NSLock()
    private var backlog = 0, droppedInFlight = 0, active = false
    /// Cheap check for the AR queue, so frames are only copied while recording.
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    private var dropped: Int { lock.lock(); defer { lock.unlock() }; return droppedInFlight }
    private var url: URL?
    /// Main queue: a short human-readable status, nil when idle.
    var onStatus: ((String?) -> Void)?

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
    }

    func start(cameraHeight: Double, note: String? = nil) {
        lock.lock(); active = true; lock.unlock()
        queue.async {
            self.closeFile(deactivate: false)
            do {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date())
                let url = Self.directory.appendingPathComponent("feel-\(stamp.replacingOccurrences(of: ":", with: "-")).feelrec")
                let header = try SessionRecording.start(RecordingInfo(source: "iphone", createdAt: stamp, cameraHeight: cameraHeight, note: note))
                guard FileManager.default.createFile(atPath: url.path, contents: header) else { throw CocoaError(.fileWriteUnknown) }
                self.handle = try FileHandle(forWritingTo: url); try self.handle?.seekToEnd()
                self.url = url; self.bytes = header.count; self.frames = 0
                self.lock.lock(); self.droppedInFlight = 0; self.active = true; self.lock.unlock()
                self.publish("Recording \(url.lastPathComponent)")
            } catch { self.closeFile(); self.publish("Recording failed: \(error.localizedDescription)") }
        }
    }

    /// Called from the AR queue. Encoding and writing happen on the recorder queue; if writes fall
    /// behind, frames are dropped (and counted) rather than stalling perception.
    func append(_ frame: RecordedFrame) {
        lock.lock()
        let full = backlog >= 8
        if full { droppedInFlight += 1 } else { backlog += 1 }
        lock.unlock()
        guard !full else { return }
        queue.async {
            defer { self.lock.lock(); self.backlog -= 1; self.lock.unlock() }
            guard self.handle != nil else { return }
            do {
                let data = try SessionRecording.encode(frame)
                try self.handle?.write(contentsOf: data)
                self.bytes += data.count; self.frames += 1
                if self.bytes >= Self.maxBytes { self.closeFile(); self.publish("Recording stopped at the size limit"); return }
                if self.frames % 50 == 0 { self.publishProgress() }
            } catch { self.closeFile(); self.publish("Recording failed: \(error.localizedDescription)") }
        }
    }

    func stop() {
        lock.lock(); active = false; lock.unlock()
        queue.async {
            guard let url = self.url else { return }
            let summary = "Saved \(url.lastPathComponent): \(self.frames) frames, \(self.bytes / 1_000_000) MB" + (self.dropped > 0 ? ", \(self.dropped) dropped" : "")
            self.closeFile(); self.publish(summary)
        }
    }

    private func publishProgress() {
        publish("Recording: \(frames) frames, \(bytes / 1_000_000) MB" + (dropped > 0 ? ", \(dropped) dropped" : ""))
    }
    private func closeFile(deactivate: Bool = true) {
        try? handle?.close(); handle = nil; url = nil
        if deactivate { lock.lock(); active = false; lock.unlock() }
    }
    private func publish(_ status: String?) { DispatchQueue.main.async { self.onStatus?(status) } }
}
