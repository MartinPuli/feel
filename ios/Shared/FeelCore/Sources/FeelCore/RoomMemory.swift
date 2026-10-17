import Foundation

/// Room memory: targets confirmed in earlier sessions, kept in the frame of a printed FEEL tag so they come
/// back once the tag is recognized again. Memory only shortcuts the question ("where is the exit?"); the pins
/// always come from live depth. chalk/feel_chalk/anchors.py aggregates the same way for the shared memory on
/// Chalk, and protocol/room-memory-v1.json is the vector both sides must agree on.

/// The printed tag as ARKit places it: an orthonormal, right-handed frame in world coordinates. ARKit's image
/// anchor has x to the right along the tag, y out of the tag toward the viewer and z down along the tag (the
/// image lies in the anchor's x–z plane). The same basis math as CameraPose, so a point stored in tag
/// coordinates returns in any later session's world.
public struct RoomFrame: Equatable, Codable, Sendable {
    public let origin: Vector3, xAxis: Vector3, yAxis: Vector3, zAxis: Vector3
    public init(origin: Vector3, xAxis: Vector3, yAxis: Vector3, zAxis: Vector3) {
        self.origin=origin; self.xAxis=xAxis; self.yAxis=yAxis; self.zAxis=zAxis
    }
    /// From a 4×4 transform flattened column by column (ARAnchor.transform). Nil unless it is a rigid frame.
    public init?(columnMajor m: [Double]) {
        guard m.count == 16 else { return nil }
        self.init(origin:Vector3(m[12],m[13],m[14]),xAxis:Vector3(m[0],m[1],m[2]),yAxis:Vector3(m[4],m[5],m[6]),zAxis:Vector3(m[8],m[9],m[10]))
        guard isValid else { return nil }
    }
    /// Unit, mutually perpendicular axes that form a right-handed frame: a mirrored frame would swap the user's left and right.
    public var isValid: Bool {
        origin.isFinite && xAxis.isFinite && yAxis.isFinite && zAxis.isFinite &&
        abs(xAxis.dot(xAxis)-1)<0.02 && abs(yAxis.dot(yAxis)-1)<0.02 && abs(zAxis.dot(zAxis)-1)<0.02 &&
        abs(xAxis.dot(yAxis))<0.02 && abs(xAxis.dot(zAxis))<0.02 && abs(yAxis.dot(zAxis))<0.02 &&
        Self.cross(xAxis,yAxis).dot(zAxis)>0.98
    }
    static func cross(_ a: Vector3,_ b: Vector3) -> Vector3 { Vector3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) }
    public func tagPoint(world point: Vector3) -> Vector3 {
        let relative=point-origin; return Vector3(relative.dot(xAxis),relative.dot(yAxis),relative.dot(zAxis))
    }
    public func worldPoint(tag point: Vector3) -> Vector3 { origin + xAxis*point.x + yAxis*point.y + zAxis*point.z }
}

/// One recognition of a printed tag: its frame in the current ARKit world (`worldEpoch`); a tracking reset ends it.
public struct TagSighting: Equatable, Sendable {
    public let tagId: String, frame: RoomFrame, worldEpoch: Int, timestamp: Double
    public init(tagId: String, frame: RoomFrame, worldEpoch: Int, timestamp: Double) {
        self.tagId=tagId; self.frame=frame; self.worldEpoch=worldEpoch; self.timestamp=timestamp
    }
}

/// One confirmed sighting of a target in a tag's frame, in metres: the phone's row of the anchors table.
public struct RoomAnchor: Equatable, Codable, Sendable {
    public let label: String, position: Vector3, confidence: Double, seenAt: Date
    public init(label: String, position: Vector3, confidence: Double, seenAt: Date) {
        self.label=label; self.position=position; self.confidence=confidence; self.seenAt=seenAt
    }
    /// The same key as confirmed finds and the anchors table: lower case, single spaces.
    public static func normalized(_ label: String) -> String {
        label.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
    }
    /// Rooms are tens of metres: a point farther than this from the tag is a bad placement, not a memory.
    public static let reach = 100.0
    public var isUsable: Bool {
        !Self.normalized(label).isEmpty && position.isFinite && abs(position.x)<=Self.reach && abs(position.y)<=Self.reach && abs(position.z)<=Self.reach &&
        confidence.isFinite && confidence>=0 && confidence<=1
    }
    enum CodingKeys: String, CodingKey { case label,x,y,z,confidence,seenAt="seen_at" }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        self.init(label:try c.decode(String.self,forKey:.label),
                  position:Vector3(try c.decode(Double.self,forKey:.x),try c.decode(Double.self,forKey:.y),try c.decode(Double.self,forKey:.z)),
                  confidence:try c.decode(Double.self,forKey:.confidence),seenAt:try c.decode(Date.self,forKey:.seenAt))
    }
    public func encode(to encoder: Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(label,forKey:.label); try c.encode(position.x,forKey:.x); try c.encode(position.y,forKey:.y); try c.encode(position.z,forKey:.z)
        try c.encode(confidence,forKey:.confidence); try c.encode(seenAt,forKey:.seenAt)
    }
}

