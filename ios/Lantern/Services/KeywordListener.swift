import Foundation
import AVFoundation
import Speech
import FeelCore

/// Hears the one target word said with a V sign ("exit", "door" …). Recognition runs on the
/// phone only; audio is never sent anywhere. When the assistant is running, its microphone
/// is borrowed and its uplink muted for the window, so it neither hears nor answers the word.
/// All calls and callbacks are on the main thread.
final class KeywordListener {
    var onWord: ((TargetWord) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private weak var voice: RealtimeVoiceSession?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    private var borrowed = false
    private var generation = 0

    init(voice: RealtimeVoiceSession) { self.voice = voice }

    var isListening: Bool { request != nil }

    /// Whether a word can be heard right now: permissions granted and on-device recognition present.
    var isAvailable: Bool {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return false }
        return voice?.isActive == true || AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Asks for speech and microphone permission ahead of the first V sign.
    func prepare() {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined { SFSpeechRecognizer.requestAuthorization { _ in } }
        if AVAudioSession.sharedInstance().recordPermission == .undetermined { AVAudioSession.sharedInstance().requestRecordPermission { _ in } }
    }

    @discardableResult func start() -> Bool {
        guard request == nil else { return true }
        guard isAvailable, let recognizer else { prepare(); return false }
        generation += 1
        let id = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = TargetWord.hints
        request.taskHint = .search
        self.request = request
        var delivered = false
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString, let word = TargetWord.match(text) else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == id, !delivered else { return }
                delivered = true
                self.onWord?(word)
            }
        }
        if voice?.borrowMicrophone({ request.append($0) }) == true {
            borrowed = true
            return true
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw VoiceAudioError.unavailableInput }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            self.engine = engine
            return true
        } catch {
            stop()
            return false
        }
    }

    func stop() {
        generation += 1
        request?.endAudio(); task?.cancel()
        request = nil; task = nil
        if borrowed { voice?.borrowMicrophone(nil); borrowed = false }
        if let engine {
            engine.stop(); engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
