import AVFoundation
import Foundation

/// All calls and callbacks use the main thread. The controller owns route and lifecycle recovery.
protocol VoiceAudioIO: AnyObject {
    var pendingPlayback: Bool { get }
    var playedMilliseconds: Int { get }
    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws
    func play(_ pcm: Data) throws
    func interruptPlayback()
    func stop()
}

enum VoiceAudioError: LocalizedError {
    case unavailableInput, invalidPCM, playbackOverflow, notRunning

    var errorDescription: String? {
        switch self {
        case .unavailableInput: return "The microphone is unavailable. Check your audio connection."
        case .invalidPCM: return "Voice returned an invalid audio buffer."
        case .playbackOverflow: return "Voice playback fell behind. Please reconnect."
        case .notRunning: return "Voice audio is not running."
        }
    }
}

/// OpenAI Realtime's wire format is mono, signed 16-bit little-endian PCM at 24 kHz.
enum VoicePCM {
    static let sampleRate = 24_000.0
    static let maximumQueuedFrames = 24_000 * 20

    static func decode(_ data: Data) throws -> [Float] {
        guard data.count.isMultiple(of: 2), data.count / 2 <= maximumQueuedFrames else {
            throw VoiceAudioError.invalidPCM
        }
        return data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 2).map { index in
                let value = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                return Float(Int16(bitPattern: value)) / 32_768
            }
        }
    }

    static func encode(_ samples: UnsafeBufferPointer<Int16>) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for (index, sample) in samples.enumerated() {
                let value = UInt16(bitPattern: sample)
                bytes[index * 2] = UInt8(truncatingIfNeeded: value)
                bytes[index * 2 + 1] = UInt8(truncatingIfNeeded: value >> 8)
            }
        }
        return data
    }
}

final class DeviceVoiceAudio: VoiceAudioIO {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var captureFormat: AVAudioFormat?
    private var inputDelivery: VoiceInputDelivery?
    private var onPlaybackDrained: (() -> Void)?
    private var playbackGeneration = UUID()
    private var queuedFrames = 0
    private var queuedBuffers = 0
    private var groupScheduledFrames = 0
    private var groupCompletedFrames = 0
    private var previousGroupFrames = 0
    private var ownsAudioSession = false

    var pendingPlayback: Bool { queuedBuffers > 0 }

