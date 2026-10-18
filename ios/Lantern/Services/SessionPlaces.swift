import Foundation
import Combine
import FeelCore

/// Explicit bookmarks belong to one continuous AR world. Room-tag memory remains separate.
/// Mutation and callbacks are confined to the main queue.
final class SessionPlaces: ObservableObject {
    @Published private(set) var memory = SpatialMemoryManager()
    @Published private(set) var message = "Start the camera to remember a place."
    @Published private(set) var guidance: MemoryGuidance?
    private var worldEpoch: Int?
    private var sample: MemoryPose?
    private let now: () -> Double
    init(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) { self.now = now }
    var hasFreshContext: Bool { (try? requireFreshContext()) != nil }
    var active: Bool { memory.activeID != nil }

    func observe(pose: CameraPose, worldEpoch: Int, timestamp: Double, tracking: Bool) {
        if self.worldEpoch != worldEpoch || memory.session == nil {
            memory.end()
            try? memory.begin(session: UUID().uuidString)
            self.worldEpoch = worldEpoch
            message = "New camera session. Places from the previous session were cleared."
        }
        guard let session = memory.session else { return }
        sample = MemoryPose(session: session, pose: pose, timestamp: timestamp, tracking: tracking)
    }
    func invalidate() { sample = nil; guidance = nil }
    func restore(_ archive: PersistentMemoryArchive, worldEpoch: Int) throws {
        end()
        try memory.begin(session: UUID().uuidString)
        self.worldEpoch = worldEpoch
        try memory.restore(archive: archive, session: memory.session!)
        message = "Saved places restored. Choose Recall when ready."
    }
    func end() { memory.end(); sample = nil; worldEpoch = nil; guidance = nil }
    func stop() { memory.stopGuidance(); guidance = nil; message = "Place guidance stopped." }

    @discardableResult func remember(_ name: String) -> [String: Any] {
        action {
            guard let sample else { throw SpatialMemoryError.noSession }
            _ = try memory.remember(name: name, sample: sample, now: now())
            return "Remembered \(name)."
        }
    }
    @discardableResult func recall(_ id: String) -> [String: Any] {
        action { try requireFreshContext(); try memory.recall(id: id); return "Pointing toward the remembered place. This does not establish a clear path." }
    }
    @discardableResult func rename(_ id: String, to name: String) -> [String: Any] {
        action { try memory.rename(id: id, name: name); return "Place renamed." }
    }
    @discardableResult func delete(_ id: String) -> [String: Any] {
        action { try memory.delete(id: id); return "Place deleted." }
    }
    @discardableResult func setReturnPoint() -> [String: Any] {
        action {
            guard let sample else { throw SpatialMemoryError.noSession }
            try memory.setReturnPoint(sample: sample, now: now())
            return "Return point saved for this camera session."
        }
    }
    @discardableResult func returnToPoint() -> [String: Any] {
        action { try requireFreshContext(); try memory.returnToStart(); return "Pointing toward your return point." }
    }
    var status: [String: Any] {
        ["places": memory.bookmarks.map { ["id": $0.id, "name": $0.name] },
         "active_id": memory.activeID ?? "", "has_return_point": memory.returnPoint != nil,
         "session": memory.session ?? "", "guidance": guidance?.state.rawValue ?? "idle",
         "note": "Places belong to this camera session. A direction is not a clear route."]
    }
    func encode(sequence: UInt8, distances: [Double?], calibrated: Bool, at time: Double) -> EncoderOutput? {
        guard active else { return nil }
        guard let sample else {
            guidance = nil
            return EncoderOutput(packet: .neutral(sequence: sequence), state: .trackingLost)
        }
        let result = memory.encode(sequence: sequence, sample: sample, now: time, distances: distances, floorCalibrated: calibrated)
        guidance = result.guidance
        if result.guidance.state == .arrived {
            memory.stopGuidance(); message = "You reached the remembered place."
        }
        return result.output
    }
    private func requireFreshContext() throws {
        guard let sample else { throw SpatialMemoryError.noSession }
        let state = memory.guidance(sample: sample, now: now()).state
        if [.trackingLost, .stalePose, .invalidPose, .sessionMismatch, .sessionUnavailable].contains(state) {
            throw SpatialMemoryError.invalidContext(state)
        }
    }
    private func action(_ body: () throws -> String) -> [String: Any] {
        do { message = try body(); return ["status": message] }
        catch { message = String(describing: error); return ["error": message] }
    }
}
