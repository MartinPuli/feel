import Foundation
import Combine
import AVFoundation
import Speech
import UIKit

/// A generation belongs to one explicit push-to-talk attempt. The same gate is
/// used by authorization, recognition, cancellation and timeout paths.
struct VoiceAttempt {
    enum Phase { case idle, authorizing, listening, finishing }
    private(set) var generation: UInt64 = 0
    private(set) var phase: Phase = .idle

    mutating func begin() -> UInt64 {
        generation &+= 1; phase = .authorizing; return generation
    }
    func authorizing(_ token: UInt64) -> Bool {
        token == generation && phase == .authorizing
    }
    func acceptsResult(_ token: UInt64) -> Bool {
        token == generation && (phase == .listening || phase == .finishing)
    }
    mutating func listen(_ token: UInt64) -> Bool {
        guard authorizing(token) else { return false }
        phase = .listening; return true
    }
    mutating func finish(_ token: UInt64) -> Bool {
        guard token == generation, phase == .listening else { return false }
        phase = .finishing; return true
    }
    mutating func complete(_ token: UInt64) -> Bool {
        guard acceptsResult(token) else { return false }
        cancel(); return true
    }
    mutating func cancel() { generation &+= 1; phase = .idle }
}

enum VoiceTranscriptPolicy {
    // Match the core command parser. One composed Character may contain an
    // arbitrarily large number of combining scalars, so Character count is not
    // an input-size bound.
    static let maximumScalars = 160
    static func isWithinLimit(_ text: String) -> Bool {
        text.unicodeScalars.prefix(maximumScalars + 1).count <= maximumScalars
    }
    static func display(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars.prefix(maximumScalars) where !isControl(scalar) { scalars.append(scalar) }
        return String(scalars)
    }
    static func final(_ text: String) -> String? {
        // Reject an overlong utterance instead of executing its truncated prefix.
        guard isWithinLimit(text),
              !text.unicodeScalars.contains(where: isControl) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate: return true
        default: return false
        }
    }
}

/// The audio tap is not a main-queue callback. A closed pipe can never append to
/// an ended request, even when an old tap callback races with Stop or a new task.
private final class VoiceAudioPipe {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
    func close() { lock.lock(); request = nil; lock.unlock() }
}