/// A label's stable position in the tag frame: the per-axis median of its newest `keep` sightings, so one bad
/// confirmation moves nothing much. Mirrors chalk/feel_chalk/anchors.py.
public struct RememberedTarget: Equatable, Sendable {
    public static let keep = 20
    public let label: String, position: Vector3, sightings: Int, lastSeenAt: Date
    public init(label: String, position: Vector3, sightings: Int, lastSeenAt: Date) {
        self.label=label; self.position=position; self.sightings=sightings; self.lastSeenAt=lastSeenAt
    }
    /// One target per label, sorted by label. Anchors that are not usable are ignored, never guessed.
    public static func remember(_ anchors: [RoomAnchor], keep: Int = keep) -> [RememberedTarget] {
        var byLabel: [String: [RoomAnchor]]=[:]
        for anchor in anchors where anchor.isUsable { byLabel[RoomAnchor.normalized(anchor.label),default:[]].append(anchor) }
        return byLabel.keys.sorted().map { label in
            let rows=byLabel[label]!.sorted { $0.seenAt>$1.seenAt }
            let newest=rows.prefix(max(1,keep))
            let position=Vector3(median(newest.map(\.position.x)),median(newest.map(\.position.y)),median(newest.map(\.position.z)))
            return RememberedTarget(label:label,position:position,sightings:rows.count,lastSeenAt:rows[0].seenAt)
        }
    }
    public static func remembered(_ label: String, in anchors: [RoomAnchor], keep: Int = keep) -> RememberedTarget? {
        let key=RoomAnchor.normalized(label)
        return remember(anchors.filter { RoomAnchor.normalized($0.label) == key },keep:keep).first
    }
    /// The middle value, or the mean of the two middle values: the same median as Python's statistics module.
    static func median(_ values: [Double]) -> Double {
        let sorted=values.sorted(), n=sorted.count
        return n%2 == 1 ? sorted[n/2] : (sorted[n/2-1]+sorted[n/2])/2
    }
}

public enum RoomMemoryError: Error, Equatable { case invalidTagId(String) }

/// Anchors per tag id on disk, as JSON under Application Support. A write replaces the file atomically, so a
/// failed write leaves the previous anchors in place; a corrupt file reads as nothing remembered.
public final class RoomMemoryStore {
    /// Newest sightings kept per tag; the aggregation only ever looks at the last 20 per label.
    public static let keepPerTag = 200
    private let directory: URL

    public init(directory: URL) { self.directory=directory }

    /// Tag ids are the slugs printed on the tags, so they are also safe file names.
    public static func isTagId(_ id: String) -> Bool { id.range(of:"^[a-z0-9][a-z0-9-]{0,63}$",options:.regularExpression) != nil }
    private func file(_ tagId: String) throws -> URL {
        guard Self.isTagId(tagId) else { throw RoomMemoryError.invalidTagId(tagId) }
        return directory.appendingPathComponent("\(tagId).json")
    }

    public func anchors(for tagId: String) -> [RoomAnchor] {
        guard let file=try? file(tagId),let data=try? Data(contentsOf:file) else { return [] }
        return (try? Self.decoder.decode([RoomAnchor].self,from:data)) ?? []
    }
    @discardableResult
    public func append(_ anchor: RoomAnchor, tagId: String) throws -> [RoomAnchor] {
        let kept=Array((anchors(for:tagId)+[anchor]).suffix(Self.keepPerTag))
        try replace(kept,tagId:tagId)
        return kept
    }
    public func replace(_ anchors: [RoomAnchor], tagId: String) throws {
        let file=try file(tagId)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try Self.encoder.encode(anchors).write(to:file,options:.atomic)
    }
    public func remove(tagId: String) throws {
        let file=try file(tagId)
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        try FileManager.default.removeItem(at:file)
    }

    private static let encoder: JSONEncoder={ let e=JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting=[.sortedKeys]; return e }()
    private static let decoder: JSONDecoder={ let d=JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
