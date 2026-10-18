import Foundation

/// One fresh pose in one continuous world-coordinate frame. A reset needs a new ID.
public struct MemoryPose: Equatable, Sendable {
    public let session: String, pose: CameraPose, timestamp: Double, tracking: Bool
    public init(session: String, pose: CameraPose, timestamp: Double, tracking: Bool) {
        self.session=session; self.pose=pose; self.timestamp=timestamp; self.tracking=tracking
    }
    /// Memory must reject reflections as well as malformed bases: a mirrored frame reverses guidance.
    var hasValidPose: Bool {
        let a=pose.right, b=pose.up
        let cross=Vector3(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x)
        return pose.isValid && cross.dot(pose.back)>0.98
    }
}
public struct SpatialBookmark: Equatable, Encodable, Sendable, Identifiable {
    public let id: String, name: String, position: Vector3
}
public struct SpatialMemorySnapshot: Equatable, Encodable, Sendable {
    public let session: String?, bookmarks: [SpatialBookmark], selectedID: String?, activeID: String?, returnPoint: Vector3?
}
public enum MemoryGuidanceState: String, Codable, Sendable {
    case idle, guiding, arrived, outsideFieldOfView, behind, beyondRange, differentLevel
    case trackingLost, stalePose, invalidPose, sessionMismatch, sessionUnavailable
}
public struct MemoryGuidance: Equatable, Sendable {
    public let state: MemoryGuidanceState
    /// Range in the native camera x/z plane, matching V1 depth bands.
    public let distance: Double?, horizontalDistance: Double?, bearingDegrees: Double?, targetName: String?, target: TargetObservation?
    public var requiresNeutral: Bool {
        switch state {
        case .trackingLost,.stalePose,.invalidPose,.sessionMismatch,.sessionUnavailable: return true
        default: return false
        }
    }
}
public struct SpatialEncoderOutput: Equatable, Sendable {
    public let output: EncoderOutput, guidance: MemoryGuidance
}
public enum SpatialMemoryError: Error, Equatable, CustomStringConvertible {
    case invalidID, invalidName, duplicateID, duplicateName, duplicateSession, capacity
    case noSession, noSelection, noReturnPoint, unknownBookmark, invalidContext(MemoryGuidanceState)
    public var description: String {
        switch self {
        case .invalidID: return "ID must contain 1–64 ASCII letters, digits, hyphens or underscores."
        case .invalidName: return "Name must contain 1–40 characters and no control characters."
        case .duplicateID: return "A place with this ID already exists."
        case .duplicateName: return "A place with this name already exists."
        case .duplicateSession: return "A new coordinate frame requires a new session ID."
        case .capacity: return "This session already contains 64 places."
        case .noSession: return "Start a session before saving or recalling places."
        case .noSelection: return "Select a place first."
        case .noReturnPoint: return "Set a return point first."
        case .unknownBookmark: return "The selected place no longer exists."
        case .invalidContext(let state): return "Fresh, normal tracking in this session is required (\(state.rawValue))."
        }
    }
}

/// Session memory. Persistent archives may populate a new frame only after the caller's
/// WorldMapRestoreGate reports ready. No navigation paths or object recognition.
/// The caller confines mutation to one queue (the app uses the main queue).
public struct SpatialMemoryManager: Sendable {
    public static let returnID = "$return"
    public static let arrivalRadius = 0.35
    public static let verticalTolerance = 0.75
    public static let poseMaxAge = 0.250
    public private(set) var session: String?
    public private(set) var bookmarks: [SpatialBookmark] = []
    public private(set) var selectedID: String?
    public private(set) var activeID: String?
    public private(set) var returnPoint: Vector3?
    private var usedSessions: Set<String> = []
    public init() {}
    public var snapshot: SpatialMemorySnapshot { .init(session:session,bookmarks:bookmarks,selectedID:selectedID,activeID:activeID,returnPoint:returnPoint) }

