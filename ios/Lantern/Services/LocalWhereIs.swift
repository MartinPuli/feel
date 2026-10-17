import Foundation
import FeelCore

protocol LocalWhereIsFinding {
    func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void)
}

/// The phone's own answer to "where is X?": the fixed on-device vocabulary, the detector on the same photo,
/// the best detection placed with LiDAR under the user's own words. Completion on the main queue.
final class LocalWhereIs: LocalWhereIsFinding {
    /// Runs one query on a JPEG; nil detections mean the detector cannot run that query here (no Core ML weights).
    typealias Detect = (LocalQuery, Data, @escaping ([ImageDetection]?) -> Void) -> Void
    private let detect: Detect
    init(detect: @escaping Detect) { self.detect = detect }

    func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void) {
        guard let query = LocalVocabulary.query(for: thing) else { completion(.unsupported); return }
        guard let jpeg = Data(base64Encoded: snapshot.jpegBase64) else { completion(.failed); return }
        detect(query, jpeg) { detections in
            let outcome = detections.map { Self.outcome(of: $0, thing: thing, snapshot: snapshot) } ?? .unsupported
            if Thread.isMainThread { completion(outcome) } else { DispatchQueue.main.async { completion(outcome) } }
        }
    }
    static func outcome(of detections: [ImageDetection], thing: String, snapshot: FrameSnapshot) -> WhereIsOutcome {
        guard let best = detections.max(by: { $0.confidence < $1.confidence }) else { return .notVisible }
        let box = NormalizedBox(bottomLeftX: Double(best.box.minX), y: Double(best.box.minY), width: Double(best.box.width), height: Double(best.box.height))
        let answer = WhereIsAnswer(found: true, label: thing, box: box, confidence: best.confidence)
        guard let target = WhereIsPlacement.place(answer: answer, snapshot: snapshot) else { return .noDepth }
        return .placed(target)
    }
}
