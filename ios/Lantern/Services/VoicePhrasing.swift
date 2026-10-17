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
        let metres = max(1, Int(distance.rounded()))
        let side: String
        switch abs(bearingDegrees) {
        case ...15: side = "ahead"
        case ...60: side = bearingDegrees < 0 ? "ahead to your left" : "ahead to your right"
        case ...120: side = bearingDegrees < 0 ? "to your left" : "to your right"
        default: side = "behind you"
        }
        return "Last time the \(label) was about \(metres) \(metres == 1 ? "meter" : "meters") \(side). Pins point there. Say photo to check again."
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
