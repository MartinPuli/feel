import Foundation

public enum VoiceLanguage: String, Codable, CaseIterable, Sendable {
    case en, es
}

public enum VoiceFindMode: String, Codable, CaseIterable, Sendable {
    case obstacles, door, exit, chair, person, teammate, barcode
}

/// A single, explicit command. This type neither performs actions nor evaluates text.
public enum VoiceIntent: Equatable, Sendable, Encodable {
    case remember(String)
    case recall(String)
    case returnToPoint
    case stop
    case listPlaces
    case find(VoiceFindMode)

    private enum CodingKeys: String, CodingKey { case action, name, mode }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .remember(let name):
            try values.encode("remember", forKey: .action)
            try values.encode(name, forKey: .name)
        case .recall(let name):
            try values.encode("recall", forKey: .action)
            try values.encode(name, forKey: .name)
        case .returnToPoint: try values.encode("return", forKey: .action)
        case .stop: try values.encode("stop", forKey: .action)
        case .listPlaces: try values.encode("listPlaces", forKey: .action)
        case .find(let mode):
            try values.encode("find", forKey: .action)
            try values.encode(mode, forKey: .mode)
        }
    }
}

public enum VoiceIntentError: Error, Equatable, CustomStringConvertible {
    case unfinishedTranscript, invalidText, invalidName, compositeCommand, unknownCommand

    public var description: String {
        switch self {
        case .unfinishedTranscript: return "Wait for a final transcript before executing a command"
        case .invalidText: return "Use 1–160 characters without control characters or line breaks"
        case .invalidName: return "Use a place name of 1–40 characters without command separators"
        case .compositeCommand: return "Use one command at a time"
        case .unknownCommand: return "The complete text must match a supported command"
        }
    }
}

/// Deliberately bounded, deterministic grammar, intended only for typed commands or
/// a final transcript from an explicit push-to-talk interaction. Perception/OCR
/// text is not a command source. Keywords are case/diacritic insensitive; names
/// preserve case, accents, and internal spacing. The total bound is Unicode scalars,
/// preventing a single grapheme with unbounded combining marks from evading it.
///
/// English: remember NAME | recall NAME | return | stop | list places | find MODE.
/// Spanish: recuerda NAME | recupera NAME | vuelve | para | lista lugares | busca MODO.
/// No polite prefixes, partial matches, sentence punctuation, or multi-command
/// separators are accepted. Ordinary names such as “Bus stop” and “Bread and Butter”
/// remain names; an explicit “and stop” / “y para” clause is rejected.
public enum VoiceIntentParser {
    public static func parse(text: String, language: VoiceLanguage, isFinal: Bool) throws -> VoiceIntent {
        guard isFinal else { throw VoiceIntentError.unfinishedTranscript }
        guard !text.isEmpty, text.unicodeScalars.count <= 160,
              !text.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              }) else { throw VoiceIntentError.invalidText }
        let input = text.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { throw VoiceIntentError.invalidText }
        let tokens = input.split(whereSeparator: { $0.isWhitespace })
        let words = tokens.map { normalized(String($0)) }
        let remember = language == .en ? "remember" : "recuerda"
        let recall = language == .en ? "recall" : "recupera"
        let returnWord = language == .en ? "return" : "vuelve"
        let stop = language == .en ? "stop" : "para"
        let list = language == .en ? ["list", "places"] : ["lista", "lugares"]
        let find = language == .en ? "find" : "busca"

        if words == [returnWord] { return .returnToPoint }
        if words == [stop] { return .stop }
        if words == list { return .listPlaces }
        if words.first == find, words.count == 2, let mode = findMode(words[1], language: language) {
            return .find(mode)
        }
        guard let command = words.first, command == remember || command == recall else {
            throw VoiceIntentError.unknownCommand
        }
        guard let separator = input.firstIndex(where: { $0.isWhitespace }) else {
            throw VoiceIntentError.invalidName
        }
        let name = String(input[separator...]).trimmingCharacters(in: .whitespaces)
        guard (1...40).contains(name.count) else { throw VoiceIntentError.invalidName }
        // A separator cannot be silently absorbed into a remembered name while a
        // second instruction appears to succeed. Apostrophes and hyphens are fine.
        if name.contains(where: { ";|&,.!?:/\\".contains($0) }) {
            throw VoiceIntentError.compositeCommand
        }
        let nameWords = name.split(whereSeparator: { $0.isWhitespace }).map { normalized(String($0)) }
        let joins: Set<String> = ["and", "then", "also", "y", "luego", "despues"]
        let verbs: Set<String> = ["remember", "recall", "return", "stop", "list", "find",
                                  "recuerda", "recupera", "vuelve", "para", "lista", "busca"]
        if nameWords.count > 1 {
            for index in 0..<(nameWords.count - 1) where joins.contains(nameWords[index]) && verbs.contains(nameWords[index + 1]) {
                throw VoiceIntentError.compositeCommand
            }
        }
        return command == remember ? .remember(name) : .recall(name)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func findMode(_ word: String, language: VoiceLanguage) -> VoiceFindMode? {
        if language == .en { return VoiceFindMode(rawValue: word) }
        switch word {
        case "obstaculos": return .obstacles
        case "puerta": return .door
        case "salida": return .exit
        case "silla": return .chair
        case "persona": return .person
        case "companero": return .teammate
        case "codigo": return .barcode
        default: return nil
        }
    }
}