    /// Starting even an identically positioned session discards the previous frame.
    public mutating func begin(session id: String) throws {
        guard Self.validID(id) else { throw SpatialMemoryError.invalidID }
        guard !usedSessions.contains(id) else { throw SpatialMemoryError.duplicateSession }
        end(); usedSessions.insert(id); session=id
    }
    public mutating func end() { session=nil; bookmarks=[]; selectedID=nil; activeID=nil; returnPoint=nil }
    /// Installation is inactive: a separate explicit Recall or Return is required.
    public mutating func restore(archive:PersistentMemoryArchive,session:String) throws {
        guard self.session==session else { throw SpatialMemoryError.noSession }
        guard bookmarks.isEmpty,returnPoint==nil,activeID==nil else { throw PersistentMemoryError.invalidArchive("restore session is no longer empty") }
        bookmarks=archive.bookmarks; returnPoint=archive.returnPoint
    }
    @discardableResult public mutating func remember(id: String=UUID().uuidString, name: String, sample: MemoryPose, now: Double) throws -> SpatialBookmark {
        try requireContext(sample,now:now)
        guard Self.validID(id) else { throw SpatialMemoryError.invalidID }
        guard !bookmarks.contains(where: { $0.id==id }) else { throw SpatialMemoryError.duplicateID }
        let clean=try validatedName(name,excluding:nil)
        guard bookmarks.count<64 else { throw SpatialMemoryError.capacity }
        let bookmark=SpatialBookmark(id:id,name:clean,position:sample.pose.position)
        bookmarks.append(bookmark); selectedID=id; activeID=nil
        return bookmark
    }
    public mutating func select(id: String) throws {
        guard bookmarks.contains(where: { $0.id==id }) else { throw SpatialMemoryError.unknownBookmark }
        activeID=nil; selectedID=id
    }
    public mutating func rename(id: String, name: String) throws {
        guard let index=bookmarks.firstIndex(where: { $0.id==id }) else { throw SpatialMemoryError.unknownBookmark }
        let clean=try validatedName(name,excluding:id), old=bookmarks[index]
        bookmarks[index]=SpatialBookmark(id:old.id,name:clean,position:old.position)
    }
    public mutating func delete(id: String) throws {
        guard let index=bookmarks.firstIndex(where: { $0.id==id }) else { throw SpatialMemoryError.unknownBookmark }
        bookmarks.remove(at:index)
        if selectedID==id { selectedID=nil }; if activeID==id { activeID=nil }
    }
    /// Recall sets intent. Every resulting packet still requires a fresh valid pose.
    public mutating func recall(id: String?=nil) throws {
        guard session != nil else { throw SpatialMemoryError.noSession }
        guard let id=id ?? selectedID else { throw SpatialMemoryError.noSelection }
        guard bookmarks.contains(where: { $0.id==id }) else { throw SpatialMemoryError.unknownBookmark }
        selectedID=id; activeID=id
    }
    public mutating func setReturnPoint(sample: MemoryPose, now: Double) throws {
        try requireContext(sample,now:now); returnPoint=sample.pose.position
        if activeID==Self.returnID { activeID=nil }
    }
    public mutating func returnToStart() throws {
        guard session != nil else { throw SpatialMemoryError.noSession }
        guard returnPoint != nil else { throw SpatialMemoryError.noReturnPoint }
        activeID=Self.returnID
    }
    public mutating func stopGuidance() { activeID=nil }

