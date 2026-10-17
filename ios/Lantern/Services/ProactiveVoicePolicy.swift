import Foundation
import FeelCore

/// Deterministic notification policy. The caller supplies only fresh, calibrated live frames.
struct ProactiveVoicePolicy {
    enum Kind: String { case target, obstacle }
    enum Side: String { case left, ahead, right }

    struct Notice: Equatable {
        let text: String
        let key: String
        let kind: Kind
        let side: Side
        let sceneBound = true
        fileprivate let distance: Double
        fileprivate let finder: FinderMode

        /// A queued spoken observation must still describe the current scene.
        func isSupported(target: TargetObservation?, finder: FinderMode, distances: [Double?], now: TimeInterval) -> Bool {
            guard now.isFinite else { return false }
            switch kind {
            case .target:
                guard finder == self.finder, let target, target.valid(at: now) else { return false }
                return ProactiveVoicePolicy.side(for: target.bearingDegrees) == side && abs(target.distance - distance) < 0.5
            case .obstacle:
                guard let obstacle = ProactiveVoicePolicy.nearestObstacle(distances), obstacle.distance <= 0.9 else { return false }
                return obstacle.side == side && abs(obstacle.distance - distance) < 0.4
            }
        }
    }

    private struct Observation {
        let distance: Double
        let side: Side
    }
    private enum Reason { case initial, sideChanged, closer, farther }
    private struct Candidate {
        let key: String
        let since: TimeInterval
        let side: Side
        let reason: Reason
    }

    private var targetBaseline: Observation?
    private var obstacleBaseline: Observation?
    private var targetCandidate: Candidate?
    private var obstacleCandidate: Candidate?
    private var targetAbsentSince: TimeInterval?
    private var obstacleAbsentSince: TimeInterval?
    private var selectedFinder: FinderMode = .none
    private var lastAcknowledgedAt: TimeInterval?
    private var lastTime: TimeInterval?
    private var lastProposal: Notice?
    private var nextKey: UInt64 = 0

    mutating func reset() {
        // Preserve the key sequence so an acknowledgement from an old scene cannot match a new one.
        let sequence = nextKey
        self = Self()
        nextKey = sequence
    }

