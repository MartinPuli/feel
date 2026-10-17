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
final class WhereIsService {
    static let timeout: TimeInterval = 12
    private let gateway: ChatGateway?
    private let model: String
    private let local: LocalWhereIsFinding?
    private var generation = 0
    private var task: URLSessionTask?

    init(gateway: ChatGateway?, model: String, local: LocalWhereIsFinding? = nil) { self.gateway = gateway; self.model = model; self.local = local }

    func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void) {
        generation += 1
        let id = generation
        task?.cancel(); task = nil
        guard let gateway, let body = try? WhereIs.requestBody(model: model, question: "Where is the \(thing)?", jpegBase64: snapshot.jpegBase64) else {
            fallBack(thing, snapshot: snapshot, id: id, completion: completion); return
        }
        task = gateway.complete(body: body, timeout: Self.timeout) { [weak self] result in
            guard let self, self.generation == id else { return }
            self.task = nil
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
    func cancel() { generation += 1; task?.cancel(); task = nil }

    static func outcome(of result: Result<String, Error>, thing: String, snapshot: FrameSnapshot) -> WhereIsOutcome {
        guard case .success(let text) = result, let answer = try? WhereIs.parse(text) else { return .failed }
        guard answer.found else { return .notVisible }
        guard let target = WhereIsPlacement.place(answer: answer, snapshot: snapshot) else { return .noDepth }
        // The user's words name the target; the model's label is never spoken back.
        return .placed(HeldTarget(position: target.position, label: thing, worldEpoch: target.worldEpoch, setAt: target.setAt))
    }
}
