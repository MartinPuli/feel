import XCTest
import FeelCore
@testable import Lantern

/// Shared doubles for the Where-is tests: a scripted on-device finder, a synthetic snapshot/frame, and a voice session fed by hand.
final class StubLocalFinder: LocalWhereIsFinding {
    var outcome: WhereIsOutcome = .notVisible
    private(set) var things: [String] = []
    func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void) { things.append(thing); completion(outcome) }
}

/// A 20×10 depth grid at 2 m with the given confidence; the JPEG is the bytes "ABC".
func makeSnapshot(confidence: UInt8 = 2, worldEpoch: Int = 1) -> FrameSnapshot {
    let width = 20, height = 10
    return FrameSnapshot(timestamp: 3, worldEpoch: worldEpoch, pose: .identity, intrinsics: CameraIntrinsics(fx: 10, fy: 10, cx: 10, cy: 5),
                         depth: DepthGrid(width: width, height: height, depths: Array(repeating: 2.0, count: width * height),
                                          confidence: Array(repeating: confidence, count: width * height)),
                         jpegBase64: "QUJD")
}
func makeFrame(worldEpoch: Int = 1, pose: CameraPose = .identity) -> PerceptionFrame {
    PerceptionFrame(epoch: 0, worldSession: "where-is-test-session", finderEpoch: 0, worldEpoch: worldEpoch, timestamp: 1, tracking: true,
                    distances: Array(repeating: nil, count: 7), target: nil, pose: pose, floorY: nil, mapID: nil, mapAnchorID: nil, relocalizing: false)
}

final class ScriptedVoiceToken: VoiceTokenFetching {
    private var completion: ((Result<String, Error>) -> Void)?
    func fetch(_ configuration: VoiceConfiguration, completion: @escaping (Result<String, Error>) -> Void) { self.completion = completion }
    func cancel() { completion = nil }
    func complete(_ result: Result<String, Error>) { completion?(result); completion = nil }
}
final class ScriptedVoiceTransport: VoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?
    private(set) var sent: [[String: Any]] = []
    func open(token: String) {}
    func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) { sent.append(event); completion(true) }
    func close() {}
    func emit(_ event: [String: Any]) { onEvent?(event) }
    /// Everything sent so far, as one JSON string, for "was this line spoken" checks.
    var json: String { (try? JSONSerialization.data(withJSONObject: sent)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
}
final class SilentVoiceAudio: VoiceAudioIO {
    var pendingPlayback = false
    var playedMilliseconds = 0
    func start(onInput: @escaping (Data) -> Void, onPlaybackDrained: @escaping () -> Void) throws {}
    func play(_ pcm: Data) throws {}
    func interruptPlayback() {}
    func stop() {}
}
/// The session greets on its own ("I'm here.") as soon as it is configured; answering that request unblocks later speech.
func acknowledgeOpeningGreeting(_ sent: [[String: Any]], emit: ([String: Any]) -> Void) {
    guard let request = sent.last(where: { ($0["type"] as? String) == "response.create" }),
          let metadata = (request["response"] as? [String: Any])?["metadata"] as? [String: Any],
          let id = metadata["feel_request_id"] as? String else { return }
    emit(["type": "response.created", "response": ["id": "greeting", "metadata": ["feel_request_id": id]]])
    emit(["type": "response.done", "response": ["id": "greeting", "status": "completed"]])
}

enum VoiceTestDoubles {
    /// A session that has connected and received its configuration, so announce() can speak.
    static func activeSession() -> (RealtimeVoiceSession, ScriptedVoiceTransport) {
        let token = ScriptedVoiceToken(), transport = ScriptedVoiceTransport()
        let configuration = VoiceConfiguration(endpoint: "https://voice.example/session", accessToken: String(repeating: "a", count: 32))
        let voice = RealtimeVoiceSession(tokenClient: token, audio: SilentVoiceAudio(), transportFactory: { transport },
                                         configuration: configuration, speaksLocally: false, requestPermission: { $0(true) })
        voice.start(); token.complete(.success("ephemeral"))
        transport.emit(["type": "session.created"]); transport.emit(["type": "session.updated"])
        acknowledgeOpeningGreeting(transport.sent, emit: transport.emit)
        return (voice, transport)
    }
}
