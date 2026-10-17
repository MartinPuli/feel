import Foundation
import CryptoKit

/// Reviewed venue information downloaded ahead of time and read without internet. Built by
/// chalk/feel_chalk/venue_pack.py; protocol/venue-pack-v1.json is the shared vector. The payload
/// travels as a string beside its SHA-256 so a corrupted or truncated download is rejected whole.
public struct VenueEntry: Equatable, Sendable, Decodable {
    public enum Kind: String, Decodable, Sendable { case place, restriction }
    public let id: String
    public let kind: Kind
    public let name: String
    public let aliases: [String]
    public let text: String
    public let sourceUrl: URL
    public let retrievedAt: Date
    public let effectiveFrom: Date?
    public let effectiveUntil: Date?
    public let appliesTo: String?

    func isEffective(at now: Date) -> Bool {
        (effectiveFrom.map { $0 <= now } ?? true) && (effectiveUntil.map { now < $0 } ?? true)
    }
}

public struct VenuePack: Equatable, Sendable, Decodable {
    public static let schema = 1
    public let venueId: String
    public let venueName: String
    public let generatedAt: Date
    public let expiresAt: Date
    public let entries: [VenueEntry]

    public static func decode(_ data: Data) throws -> VenuePack {
        struct Envelope: Decodable { let schema: Int; let sha256: String; let payload: String }
        guard let envelope=try? JSONDecoder().decode(Envelope.self,from:data) else { throw VenuePackError.invalid("not a venue pack") }
        guard envelope.schema == schema else { throw VenuePackError.invalid("unsupported schema \(envelope.schema)") }
        let payload=Data(envelope.payload.utf8)
        guard SHA256.hash(data:payload).map({ String(format:"%02x",$0) }).joined() == envelope.sha256.lowercased() else {
            throw VenuePackError.invalid("payload does not match its hash")
        }
        let decoder=JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let pack=try? decoder.decode(VenuePack.self,from:payload) else { throw VenuePackError.invalid("payload is malformed") }
        try pack.validate()
        return pack
    }

    /// Answers from this pack only. Expired packs and out-of-window entries are never presented as current,
    /// and an active restriction on a place replaces its usual description.
    public func answer(_ question: String, at now: Date) -> VenueAnswer {
        guard now < expiresAt else { return .expired(venueName:venueName,expiresAt:expiresAt) }
        guard let place=place(for:question) else { return .unknown }
        guard place.isEffective(at:now) else { return .notCurrent(place) }
        if let restriction=entries.first(where:{ $0.kind == .restriction && $0.appliesTo == place.id && $0.isEffective(at:now) }) {
            return .restricted(place,restriction)
        }
        return .found(place)
    }

    private func place(for question: String) -> VenueEntry? {
        let asked=Self.words(question)
        var best: (entry: VenueEntry, length: Int)?
        for entry in entries where entry.kind == .place {
            for phrase in [entry.name]+entry.aliases {
                let words=Self.words(phrase)
                guard !words.isEmpty,words.count>(best?.length ?? 0),words.count<=asked.count,
                      (0...(asked.count-words.count)).contains(where:{ Array(asked[$0..<$0+words.count]) == words }) else { continue }
                best=(entry,words.count)
            }
        }
        return best?.entry
    }

    private static func words(_ text: String) -> [Substring] {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
    }

    private func validate() throws {
        func fail(_ reason: String) -> VenuePackError { .invalid(reason) }
        guard !venueId.isEmpty,!venueName.isEmpty,generatedAt<expiresAt,!entries.isEmpty else { throw fail("venue header is incomplete") }
        guard Set(entries.map(\.id)).count == entries.count else { throw fail("entry ids must be unique") }
        let places=Set(entries.filter { $0.kind == .place }.map(\.id))
        for entry in entries {
            let text=entry.text.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !entry.id.isEmpty,!entry.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!text.isEmpty,text.count<=500 else {
                throw fail("entry \(entry.id) needs a name and text")
            }
            guard entry.sourceUrl.scheme == "https",entry.sourceUrl.host != nil,entry.retrievedAt<=generatedAt else {
                throw fail("entry \(entry.id) needs an HTTPS source retrieved before the pack was built")
            }
            if let from=entry.effectiveFrom,let until=entry.effectiveUntil,from>=until { throw fail("entry \(entry.id) has an empty window") }
            if entry.kind == .restriction,entry.effectiveFrom == nil || !places.contains(entry.appliesTo ?? "") {
                throw fail("restriction \(entry.id) needs a start time and a place in this pack")
            }
        }
    }
}

public enum VenuePackError: Error, Equatable { case invalid(String) }

public enum VenueAnswer: Equatable, Sendable {
    case found(VenueEntry)
    case restricted(VenueEntry, VenueEntry)
    case notCurrent(VenueEntry)
    case expired(venueName: String, expiresAt: Date)
    case unknown

    public func spoken(timeZone: TimeZone = .current) -> String {
        let day=DateFormatter()
        day.locale=Locale(identifier:"en_US_POSIX"); day.timeZone=timeZone; day.dateFormat="MMMM d"
        switch self {
        case .found(let entry): return "\(entry.text) Source checked \(day.string(from:entry.retrievedAt))."
        case .restricted(_,let restriction): return "\(restriction.text) Source checked \(day.string(from:restriction.retrievedAt))."
        case .notCurrent(let entry): return "I have information about the \(entry.name.lowercased()), but it is not current, so I can't confirm it."
        case .expired(let venue,let date): return "The downloaded information for \(venue) expired on \(day.string(from:date)), so I can't confirm it."
        case .unknown: return "The downloaded venue information has nothing about that."
        }
    }
}