    public func guidance(sample: MemoryPose, now: Double) -> MemoryGuidance {
        func result(_ state: MemoryGuidanceState, distance: Double?=nil, horizontal: Double?=nil, bearing: Double?=nil, name: String?=nil, target: TargetObservation?=nil) -> MemoryGuidance {
            .init(state:state,distance:distance,horizontalDistance:horizontal,bearingDegrees:bearing,targetName:name,target:target)
        }
        if let fault=contextFault(sample,now:now) { return result(fault) }
        guard let activeID else { return result(.idle) }
        let position: Vector3, name: String
        if activeID==Self.returnID,let point=returnPoint { position=point; name="Return point" }
        else if let bookmark=bookmarks.first(where: { $0.id==activeID }) { position=bookmark.position; name=bookmark.name }
        else { return result(.idle) }
        let delta=position-sample.pose.position, local=sample.pose.cameraPoint(world:position)
        let horizontal=hypot(delta.x,delta.z),distance=hypot(local.x,local.z)
        guard delta.isFinite,local.isFinite,horizontal.isFinite,distance.isFinite else { return result(.invalidPose) }
        // Arrival uses the gravity plane; tactile projection exactly matches V1.
        guard abs(delta.y)<=Self.verticalTolerance else { return result(.differentLevel,distance:distance,horizontal:horizontal,name:name) }
        if horizontal<=Self.arrivalRadius { return result(.arrived,distance:distance,horizontal:horizontal,name:name) }
        guard let bearing=TactileGeometry.bearing(x:local.x,z:local.z) else { return result(.behind,distance:distance,horizontal:horizontal,name:name) }
        guard TactileGeometry.column(bearingDegrees:bearing) != nil else { return result(.outsideFieldOfView,distance:distance,horizontal:horizontal,bearing:bearing,name:name) }
        guard distance<=4 else { return result(.beyondRange,distance:distance,horizontal:horizontal,bearing:bearing,name:name) }
        let target=TargetObservation(bearingDegrees:bearing,distance:distance,timestamp:sample.timestamp,label:name)
        return result(.guiding,distance:distance,horizontal:horizontal,bearing:bearing,name:name,target:target)
    }

    /// The existing nine-byte encoder remains the sole distance/sector implementation.
    /// A nearer obstacle is preserved; a highlight never claims a clear route.
    public func encode(sequence: UInt8, sample: MemoryPose, now: Double, distances: [Double?], floorCalibrated: Bool=true) -> SpatialEncoderOutput {
        let direction=guidance(sample:sample,now:now)
        let output: EncoderOutput
        if direction.requiresNeutral {
            let state: GuidanceState
            switch direction.state {
            case .trackingLost: state = .trackingLost
            case .stalePose: state = .staleDepth
            default: state = .invalidFrame
            }
            output = .init(packet:.neutral(sequence:sequence),state:state)
        } else {
            output=TactileEncoder.encode(sequence:sequence,now:now,frameTimestamp:sample.timestamp,tracking:sample.tracking,distances:distances,target:direction.target,floorCalibrated:floorCalibrated)
        }
        return .init(output:output,guidance:direction)
    }
    private func requireContext(_ sample: MemoryPose, now: Double) throws {
        if let fault=contextFault(sample,now:now) { throw SpatialMemoryError.invalidContext(fault) }
    }
    private func contextFault(_ sample: MemoryPose, now: Double) -> MemoryGuidanceState? {
        guard let session else { return .sessionUnavailable }
        guard session==sample.session else { return .sessionMismatch }
        guard sample.tracking else { return .trackingLost }
        guard now.isFinite,sample.timestamp.isFinite,now>=sample.timestamp,sample.hasValidPose,
              sample.pose.up.y>0.7,abs(sample.pose.right.y)<0.35 else { return .invalidPose }
        guard now-sample.timestamp<=Self.poseMaxAge else { return .stalePose }
        return nil
    }
    private static func validID(_ id: String) -> Bool {
        (1...64).contains(id.utf8.count) && id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45 || $0==95 }
    }
    private func validatedName(_ name: String, excluding id: String?) throws -> String {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (1...40).contains(clean.count),!name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw SpatialMemoryError.invalidName }
        func key(_ value: String) -> String { value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")) }
        guard !bookmarks.contains(where: { $0.id != id && key($0.name)==key(clean) }) else { throw SpatialMemoryError.duplicateName }
        return clean
    }
}
