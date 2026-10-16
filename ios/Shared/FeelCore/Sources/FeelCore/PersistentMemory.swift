import Foundation

public enum PersistentMemoryError: Error, Equatable, CustomStringConvertible {
    case invalidArchive(String)
    public var description: String { switch self { case .invalidArchive(let reason): return "Saved map rejected: \(reason)" } }
}

/// A strict, bounded envelope. ARKit bytes are opaque here; the iOS adapter additionally
/// securely decodes ARWorldMap and verifies its marker anchor before running the session.
public struct PersistentMemoryArchive: Codable, Equatable, Sendable {
    public static let maxMapBytes = 16 * 1024 * 1024
    public static let maxJSONBytes = 24 * 1024 * 1024
    public let version: Int
    public let mapID: String
    public let anchorID: String
    public let mapDataBase64: String
    public let bookmarks: [SpatialBookmark]
    public let returnPoint: Vector3?
    public var mapData: Data { Data(base64Encoded:mapDataBase64)! }

    public init(mapID:String, anchorID:String, mapData:Data, snapshot:SpatialMemorySnapshot) throws {
        try self.init(version:1,mapID:mapID,anchorID:anchorID,mapDataBase64:mapData.base64EncodedString(),bookmarks:snapshot.bookmarks,returnPoint:snapshot.returnPoint)
    }
    private init(version:Int,mapID:String,anchorID:String,mapDataBase64:String,bookmarks:[SpatialBookmark],returnPoint:Vector3?) throws {
        func reject(_ reason:String) throws -> Never { throw PersistentMemoryError.invalidArchive(reason) }
        guard version==1 else { try reject("unsupported version") }
        guard let map=UUID(uuidString:mapID),let anchor=UUID(uuidString:anchorID),map != anchor else { try reject("map and anchor require distinct UUIDs") }
        guard mapDataBase64.utf8.count<=((Self.maxMapBytes+2)/3)*4,
              let data=Data(base64Encoded:mapDataBase64),!data.isEmpty,data.count<=Self.maxMapBytes,
              data.base64EncodedString()==mapDataBase64 else { try reject("invalid or oversized map bytes") }
        guard bookmarks.count<=64 else { try reject("more than 64 places") }
        var ids=Set<String>(),names=Set<String>()
        for place in bookmarks {
            guard Self.validID(place.id),ids.insert(place.id).inserted else { try reject("invalid or duplicate place ID") }
            guard Self.validName(place.name),names.insert(Self.nameKey(place.name)).inserted else { try reject("invalid or duplicate place name") }
            guard Self.validPosition(place.position) else { try reject("invalid place coordinate") }
        }
        if let point=returnPoint, !Self.validPosition(point) { try reject("invalid return coordinate") }
        self.version=version; self.mapID=map.uuidString; self.anchorID=anchor.uuidString
        self.mapDataBase64=mapDataBase64; self.bookmarks=bookmarks; self.returnPoint=returnPoint
    }
    public static func decode(_ data:Data) throws -> Self {
        guard data.count<=maxJSONBytes else { throw PersistentMemoryError.invalidArchive("JSON exceeds 24 MiB") }
        return try JSONDecoder().decode(Self.self,from:data)
    }
    public func encoded() throws -> Data { let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]; return try encoder.encode(self) }
    static func validID(_ value:String)->Bool {
        (1...64).contains(value.utf8.count) && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45 || $0==95 }
    }
    private static func validName(_ value:String)->Bool {
        (1...40).contains(value.count) && value.utf8.count<=640 && value==value.trimmingCharacters(in:.whitespacesAndNewlines) && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private static func nameKey(_ value:String)->String { value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")) }
    private static func validPosition(_ value:Vector3)->Bool { value.isFinite && abs(value.x)<=10_000 && abs(value.y)<=10_000 && abs(value.z)<=10_000 }
    private enum CodingKeys:String,CodingKey { case version,mapID,anchorID,mapDataBase64,bookmarks,returnPoint }
    public init(from decoder:Decoder) throws {
        try strictKeys(decoder,allowed:["version","mapID","anchorID","mapDataBase64","bookmarks","returnPoint"])
        let c=try decoder.container(keyedBy:CodingKeys.self)
        let places=try c.decode([ArchivedPlace].self,forKey:.bookmarks).map { SpatialBookmark(id:$0.id,name:$0.name,position:$0.position.value) }
        try self.init(version:c.decode(Int.self,forKey:.version),mapID:c.decode(String.self,forKey:.mapID),anchorID:c.decode(String.self,forKey:.anchorID),mapDataBase64:c.decode(String.self,forKey:.mapDataBase64),bookmarks:places,returnPoint:c.decodeIfPresent(ArchivedPosition.self,forKey:.returnPoint)?.value)
    }
}
private struct AnyArchiveKey:CodingKey {
    var stringValue:String; var intValue:Int? { nil }
    init?(stringValue:String) { self.stringValue=stringValue }
    init?(intValue:Int) { return nil }
}
private func strictKeys(_ decoder:Decoder,allowed:Set<String>) throws {
    let c=try decoder.container(keyedBy:AnyArchiveKey.self)
    guard c.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw PersistentMemoryError.invalidArchive("unknown field") }
}
private struct ArchivedPosition:Decodable {
    let value:Vector3
    enum CodingKeys:String,CodingKey { case x,y,z }
    init(from decoder:Decoder) throws {
        try strictKeys(decoder,allowed:["x","y","z"])
        let c=try decoder.container(keyedBy:CodingKeys.self)
        value=try Vector3(c.decode(Double.self,forKey:.x),c.decode(Double.self,forKey:.y),c.decode(Double.self,forKey:.z))
    }
}
private struct ArchivedPlace:Decodable {
    let id:String,name:String,position:ArchivedPosition
    enum CodingKeys:String,CodingKey { case id,name,position }
    init(from decoder:Decoder) throws {
        try strictKeys(decoder,allowed:["id","name","position"])
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id); name=try c.decode(String.self,forKey:.name); position=try c.decode(ArchivedPosition.self,forKey:.position)
    }
}

