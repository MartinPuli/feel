import Foundation
import FeelCore

enum WhereIsOutcome: Equatable {
    case placed(HeldTarget)   // held in world coordinates; the puck points at it from now on
    case notVisible           // the model did not see it in the photo
    case noDepth              // seen, but no usable LiDAR depth at that spot (glass, beyond range)
    case unsupported          // on-device only: the fixed vocabulary has nothing for the thing
    case failed               // offline, timeout, HTTP error or a malformed reply
}

/// One Where-is lookup: Chalk first (photo + question through the gateway, strict parse, LiDAR placement);
/// without Chalk, or when it cannot answer, the phone's own detector on the same photo.
/// A newer request supersedes an older one; a late answer to a superseded request is dropped.
/// Chalk gets one absolute deadline: an answer after it is dropped and the local finder answers instead.
final class WhereIsService {
    private let gateway: ChatGateway?
    private let model: String
    private let local: LocalWhereIsFinding?
    private let deadline: TimeInterval
    private var generation = 0
    private var task: URLSessionTask?
    private var expiry: DispatchWorkItem?

    init(gateway: ChatGateway?, model: String, local: LocalWhereIsFinding? = nil, deadline: TimeInterval = WhereIs.deadline) {
        self.gateway = gateway; self.model = model; self.local = local; self.deadline = deadline
    }

    func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void) {
        cancel()
        let id = generation
        guard let gateway, let body = try? WhereIs.requestBody(model: model, question: "Where is the \(thing)?", jpegBase64: snapshot.jpegBase64) else {
            fallBack(thing, snapshot: snapshot, id: id, completion: completion); return
        }
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id else { return }
            self.expiry = nil; self.task?.cancel(); self.task = nil
            self.fallBack(thing, snapshot: snapshot, id: id, completion: completion)
        }
        self.expiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline, execute: expiry)
        task = gateway.complete(body: body, timeout: deadline) { [weak self] result in
            guard let self, self.generation == id, let pending = self.expiry else { return }
            pending.cancel(); self.expiry = nil; self.task = nil
            let outcome = Self.outcome(of: result, thing: thing, snapshot: snapshot)
            if case .failed = outcome { self.fallBack(thing, snapshot: snapshot, id: id, completion: completion) } else { completion(outcome) }
        }
    }
    private func fallBack(_ thing: String, snapshot: FrameSnapshot, id: Int, completion: @escaping (WhereIsOutcome) -> Void) {
        guard let local else { completion(.failed); return }
        local.find(thing, snapshot: snapshot) { [weak self] outcome in
            guard let self, self.generation == id else { return }
            completion(outcome)
        }
    }
    func cancel() { generation += 1; expiry?.cancel(); expiry = nil; task?.cancel(); task = nil }

    static func outcome(of result: Result<String, Error>, thing: String, snapshot: FrameSnapshot) -> WhereIsOutcome {
        guard case .success(let text) = result, let answer = try? WhereIs.parse(text) else { return .failed }
        guard answer.found else { return .notVisible }
        guard let target = WhereIsPlacement.place(answer: answer, snapshot: snapshot) else { return .noDepth }
        // The user's words name the target; the model's label is never spoken back.
        return .placed(HeldTarget(position: target.position, label: thing, worldEpoch: target.worldEpoch, setAt: target.setAt))
    }
}
