import Foundation

/// The single spoken word that names what to find after a V sign.
public enum TargetWord: String, CaseIterable, Sendable {
    case door, exit, chair, person, teammate

    private static let phrases: [(String, TargetWord)] = [
        ("exit sign", .exit), ("way out", .exit), ("exits", .exit), ("exit", .exit),
        ("doorway", .door), ("doors", .door), ("door", .door),
        ("chairs", .chair), ("chair", .chair), ("seat", .chair),
        ("teammate", .teammate), ("team mate", .teammate), ("partner", .teammate), ("buddy", .teammate),
        ("person", .person), ("people", .person), ("someone", .person), ("somebody", .person), ("human", .person)]

    /// Recognizer hints, so short single words are recognized reliably.
    public static var hints: [String] { phrases.map(\.0) }

    /// The earliest target word in a transcript, matched on whole words.
    public static func match(_ transcript: String) -> TargetWord? {
        let words = transcript.lowercased().split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return nil }
        let text = " " + words.joined(separator: " ") + " "
        var best: (index: String.Index, word: TargetWord)?
        for (phrase, word) in phrases {
            guard let range = text.range(of: " \(phrase) ") else { continue }
            if best == nil || range.lowerBound < best!.index { best = (range.lowerBound, word) }
        }
        return best?.word
    }

    public var plural: String {
        switch self { case .door: return "doors"; case .exit: return "exits"; case .chair: return "chairs"; case .person: return "people"; case .teammate: return "teammates" }
    }
}

/// One visible target the wearer could be guided to, ordered left to right.
public struct TargetChoice: Equatable, Sendable {
    public let bearingDegrees: Double, distance: Double
    public init(bearingDegrees: Double, distance: Double) { self.bearingDegrees=bearingDegrees; self.distance=distance }

    public var spokenPlace: String {
        let side: String
        switch bearingDegrees {
        case ..<(-25): side = "left"
        case ..<(-8): side = "slightly left"
        case ...8: side = "ahead"
        case ...25: side = "slightly right"
        default: side = "right"
        }
        let metres = max(0.5, (distance * 2).rounded() / 2)
        return "\(side), about \(metres.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(metres)) : String(metres)) meters"
    }

    /// Question for the voice assistant when several targets are in view.
    public static func question(_ choices: [TargetChoice], word: TargetWord?) -> String {
        let noun = word?.plural ?? "targets"
        let options = choices.prefix(4).enumerated().map { "\($0.offset + 1): \($0.element.spokenPlace)" }.joined(separator: ". ")
        return "I see \(choices.count) \(noun). \(options). Which one?"
    }
}

public enum RequestSound: Equatable, Sendable { case listening, success, failure }

public enum RequestAction: Equatable, Sendable {
    case startListening, stopListening
    case sound(RequestSound)
    /// Switch the finder to this target.
    case select(TargetWord)
    /// Several targets are in view; ask the voice assistant to let the wearer choose.
    case ask([TargetChoice])
    /// Guide to this choice (index into the choices last passed to `tick`).
    case lock(Int)
    /// One target and a fresh route: start guidance (the arrow scheduler plays the first cue).
    case startGuidance
}

/// What happens after a V sign: listen briefly for a target word, switch to that target,
/// wait for it to be seen with a route, ask when several are in view, then start guidance.
/// Listening begins when the sign is first seen, so "[V] exit" spoken together still counts.
public struct DirectionRequest: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The sign is being held but has not fired yet.
        case preListening(since: Double)
        case listening(until: Double)
        case acquiring(since: Double, until: Double)
        case choosing(until: Double)
    }
    public var preListenSeconds = 1.5
    /// After the sign fires, how long to wait for a word.
    public var listenSeconds = 2.5
    /// After the word, how long the target has to appear with a route.
    public var acquireSeconds = 3.0
    public var chooseSeconds = 15.0
    public private(set) var phase: Phase = .idle
    public private(set) var heard: TargetWord?
    private var locked = false
    private var lockedAt = -Double.infinity
    private var choices: [TargetChoice] = []

    public init() {}

    public var isBusy: Bool { phase != .idle }
    public mutating func reset() { phase = .idle; heard = nil; locked = false; choices = [] }

    /// The hand sign is first seen (before the hold completes).
    public mutating func handBegan(now: Double) -> [RequestAction] {
        guard phase == .idle else { return [] }
        heard = nil; phase = .preListening(since: now)
        return [.startListening]
    }

    /// The hold completed.
    public mutating func signFired(now: Double, selected: TargetWord?) -> [RequestAction] {
        switch phase {
        case .preListening:
            if heard != nil { return resolve(now: now, selected: selected) }
            phase = .listening(until: now + listenSeconds)
            return [.sound(.listening)]
        case .idle:
            heard = nil; phase = .listening(until: now + listenSeconds)
            return [.startListening, .sound(.listening)]
        default:
            // A sign while choosing or acquiring restarts the request.
            reset(); heard = nil; phase = .listening(until: now + listenSeconds)
            return [.startListening, .sound(.listening)]
        }
    }

    /// The recognizer heard a target word.
    public mutating func heardWord(_ word: TargetWord, now: Double, selected: TargetWord?) -> [RequestAction] {
        switch phase {
        case .preListening: heard = word; return []
        case .listening: heard = word; return resolve(now: now, selected: selected)
        default: return []
        }
    }

    private mutating func resolve(now: Double, selected: TargetWord?) -> [RequestAction] {
        guard let target = heard ?? selected else { reset(); return [.stopListening, .sound(.failure)] }
        var actions: [RequestAction] = [.stopListening]
        if target != selected { actions.append(.select(target)); locked = false }
        heard = target
        phase = .acquiring(since: now, until: now + acquireSeconds)
        return actions
    }

    /// - Parameters:
    ///   - choices: distinct targets in view now, left to right.
    ///   - hintTime: timestamp of the latest route hint for the guided target, if any.
    ///   - lockedTarget: whether perception is already following one chosen target.
    public mutating func tick(now: Double, selected: TargetWord?, choices current: [TargetChoice], hintTime: Double?, lockedTarget: Bool, agentAvailable: Bool) -> [RequestAction] {
        switch phase {
        case .idle: return []
        case .preListening(let since):
            if now - since > preListenSeconds { reset(); return [.stopListening] }
            return []
        case .listening(let until):
            return now >= until ? resolve(now: now, selected: selected) : []
        case .choosing(let until):
            if now >= until { reset(); return [.sound(.failure)] }
            return []
        case .acquiring(let since, let until):
            let isLocked = locked || lockedTarget
            if !isLocked && current.count >= 2 {
                choices = current
                if agentAvailable { phase = .choosing(until: now + chooseSeconds); return [.ask(current)] }
                // No assistant: take the one most straight ahead.
                let ahead = current.indices.min { abs(current[$0].bearingDegrees) < abs(current[$1].bearingDegrees) }!
                locked = true; lockedAt = now
                return [.lock(ahead)]
            }
            let fresh = hintTime.map { $0 >= max(since, locked ? lockedAt : since) } ?? false
            if (current.count == 1 || isLocked) && fresh { reset(); return [.startGuidance] }
            if now >= until { reset(); return [.sound(.failure)] }
            return []
        }
    }

    /// The wearer picked option `index` (0-based) through the assistant.
    public mutating func chose(_ index: Int, now: Double) -> [RequestAction] {
        guard case .choosing = phase, choices.indices.contains(index) else { return [] }
        locked = true; lockedAt = now
        phase = .acquiring(since: now, until: now + acquireSeconds)
        return [.lock(index)]
    }
}