    /// Uses the player timeline, excluding idle gaps and downstream output latency.
    /// This is an estimate for conversation truncation, not a physical speaker measurement.
    var playedMilliseconds: Int {
        var frames = groupCompletedFrames
        if let player, let renderTime = player.lastRenderTime,
           let time = player.playerTime(forNodeTime: renderTime), time.sampleRate > 0 {
            let audibleSeconds = max(0, Double(time.sampleTime) / time.sampleRate - player.outputPresentationLatency)
            frames = max(frames, min(groupScheduledFrames, Int(audibleSeconds * VoicePCM.sampleRate)))
        }
        return Int(Double(previousGroupFrames + frames) * 1_000 / VoicePCM.sampleRate)
    }

    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws {
        precondition(Thread.isMainThread)
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            ownsAudioSession = true
            let newEngine = AVAudioEngine()
            engine = newEngine
            let input = newEngine.inputNode
            // Voice processing must be enabled before configuring the graph or starting it.
            try input.setVoiceProcessingEnabled(true)
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: VoicePCM.sampleRate,
                                                channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: inputFormat, to: wireFormat),
                  let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: VoicePCM.sampleRate, channels: 1)
            else { throw VoiceAudioError.unavailableInput }
            converter.downmix = true
            let delivery = VoiceInputDelivery(onInput: onInput)
            inputDelivery = delivery
            let capture = VoiceInputCapture(converter: converter, delivery: delivery)
            input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
                capture.receive(buffer)
            }
            tapInstalled = true
            captureFormat = inputFormat
            let newPlayer = AVAudioPlayerNode()
            player = newPlayer
            newEngine.attach(newPlayer)
            newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: playbackFormat)
            self.onPlaybackDrained = onPlaybackDrained
            newEngine.prepare()
            try newEngine.start()
        } catch {
            stop()
            throw error
        }
    }

    private var tapInstalled = false

    func play(_ pcm: Data) throws {
        precondition(Thread.isMainThread)
        guard let engine, let player else { throw VoiceAudioError.notRunning }
        if !engine.isRunning {
            // A system output-format change can stop the engine just after startup.
            // Restart the existing graph only if its microphone converter is still valid.
            // Explicit stop clears engine, so this cannot restart a stopped session.
            guard let captureFormat,
                  engine.inputNode.outputFormat(forBus: 0).isEqual(captureFormat) else {
                VoiceDiagnostics.record("audio_input_format_changed")
                throw VoiceAudioError.unavailableInput
            }
            try engine.start()
            guard engine.isRunning else { throw VoiceAudioError.notRunning }
            VoiceDiagnostics.record("audio_engine_restarted")
        }
        guard !pcm.isEmpty else { return }
        guard pcm.count.isMultiple(of: 2) else { throw VoiceAudioError.invalidPCM }
        let frames = pcm.count / 2
        // Also cap buffer count so tiny network fragments cannot enqueue unlimited callbacks.
        guard frames <= VoicePCM.maximumQueuedFrames - queuedFrames, queuedBuffers < 2_048 else {
            throw VoiceAudioError.playbackOverflow
        }
        let samples = try VoicePCM.decode(pcm)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: VoicePCM.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { throw VoiceAudioError.invalidPCM }
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: frames) }
        }
        queuedFrames += frames
        queuedBuffers += 1
        groupScheduledFrames += frames
        let generation = playbackGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.queuedFrames -= frames
                self.queuedBuffers -= 1
                self.groupCompletedFrames += frames
                guard self.queuedBuffers == 0 else { return }
                self.previousGroupFrames += self.groupScheduledFrames
                self.groupScheduledFrames = 0
                self.groupCompletedFrames = 0
                // Freeze the timeline between chunks, so silence never inflates truncation time.
                self.player?.stop()
                self.onPlaybackDrained?()
            }
        }
        if !player.isPlaying { player.play() }
    }

    func interruptPlayback() {
        precondition(Thread.isMainThread)
        playbackGeneration = UUID()
        player?.stop()
        queuedFrames = 0
        queuedBuffers = 0
        groupScheduledFrames = 0
        groupCompletedFrames = 0
        previousGroupFrames = 0
    }

    func stop() {
        precondition(Thread.isMainThread)
        // Invalidate delivery first. An in-flight tap retains its converter and cannot reach a new session.
        inputDelivery?.invalidate()
        inputDelivery = nil
        onPlaybackDrained = nil
        interruptPlayback()
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        captureFormat = nil
        player = nil
        engine = nil
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }
}

/// A tap owns this immutable converter for its entire lifetime, including callbacks racing teardown.
private final class VoiceInputCapture {
    let converter: AVAudioConverter
    let delivery: VoiceInputDelivery

    init(converter: AVAudioConverter, delivery: VoiceInputDelivery) {
        self.converter = converter
        self.delivery = delivery
    }

    func receive(_ input: AVAudioPCMBuffer) {
        let capacity = ceil(Double(input.frameLength) * VoicePCM.sampleRate / input.format.sampleRate) + 64
        guard capacity > 0, capacity <= VoicePCM.sampleRate,
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(capacity))
        else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, output.frameLength > 0,
              let samples = output.int16ChannelData?[0] else { return }
        delivery.enqueue(VoicePCM.encode(UnsafeBufferPointer(start: samples, count: Int(output.frameLength))))
    }
}

/// At most one main-queue block and half a second of microphone data can wait for delivery.
private final class VoiceInputDelivery {
    private let lock = NSLock()
    private var callback: ((Data) -> Void)?
    private var pending = Data()
    private var scheduled = false
    private let maximumBytes = 24_000

    init(onInput: @escaping (Data) -> Void) { callback = onInput }

    func enqueue(_ data: Data) {
        lock.lock()
        guard callback != nil, pending.count + data.count <= maximumBytes else { lock.unlock(); return }
        pending.append(data)
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule {
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
    }

    func invalidate() {
        lock.lock()
        callback = nil
        pending.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        let data = pending
        pending = Data()
        let callback = callback
        scheduled = false
        lock.unlock()
        if !data.isEmpty { callback?(data) }
    }
}