/// Explicit push-to-talk only. No permission request, microphone capture or
/// speech occurs during initialization. All observable state stays on main.
final class LocalVoiceControl: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var status = "Voice idle. Tap Speak command to listen on this device."
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var canFinish = false
    /// Includes authorization and final-result processing, when capture is no longer running.
    var hasPendingAttempt: Bool { attempt.phase != .idle }
    var onFinalTranscript: ((String) -> Void)?
    /// Called on main immediately before acquiring the microphone. The app must
    /// release realtime and keyword capture here. Canceling here aborts this attempt.
    /// Finishing or cancellation never restarts another microphone owner automatically.
    var onCaptureWillStart: (() -> Void)?

    private var attempt = VoiceAttempt()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    private var pipe: VoiceAudioPipe?
    private var tapInstalled = false
    private var audioSessionActive = false
    private var captureDeadline: DispatchWorkItem?
    private var finalDeadline: DispatchWorkItem?
    private let synthesizer = AVSpeechSynthesizer()
    private var speakingUtterance: AVSpeechUtterance?
    private var speakingGeneration: UInt64?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = false
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelInternal(status: "Voice canceled in background.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  value == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.cancelInternal(status: "Audio interrupted. Tap Speak command to try again.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelInternal(status: "Audio service reset. Tap Speak command to try again.")
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        captureDeadline?.cancel(); finalDeadline?.cancel()
        pipe?.close(); engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        task?.cancel(); synthesizer.stopSpeaking(at: .immediate)
        if audioSessionActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func start(localeIdentifier: String) {
        onMain { $0.startInternal(localeIdentifier: localeIdentifier) }
    }

    /// Stop microphone capture, then allow at most three seconds for a final
    /// result. Unlike cancel(), a final result from this attempt is still valid.
    func finish() { onMain { $0.finishInternal(token: $0.attempt.generation) } }

    /// Invalidates permission replies and late results before releasing audio.
    func cancel() { onMain { $0.cancelInternal(status: "Voice canceled.") } }

    /// Mute only output; an explicit on-device recognition attempt keeps running.
    func stopReadback() {
        onMain { control in
            control.synthesizer.stopSpeaking(at: .immediate)
            control.speakingUtterance = nil
            control.speakingGeneration = nil
        }
    }

    /// Readback is an explicit action and never starts or resumes listening.
    func speak(_ text: String, localeIdentifier: String) {
        onMain { control in
            control.cancelInternal(status: "Voice idle.")
            guard UIApplication.shared.applicationState != .background else { return }
            guard let text = VoiceTranscriptPolicy.final(text) else {
                control.status = "Readback requires 1–160 plain text characters."; return
            }
            guard let voice = AVSpeechSynthesisVoice(language: localeIdentifier) else {
                control.status = "No readback voice is available for that language."; return
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            control.speakingUtterance = utterance
            control.speakingGeneration = control.attempt.generation
            control.status = "Reading aloud. Microphone is off."
            control.synthesizer.speak(utterance)
        }
    }

    private func onMain(_ body: @escaping (LocalVoiceControl) -> Void) {
        if Thread.isMainThread { body(self) }
        else { DispatchQueue.main.async { [weak self] in if let self { body(self) } } }
    }

    private func startInternal(localeIdentifier: String) {
        cancelInternal(status: "Requesting voice permissions…")
        guard UIApplication.shared.applicationState != .background else {
            status = "Open FEEL before starting a voice command."; return
        }
        let token = attempt.begin()
        // Explicit consent comes first; no network-recognition fallback is used.
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.authorizing(token) else { return }
                guard authorization == .authorized else {
                    self.cancelInternal(status: "Speech permission is unavailable. Use the on-screen controls or change permission in Settings.")
                    return
                }
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
                      recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
                    self.cancelInternal(status: "On-device speech is unavailable for this language/device. Use the on-screen controls.")
                    return
                }
                self.recognizer = recognizer
                // Kept for the iOS 16 deployment target; deprecated, not removed,
                // in iOS 17. This callback is not guaranteed to arrive on main.
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.authorizing(token) else { return }
                        guard granted else {
                            self.cancelInternal(status: "Microphone permission denied. Use the on-screen controls or change permission in Settings.")
                            return
                        }
                        self.beginRecording(token: token)
                    }
                }
            }
        }
    }

    private func authorizing(_ token: UInt64) -> Bool {
        attempt.authorizing(token) && UIApplication.shared.applicationState != .background
    }

    private func beginRecording(token: UInt64) {
        guard authorizing(token), let recognizer,
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            cancelInternal(status: "On-device speech became unavailable. Tap Speak command to retry."); return
        }
        // stopSpeaking(.immediate) was called before asking permission. Never
        // open the microphone if the synthesizer is still reporting speech.
        guard !synthesizer.isSpeaking else {
            cancelInternal(status: "Readback is stopping. Tap Speak command again when it is silent."); return
        }
        onCaptureWillStart?()
        guard authorizing(token) else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true, options: [])
            audioSessionActive = true
            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                cancelInternal(status: "No microphone input is available."); return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = false
            request.taskHint = .confirmation
            self.request = request
            let pipe = VoiceAudioPipe(request)
            self.pipe = pipe
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in pipe.append(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            guard attempt.listen(token) else { cancelInternal(status: "Voice canceled."); return }
            isListening = true; canFinish = true
            status = "Listening on device, up to 10 seconds. Tap Finish when done."
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let failed = error != nil
                DispatchQueue.main.async { [weak self] in
                    self?.receive(text: text, final: final, failed: failed, token: token)
                }
            }
            let deadline = DispatchWorkItem { [weak self] in self?.finishInternal(token: token) }
            captureDeadline = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: deadline)
        } catch {
            cancelInternal(status: "Could not start microphone capture. Use the on-screen controls or try again.")
        }
    }

    private func finishInternal(token: UInt64) {
        guard attempt.finish(token) else { return }
        captureDeadline?.cancel(); captureDeadline = nil
        stopCapture()
        request?.endAudio()
        status = "Microphone off. Waiting briefly for the final command…"
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.attempt.generation == token, self.attempt.phase == .finishing else { return }
            self.cancelInternal(status: "No final command arrived. Tap Speak command to retry.")
        }
        finalDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: deadline)
    }

    private func receive(text: String?, final: Bool, failed: Bool, token: UInt64) {
        guard attempt.acceptsResult(token), UIApplication.shared.applicationState != .background else { return }
        guard !failed else {
            cancelInternal(status: "On-device recognition failed. No command was executed."); return
        }
        guard let text else { return }
        transcript = VoiceTranscriptPolicy.display(text)
        guard VoiceTranscriptPolicy.isWithinLimit(text) else {
            cancelInternal(status: "Command exceeded 160 characters. Please try a shorter command."); return
        }
        guard final else { return } // Partial transcripts are display-only.
        guard let command = VoiceTranscriptPolicy.final(text) else {
            cancelInternal(status: "No valid final command was heard. Please try again."); return
        }
        guard attempt.complete(token) else { return } // Invalidate before invoking app code.
        releaseRecognition()
        transcript = command
        status = "Final command received. Microphone is off."
        onFinalTranscript?(command)
    }

    private func stopCapture() {
        pipe?.close(); pipe = nil
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine = nil
        isListening = false; canFinish = false
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
    }

    private func releaseRecognition() {
        captureDeadline?.cancel(); captureDeadline = nil
        finalDeadline?.cancel(); finalDeadline = nil
        stopCapture()
        task?.cancel(); task = nil
        request = nil; recognizer = nil
    }

    private func cancelInternal(status: String) {
        attempt.cancel() // First: every subsequently delivered callback is stale.
        releaseRecognition()
        speakingUtterance = nil; speakingGeneration = nil
        synthesizer.stopSpeaking(at: .immediate)
        transcript = ""
        self.status = status
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishReadback(utterance)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishReadback(utterance)
    }
    private func finishReadback(_ utterance: AVSpeechUtterance) {
        onMain { control in
            guard control.speakingUtterance === utterance,
                  control.speakingGeneration == control.attempt.generation else { return }
            control.speakingUtterance = nil; control.speakingGeneration = nil
            control.status = "Readback finished. Microphone is off."
        }
    }
}
