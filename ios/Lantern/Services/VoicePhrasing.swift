import Foundation
import FeelCore

/// Spoken observations use the same freshness and range rules as tactile output.
enum VoicePhrasing {
    static func observation(_ target: TargetObservation, finder: FinderMode, now: TimeInterval) -> String? {
        guard target.valid(at: now), finder != .none else { return nil }
        let object: String
        switch finder {
        case .none: return nil
        case .door: object = "A possible door"
        case .exit: object = "An exit sign"
        case .chair: object = "A chair"
        case .person: object = "A person"
        case .teammate: object = "Your teammate"
        case .barcode: object = "A barcode"
        }
        return "\(object) was \(distanceText(target.distance)) \(side(target.bearingDegrees))."
    }
    /// A Where-is target keeps the user's own name for the thing.
    static func observation(_ target: TargetObservation, named label: String, now: TimeInterval) -> String? {
        guard target.valid(at: now) else { return nil }
        return "The \(label) was \(distanceText(target.distance)) \(side(target.bearingDegrees))."
    }
    /// The cue for a place recalled from room memory: a past sighting with a rough distance, the pins doing the
    /// pointing, and the way to check with the camera. Never a present-tense claim.
    static func remembered(_ label: String, bearingDegrees: Double, distance: Double) -> String {
        "Last time the \(label) was \(roughPlace(bearingDegrees: bearingDegrees, distance: distance)). Pins point there. Say photo to check again."
    }
    /// The cue when the phone leads the way to a remembered place one progress point at a time (lead_me). Still a past
    /// sighting; the pins point to the next point of the way, which is a suggested direction, never a clear path.
    static func leading(_ label: String, bearingDegrees: Double, distance: Double) -> String {
        "Leading you to the \(label). Last time it was \(roughPlace(bearingDegrees: bearingDegrees, distance: distance)). Pins point the way, one point at a time."
    }
    private static func roughPlace(bearingDegrees: Double, distance: Double) -> String {
        let metres = max(1, Int(distance.rounded()))
        let side: String
        switch abs(bearingDegrees) {
        case ...15: side = "ahead"
        case ...60: side = bearingDegrees < 0 ? "ahead to your left" : "ahead to your right"
        case ...120: side = bearingDegrees < 0 ? "to your left" : "to your right"
        default: side = "behind you"
        }
        return "about \(metres) \(metres == 1 ? "meter" : "meters") \(side)"
    }
    private static func distanceText(_ distance: Double) -> String {
        let rounded = (distance * 10).rounded() / 10
        let text = rounded == rounded.rounded()
            ? String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), rounded)
            : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        return "\(text) \(rounded == 1 ? "meter" : "meters")"
    }
    private static func side(_ bearing: Double) -> String {
        abs(bearing) <= 15 ? "ahead" : bearing < 0 ? "to your left" : "to your right"
    }
}


extension VoicePhrasing {
    static let describePrompt = """
    You help a blind person with one photo from a chest-mounted camera. Say what is directly ahead in one plain sentence of at most 14 words, nearest things first, with a rough distance in meters when it is obvious. Name objects and people as "a person". If nothing is identifiable say so. No preamble, no advice, no safety claims.
    """

    /// Chat body for the gateway: the describe prompt plus the photo, same shape as the Where-is request.
    static func describeBody(model: String, jpegBase64: String) throws -> Data {
        // Low reasoning effort: measured through the gateway, about 2.7 s and 50 completion tokens for a
        // one-sentence description, against 3.5 s or more at the default effort.
        let body: [String: Any] = ["model": model, "max_completion_tokens": 400, "reasoning_effort": "low", "messages": [
            ["role": "system", "content": describePrompt],
            ["role": "user", "content": [["type": "text", "text": "What is in front of me?"],
                                         ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpegBase64)"]]]]]]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The first sentence of a reply, trimmed; nil when the reply is empty.
    static func oneSentence(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            let first = trimmed[...end].trimmingCharacters(in: .whitespaces)
            return first.count >= 8 ? String(first) : trimmed
        }
        return trimmed
    }

    /// What the pins show right now, for the assistant's status: nearest range per side. Columns 0-1 are
    /// left, 2-4 ahead, 5-6 right. "nothing within 4 m" is what the sensor reports, never a clear path.
    static func obstacles(_ distances: [Double?]) -> String {
        guard distances.count == 7 else { return "unknown" }
        func nearest(_ columns: ClosedRange<Int>) -> String {
            let ranges = columns.compactMap { distances[$0] }.filter { $0.isFinite && $0 > 0 && $0 <= 4 }
            guard let value = ranges.min() else { return "nothing within 4 m" }
            return String(format: "%.1f m", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return "ahead \(nearest(2...4)), left \(nearest(0...1)), right \(nearest(5...6))"
    }
}