public enum WorldMapRestoreState:String,Codable,Sendable { case idle,awaitingRelocalization,ready,failed }

/// A map identity is not proof of localization. A restore requires the actual marker,
/// observed AR relocalization, then normal fresh upright poses over a 0.5 second interval.
/// Call at the sensor cadence; any observed tracking loss or mismatch restarts settling.
public struct WorldMapRestoreGate:Sendable {
    public private(set) var state:WorldMapRestoreState = .idle
    public private(set) var archive:PersistentMemoryArchive?
    public private(set) var session:String?
    private var began:Double=0,lastNow:Double=0,normalSince:Double?
    private var sawRelocalizing=false
    public init() {}
    public mutating func begin(archive:PersistentMemoryArchive,session:String,now:Double) throws {
        guard PersistentMemoryArchive.validID(session),now.isFinite,now>=0 else { throw PersistentMemoryError.invalidArchive("invalid restore session or clock") }
        self.archive=archive; self.session=session; began=now; lastNow=now; normalSince=nil; sawRelocalizing=false; state = .awaitingRelocalization
    }
    public mutating func cancel() { self=Self() }
    /// Timer-driven expiry also works when AR stops delivering frames entirely.
    @discardableResult public mutating func checkDeadline(now:Double)->WorldMapRestoreState {
        if state == .awaitingRelocalization,(!now.isFinite || now<lastNow || now-began>60) { state = .failed }
        return state
    }
    @discardableResult public mutating func observe(session:String,mapID:String,anchorID:String?,now:Double,sample:MemoryPose,relocalizing:Bool)->WorldMapRestoreState {
        guard state == .awaitingRelocalization,let archive else { return state }
        guard now.isFinite,now>=lastNow,now-began<=60 else { state = .failed; return state }
        if now-lastNow>SpatialMemoryManager.poseMaxAge { normalSince=nil }
        lastNow=now
        guard self.session==session,sample.session==session,UUID(uuidString:mapID)?.uuidString==archive.mapID else { normalSince=nil; return state }
        let age=now-sample.timestamp
        guard sample.timestamp.isFinite,age>=0,age<=SpatialMemoryManager.poseMaxAge,sample.pose.isValid,sample.pose.up.y>0.7,abs(sample.pose.right.y)<0.35 else { normalSince=nil; return state }
        if relocalizing { sawRelocalizing=true; normalSince=nil; return state }
        guard sawRelocalizing,sample.tracking,UUID(uuidString:anchorID ?? "")?.uuidString==archive.anchorID else { normalSince=nil; return state }
        if normalSince==nil { normalSince=now }
        if now-normalSince!>=0.5 { state = .ready }
        return state
    }
}
