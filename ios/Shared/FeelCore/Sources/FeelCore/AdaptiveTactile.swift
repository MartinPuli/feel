import Foundation

public enum AdaptiveProfile: String, Codable, CaseIterable, Sendable {
    case standard, reduced, automatic
}

/// Gates target highlighting only. The sequence and all seven obstacle/target
/// bands are always preserved. This is a command policy, not a model of sensation.
///
/// Reduced mode starts quiet for 1.8 s, enables the effective highlight for 0.6 s,
/// and repeats every 2.4 s. At the off boundary it emits 255, so firmware does not
/// start a second 600 ms tap. Session/profile/target identity changes start a new
/// quiet interval. Losing/reacquiring a target does too; repeated changes therefore
/// postpone taps instead of restarting a continuous firmware tap dip.
///
/// Automatic mode enters reduced immediately on any band 1. It leaves reduced only
/// after 2.4 continuous seconds without band 1, preventing near/far flicker from
/// repeatedly switching back into standard. Other column band changes do not reset
/// a stable target's clock. Continue calling at the normal packet cadence.
public struct AdaptiveTactileController: Sendable {
    private struct Target: Equatable, Sendable {
        let column: UInt8
        let band: UInt8
    }
    private var session: String?
    private var profile: AdaptiveProfile?
    private var target: Target?
    private var previousTime: Double?
    private var quietEpoch: Double?
    private var farSince: Double?
    private var reduced = false

    public init() {}

    /// Discard history; the next reduced packet starts with a quiet interval.
    public mutating func reset() {
        session = nil
        profile = nil
        target = nil
        previousTime = nil
        quietEpoch = nil
        farSince = nil
        reduced = false
    }

    public mutating func apply(packet: FeelPacket, profile: AdaptiveProfile, session: String, now: Double) -> FeelPacket {
        guard !session.isEmpty, now.isFinite, now >= 0,
              previousTime.map({ now >= $0 }) ?? true else {
            reset()
            return withHighlight(255, packet: packet)
        }
        previousTime = now
        let effective = packet.effectiveHighlight
        let nextTarget: Target? = effective < 7 ? Target(column: effective, band: packet.bands[Int(effective)]) : nil
        let near = packet.bands.contains(1)
        let identityChanged = self.session != session || self.profile != profile

        if identityChanged {
            self.session = session
            self.profile = profile
            reduced = profile == .reduced || (profile == .automatic && near)
            farSince = nil
            quietEpoch = now
        } else if profile == .automatic {
            if near {
                farSince = nil
                if !reduced {
                    reduced = true
                    quietEpoch = now
                }
            } else if reduced {
                if let farSince {
                    if now - farSince >= 2.4 {
                        reduced = false
                        self.farSince = nil
                        quietEpoch = now
                    }
                } else {
                    farSince = now
                }
            }
        }
        if target != nextTarget {
            target = nextTarget
            quietEpoch = now
        }
        guard reduced else { return withHighlight(effective, packet: packet) }
        guard effective < 7, let quietEpoch else { return withHighlight(255, packet: packet) }
        var phase = (now - quietEpoch).truncatingRemainder(dividingBy: 2.4)
        // Normalize nanosecond-scale subtraction roundoff at decimal boundaries
        // (for example an epoch of 100 s plus the exact 1.8 s quiet duration).
        if abs(phase - 1.8) < 1e-9 { phase = 1.8 }
        if abs(phase - 2.4) < 1e-9 { phase = 0 }
        return withHighlight(phase >= 1.8 ? effective : 255, packet: packet)
    }

    private func withHighlight(_ highlight: UInt8, packet: FeelPacket) -> FeelPacket {
        // FeelPacket's validated immutable fields guarantee this reconstruction.
        try! FeelPacket(sequence: packet.sequence, bands: packet.bands, highlight: highlight)
    }
}
