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
        let rounded = (target.distance * 10).rounded() / 10
        let distance = rounded == rounded.rounded()
            ? String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), rounded)
            : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        let unit = rounded == 1 ? "meter" : "meters"
        let side = abs(target.bearingDegrees) <= 10 ? "ahead" : target.bearingDegrees < 0 ? "to your left" : "to your right"
        return "\(object) was \(distance) \(unit) \(side)."
    }
}
