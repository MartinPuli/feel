import Foundation
import AVFoundation
import FeelCore

/// Writes processed AR frames to Documents/Recordings/*.feelrec for offline replay with
/// simulation/run.py and the /replay web viewer. Stores depth, confidence, pose, floor height and the
/// cached detection. With camera video on, also writes <name>.mp4 (960 × 720 H.264, 15 fps, no audio)
/// and <name>.video.json, which maps video time 0 to the ARKit timestamp of its first frame.
/// Files stay on the phone until the user shares them (Files app → On My iPhone → FEEL → Recordings).
final class SessionRecorder {
    /// About ten minutes at 10 Hz and ~250 kB per frame.
    static let maxBytes = 1_500_000_000
    static let videoInterval = 1.0 / 15
    private let queue = DispatchQueue(label: "feel.recorder", qos: .utility)
    private var handle: FileHandle?
    private var bytes = 0, frames = 0, videoFrames = 0
    private var url: URL?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    /// Work waiting for the recorder queue, counted by the AR queue at enqueue time.
    private let lock = NSLock()
    private var backlog = 0, videoBacklog = 0, droppedInFlight = 0, active = false, videoEnabled = false
    private var lastVideo = -Double.infinity
    /// Cheap check for the AR queue, so frames are only copied while recording.
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    private var dropped: Int { lock.lock(); defer { lock.unlock() }; return droppedInFlight }
    /// Main queue: a short human-readable status, nil when idle.
    var onStatus: ((String?) -> Void)?

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
    }

    func start(cameraHeight: Double, video: Bool, note: String? = nil) {
        lock.lock(); active = true; videoEnabled = video; lastVideo = -.infinity; lock.unlock()
        queue.async {
            self.closeFile(deactivate: false)
            do {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date())
                let base = Self.directory.appendingPathComponent("feel-\(stamp.replacingOccurrences(of: ":", with: "-"))")
                let url = base.appendingPathExtension("feelrec")
                let header = try SessionRecording.start(RecordingInfo(source: "iphone", createdAt: stamp, cameraHeight: cameraHeight, note: note))
                guard FileManager.default.createFile(atPath: url.path, contents: header) else { throw CocoaError(.fileWriteUnknown) }
                self.handle = try FileHandle(forWritingTo: url); try self.handle?.seekToEnd()
                self.url = url; self.bytes = header.count; self.frames = 0; self.videoFrames = 0; self.events = []
                if video { try self.openVideo(base.appendingPathExtension("mp4")) }
                self.lock.lock(); self.droppedInFlight = 0; self.active = true; self.lock.unlock()
                self.publish("Recording \(url.lastPathComponent)\(video ? " with camera video" : "")")
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

    /// Called from the AR queue for every ARFrame; keeps one per `videoInterval`. At most two camera
    /// buffers are held at once so ARKit's buffer pool is never starved.
    func appendVideo(_ buffer: CVPixelBuffer, timestamp: Double) {
        lock.lock()
        let take = active && videoEnabled && videoBacklog < 2 && timestamp - lastVideo >= Self.videoInterval - 0.002
        if take { videoBacklog += 1; lastVideo = timestamp }
        lock.unlock()
        guard take else { return }
        queue.async {
            defer { self.lock.lock(); self.videoBacklog -= 1; self.lock.unlock() }
            guard let writer = self.writer, let input = self.videoInput, let adaptor = self.adaptor else { return }
            let time = CMTime(seconds: timestamp, preferredTimescale: 6000)
            if writer.status == .unknown {
                guard writer.startWriting() else { self.dropVideo("Camera video failed: \(writer.error?.localizedDescription ?? "unknown")"); return }
                writer.startSession(atSourceTime: time)
                self.writeVideoTiming(start: timestamp)
            }
            guard writer.status == .writing else { return }
            if input.isReadyForMoreMediaData, adaptor.append(buffer, withPresentationTime: time) { self.videoFrames += 1 }
        }
    }

    /// Trial events, rewritten to <name>.events.json on each mark so a crash keeps what was marked.
    private var events: [[String: Any]] = []
    func mark(_ kind: String, at timestamp: Double) {
        queue.async {
            guard let url = self.url else { return }
            self.events.append(["t": timestamp, "kind": kind])
            let sidecar = url.deletingPathExtension().appendingPathExtension("events.json")
            try? JSONSerialization.data(withJSONObject: ["events": self.events]).write(to: sidecar)
        }
    }

    func stop() {
        lock.lock(); active = false; lock.unlock()
        queue.async {
            guard let url = self.url else { return }
            let summary = "Saved \(url.lastPathComponent): \(self.frames) frames, \(self.bytes / 1_000_000) MB"
                + (self.writer != nil ? ", \(self.videoFrames) video frames" : "") + (self.dropped > 0 ? ", \(self.dropped) dropped" : "")
            self.closeFile(); self.publish(summary)
        }
    }

    private func openVideo(_ url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 960, AVVideoHeightKey: 720,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        self.writer = writer; videoInput = input
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    }

    /// Sidecar read by simulation/run.py: video time 0 is ARKit timestamp `start`.
    private func writeVideoTiming(start: Double) {
        guard let url, let writer else { return }
        let sidecar = url.deletingPathExtension().appendingPathExtension("video.json")
        let body: [String: Any] = ["video": writer.outputURL.lastPathComponent, "start": start]
        try? JSONSerialization.data(withJSONObject: body).write(to: sidecar)
    }

    private func dropVideo(_ message: String) {
        writer?.cancelWriting(); writer = nil; videoInput = nil; adaptor = nil
        publish(message)
    }

    private func publishProgress() {
        publish("Recording: \(frames) frames, \(bytes / 1_000_000) MB" + (dropped > 0 ? ", \(dropped) dropped" : ""))
    }
    private func closeFile(deactivate: Bool = true) {
        try? handle?.close(); handle = nil; url = nil
        if let writer {
            if writer.status == .writing { videoInput?.markAsFinished(); writer.finishWriting { _ = writer } } else { writer.cancelWriting() }
        }
        writer = nil; videoInput = nil; adaptor = nil
        if deactivate { lock.lock(); active = false; lock.unlock() }
    }
    private func publish(_ status: String?) { DispatchQueue.main.async { self.onStatus?(status) } }
}
