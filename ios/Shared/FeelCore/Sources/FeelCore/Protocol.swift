import Foundation

public enum ProtocolError: Error, Equatable, CustomStringConvertible {
    case invalidLength(Int), invalidBand(Int), invalidHighlight(Int), malformedHex
    public var description: String {
        switch self {
        case .invalidLength(let count): return "Expected 9 packet bytes or 7 bands; received \(count)"
        case .invalidBand(let value): return "Band must be 0...4, received \(value)"
        case .invalidHighlight(let value): return "Highlight must be 0...6 or 255, received \(value)"
        case .malformedHex: return "Hex must contain exactly 18 hexadecimal digits"
        }
    }
}

/// The exact nine-byte wire packet. A wire-legal empty-column highlight is preserved;
/// firmware and TactileEncoder suppress its effective highlight.
public struct FeelPacket: Equatable, Codable, Sendable {
    public let sequence: UInt8
    public let bands: [UInt8]
    public let highlight: UInt8
    public init(sequence: UInt8, bands: [UInt8], highlight: UInt8 = 255) throws {
        guard bands.count == 7 else { throw ProtocolError.invalidLength(bands.count) }
        if let band = bands.first(where: { $0 > 4 }) { throw ProtocolError.invalidBand(Int(band)) }
        guard highlight < 7 || highlight == 255 else { throw ProtocolError.invalidHighlight(Int(highlight)) }
        self.sequence = sequence; self.bands = bands; self.highlight = highlight
    }
    enum CodingKeys: String, CodingKey { case sequence,bands,highlight }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(sequence:c.decode(UInt8.self,forKey:.sequence),bands:c.decode([UInt8].self,forKey:.bands),highlight:c.decode(UInt8.self,forKey:.highlight))
    }
    public init(bytes: [UInt8]) throws {
        guard bytes.count == 9 else { throw ProtocolError.invalidLength(bytes.count) }
        try self.init(sequence: bytes[0], bands: Array(bytes[1...7]), highlight: bytes[8])
    }
    public init(hex: String) throws {
        guard hex.count == 18, hex.allSatisfy({ $0.isHexDigit }) else { throw ProtocolError.malformedHex }
        var bytes: [UInt8] = []; var offset = hex.startIndex
        while offset < hex.endIndex {
            let end = hex.index(offset, offsetBy: 2)
            guard let byte = UInt8(hex[offset..<end], radix: 16) else { throw ProtocolError.malformedHex }
            bytes.append(byte); offset = end
        }
        try self.init(bytes: bytes)
    }
    public var bytes: [UInt8] { [sequence] + bands + [highlight] }
    public var data: Data { Data(bytes) }
    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }
    public var effectiveHighlight: UInt8 { highlight < 7 && bands[Int(highlight)] != 0 ? highlight : 255 }
    public static func neutral(sequence: UInt8) -> Self { try! Self(sequence: sequence, bands: Array(repeating: 0, count: 7)) }
}

public enum FeelBLE {
    public static let service = "7D2A0001-5C6B-4F9A-8E21-0BCE7F0A1000"
    public static let command = "7D2A0002-5C6B-4F9A-8E21-0BCE7F0A1000"
    public static let status = "7D2A0003-5C6B-4F9A-8E21-0BCE7F0A1000"
}

public enum TactileGeometry {
    public static func band(distance: Double) -> UInt8 {
        guard distance.isFinite, distance > 0, distance <= 4 else { return 0 }
        if distance < 0.9 { return 1 }; if distance < 1.6 { return 2 }
        if distance < 2.5 { return 3 }; return 4
    }
    /// Seven equal sectors. x right, camera forward -z. Internal edges choose right.
    public static func column(bearingDegrees: Double) -> Int? {
        guard bearingDegrees.isFinite, bearingDegrees >= -45, bearingDegrees <= 45 else { return nil }
        if bearingDegrees == 45 { return 6 }
        let scaled = (bearingDegrees + 45) * 7 / 90
        // Avoid a round-off drift to the left for an exactly constructed boundary.
        let nearest = scaled.rounded()
        let normalized = abs(scaled - nearest) <= 1e-12 ? nearest : scaled
        return min(6, max(0, Int(floor(normalized))))
    }
    public static func bearing(x: Double, z: Double) -> Double? {
        guard x.isFinite, z.isFinite, z < 0 else { return nil }
        return atan2(x, -z) * 180 / .pi
    }
}

public enum PuckOutputState: UInt8, Sendable { case disabled=0,ready=1,fault=2 }
public struct PuckStatus: Equatable, Sendable {
    public let connected:Bool,active:Bool,sequenceValid:Bool,sequence:UInt8,highlight:UInt8,benchArmed:Bool,outputState:PuckOutputState,bands:[UInt8]
    public init(bytes:[UInt8]) throws {
        guard bytes.count==15 else { throw ProtocolError.invalidLength(bytes.count) }
        guard bytes[0]==1,[bytes[1],bytes[2],bytes[3],bytes[6]].allSatisfy({$0<=1}),let state=PuckOutputState(rawValue:bytes[7]) else { throw ProtocolError.malformedHex }
        _=try FeelPacket(sequence:bytes[4],bands:Array(bytes[8...14]),highlight:bytes[5])
        connected=bytes[1]==1;active=bytes[2]==1;sequenceValid=bytes[3]==1;sequence=bytes[4];highlight=bytes[5];benchArmed=bytes[6]==1;outputState=state;bands=Array(bytes[8...14])
    }
    public var summary:String {
        let output:String
        switch outputState { case .disabled:output="Physical PWM DISABLED";case .ready:output="PWM enabled — unverified physically";case .fault:output="OUTPUT FAULT — remove servo power" }
        return "\(output). Controller \(active ? "active" : "neutral"), seq \(sequenceValid ? String(sequence) : "none"), bench \(benchArmed ? "armed" : "off")."
    }
}

/// Callback identity gate, shared by production Bluetooth code and host tests.
public struct PeripheralSelection: Sendable {
    public private(set) var identifier:UUID?
    public init() {}
    public mutating func select(_ identifier:UUID) { self.identifier=identifier }
    public mutating func clear() { identifier=nil }
    public func accepts(_ identifier:UUID)->Bool { self.identifier==identifier }
}
