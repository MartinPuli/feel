import Foundation
import FeelCore

enum WhereIsOutcome: Equatable {
    case placed(HeldTarget)   // held in world coordinates; the puck points at it from now on
    case notVisible           // the model did not see it in the photo
    case noDepth              // seen, but no usable LiDAR depth at that spot (glass, beyond range)
    case failed               // offline, timeout, HTTP error or a malformed reply
}

/// One Where-is lookup: photo + question through the gateway, strict parse, LiDAR placement.
/// A newer request supersedes an older one; a late answer to a superseded request is dropped.
final class WhereIsService {
    static let timeout: TimeInterval = 20
    private let gateway: ChatGateway
    private let model: String
    private var generation = 0
    private var task: URLSessionTask?

    init(gateway: ChatGateway, model: String) { self.gateway = gateway; self.model = model }

    func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void) {
        generation += 1
        let id = generation
        task?.cancel(); task = nil
        guard let body = try? WhereIs.requestBody(model: model, question: "Where is the \(thing)?", jpegBase64: snapshot.jpegBase64) else {
            completion(.failed); return
        }
        task = gateway.complete(body: body, timeout: Self.timeout) { [weak self] result in
            guard let self, self.generation == id else { return }
            self.task = nil
            completion(Self.outcome(of: result, snapshot: snapshot))
        }
    }
    func cancel() { generation += 1; task?.cancel(); task = nil }

    static func outcome(of result: Result<String, Error>, snapshot: FrameSnapshot) -> WhereIsOutcome {
        guard case .success(let text) = result, let answer = try? WhereIs.parse(text) else { return .failed }
        guard answer.found else { return .notVisible }
        guard let target = WhereIsPlacement.place(answer: answer, snapshot: snapshot) else { return .noDepth }
        return .placed(target)
    }
}