    mutating func propose(target: TargetObservation?, finder: FinderMode, distances: [Double?], now: TimeInterval) -> Notice? {
        lastProposal = nil
        guard now.isFinite else { return nil }
        if let lastTime, now < lastTime { reset() }
        lastTime = now
        if finder != selectedFinder {
            selectedFinder = finder
            targetBaseline = nil; targetCandidate = nil; targetAbsentSince = nil
        }

        let currentTarget = finder != .none ? target.flatMap { $0.valid(at: now) ? $0 : nil } : nil
        if let currentTarget {
            if elapsed(since: targetAbsentSince, now: now, atLeast: 0.6) { targetBaseline = nil }
            targetAbsentSince = nil
            let observation = Observation(distance: currentTarget.distance, side: Self.side(for: currentTarget.bearingDegrees))
            targetCandidate = candidate(existing: targetCandidate, kind: .target, observation: observation,
                                        reason: reason(observation, baseline: targetBaseline, threshold: 0.5, allowsReceding: true), now: now)
        } else {
            targetCandidate = nil
            if targetAbsentSince == nil { targetAbsentSince = now }
            if elapsed(since: targetAbsentSince, now: now, atLeast: 0.6) { targetBaseline = nil }
        }

        let obstacle = Self.nearestObstacle(distances)
        if let obstacle {
            if elapsed(since: obstacleAbsentSince, now: now, atLeast: 2) { obstacleBaseline = nil }
            obstacleAbsentSince = nil
            let change = obstacle.distance <= 0.9
                ? reason(obstacle, baseline: obstacleBaseline, threshold: 0.4, allowsReceding: false) : nil
            obstacleCandidate = candidate(existing: obstacleCandidate, kind: .obstacle, observation: obstacle, reason: change, now: now)
        } else {
            obstacleCandidate = nil
            if obstacleAbsentSince == nil { obstacleAbsentSince = now }
            if elapsed(since: obstacleAbsentSince, now: now, atLeast: 2) { obstacleBaseline = nil }
        }

        if let lastAcknowledgedAt, !elapsed(since: lastAcknowledgedAt, now: now, atLeast: 8) { return nil }
        // A qualifying close obstacle has priority, including its stability interval.
        if let candidate = obstacleCandidate, let obstacle {
            guard elapsed(since: candidate.since, now: now, atLeast: 0.8) else { return nil }
            let distance = obstacle.distance < 0.3 ? "less than 0.3" : "about " + String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), obstacle.distance)
            let side = obstacle.side == .ahead ? "ahead" : "to your \(obstacle.side.rawValue)"
            return remember(Notice(text: "An obstacle was \(distance) meters \(side).", key: candidate.key,
                                   kind: .obstacle, side: obstacle.side, distance: obstacle.distance, finder: .none))
        }
        if let candidate = targetCandidate, let currentTarget,
           elapsed(since: candidate.since, now: now, atLeast: 0.8),
           let text = VoicePhrasing.observation(currentTarget, finder: finder, now: now) {
            return remember(Notice(text: text, key: candidate.key, kind: .target, side: candidate.side,
                                   distance: currentTarget.distance, finder: finder))
        }
        return nil
    }

    /// Call only after the voice session accepts this exact proposal for delivery.
    mutating func acknowledge(_ notice: Notice, now: TimeInterval) {
        guard now.isFinite, let lastTime, now >= lastTime, lastProposal == notice else { return }
        let observation = Observation(distance: notice.distance, side: notice.side)
        switch notice.kind {
        case .target:
            guard targetCandidate?.key == notice.key else { return }
            targetBaseline = observation; targetCandidate = nil
        case .obstacle:
            guard obstacleCandidate?.key == notice.key else { return }
            obstacleBaseline = observation; obstacleCandidate = nil
        }
        lastAcknowledgedAt = now
        lastProposal = nil
    }

    private mutating func remember(_ notice: Notice) -> Notice {
        lastProposal = notice
        return notice
    }

    private mutating func candidate(existing: Candidate?, kind: Kind, observation: Observation, reason: Reason?, now: TimeInterval) -> Candidate? {
        guard let reason else { return nil }
        if let existing, existing.side == observation.side, existing.reason == reason { return existing }
        nextKey &+= 1
        return Candidate(key: "\(kind.rawValue)-\(nextKey)", since: now, side: observation.side, reason: reason)
    }

    private func reason(_ observation: Observation, baseline: Observation?, threshold: Double, allowsReceding: Bool) -> Reason? {
        guard let baseline else { return .initial }
        if observation.side != baseline.side { return .sideChanged }
        if baseline.distance - observation.distance + 1e-9 >= threshold { return .closer }
        if allowsReceding && observation.distance - baseline.distance + 1e-9 >= threshold { return .farther }
        return nil
    }

    private func elapsed(since start: TimeInterval?, now: TimeInterval, atLeast duration: TimeInterval) -> Bool {
        guard let start else { return false }
        return now - start + 1e-9 >= duration
    }

    private static func side(for bearing: Double) -> Side {
        abs(bearing) <= 15 ? .ahead : bearing < 0 ? .left : .right
    }

    private static func nearestObstacle(_ distances: [Double?]) -> Observation? {
        guard distances.count == 7 else { return nil }
        let nearest = distances.enumerated().compactMap { column, distance -> (Int, Double)? in
            guard let distance, distance.isFinite, distance > 0, distance <= 1.6 else { return nil }
            return (column, distance)
        }.min { lhs, rhs in lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1 }
        guard let (column, distance) = nearest else { return nil }
        let bearing = -45 + (Double(column) + 0.5) * 90 / 7
        return Observation(distance: distance, side: side(for: bearing))
    }
}
