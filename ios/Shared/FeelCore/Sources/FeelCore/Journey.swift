import Foundation

/// The journey loop: every walk toward a chosen target is a Journey, recorded in the levelled frame of the room's
/// printed FEEL tag (RoomFrame.levelled: x right along the tag, y out of the tag into the room, metres) and kept for
/// Chalk, which turns journeys into a Path (a polyline) and progress points every six metres; the phone then leads
/// the user along those points (WaypointFollower). protocol/journey-v1.json is the vector both sides must agree on.
/// Nothing here reaches the pins directly: a journey only chooses where the pins point, and the pins always show
/// live depth. A route is a suggested direction, never a clear path.

/// A point on the floor of the tag frame, metres.
public struct FloorPoint: Equatable, Codable, Sendable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x=x; self.y=y }
    public var isFinite: Bool { x.isFinite && y.isFinite }
    public func distance(to other: FloorPoint) -> Double { hypot(other.x-x,other.y-y) }
    /// The point's cell centre on a lattice of `cellSize` cells whose corners sit on the origin.
    public func cellCentre(cellSize: Double) -> FloorPoint {
        FloorPoint((floor(x/cellSize)+0.5)*cellSize,(floor(y/cellSize)+0.5)*cellSize)
    }
    /// A world point on the floor of `frame` (a levelled tag frame or `RoomFrame.worldFloor`), its height dropped.
    public init(world point: Vector3, in frame: RoomFrame) {
        let tag=frame.tagPoint(world:point); self.init(tag.x,tag.y)
    }
    /// Where the camera stands on the floor of `frame`.
    public init(pose: CameraPose, in frame: RoomFrame) { self.init(world:pose.position,in:frame) }
    /// Back to the world: on the floor plane through the frame's origin (the tag's height; the pins use horizontal range).
    public func world(in frame: RoomFrame) -> Vector3 { frame.worldPoint(tag:Vector3(x,y,0)) }
}

public extension RoomFrame {
    /// The world's own floor as a frame, for leading the user when no tag has been seen: x is world +x, y is world +z
    /// and z points down, so it is its own levelled frame. Journeys are never recorded in it (they need a tag).
    static let worldFloor = RoomFrame(origin: .zero, xAxis: Vector3(1,0,0), yAxis: Vector3(0,0,1), zAxis: Vector3(0,-1,0))
    /// The way the camera faces, as a heading on this frame's floor: clockwise from +y (out of the tag), so +x (to the
    /// right along the tag) is 90°, in 0…360. Nil when the camera looks straight up or down.
    func heading(of pose: CameraPose) -> Double? {
        let forward=pose.back*(-1)
        let x=forward.dot(xAxis), y=forward.dot(yAxis)
        guard hypot(x,y)>0.3 else { return nil }
        let degrees=atan2(x,y)*180 / .pi
        return degrees<0 ? degrees+360 : degrees
    }
}

/// One walk toward a target: the contract shared with Chalk (protocol/journey-v1.json).
public struct Journey: Equatable, Sendable {
    public struct Step: Equatable, Codable, Sendable {
        /// Seconds since `startedAt`.
        public let t: Double
        public let x: Double, y: Double
        public let headingDeg: Double
        public init(t: Double, x: Double, y: Double, headingDeg: Double) { self.t=t; self.x=x; self.y=y; self.headingDeg=headingDeg }
        enum CodingKeys: String, CodingKey { case t,x,y,headingDeg="heading_deg" }
        public var point: FloorPoint { FloorPoint(x,y) }
    }
    public var venueId: String?, tagId: String, userId: String?, sessionId: String
    public var startedAt: Date
    public var targetLabel: String
    public var steps: [Step]
    /// Centres of the floor cells the camera classified as blocked on this trip.
    public var obstacles: [FloorPoint]
    /// Time from a target or progress-point change to the first packet that showed it, milliseconds.
    public var cueLatencyMs: [Double]
    public var arrivedAt: Date?
    /// Distance from the last step to the target when the walk ended, metres: about zero on arrival, how far short
    /// otherwise; nil only for a walk without steps.
    public var arrivalDistanceM: Double?

    public init(venueId: String?=nil, tagId: String, userId: String?=nil, sessionId: String, startedAt: Date, targetLabel: String,
                steps: [Step]=[], obstacles: [FloorPoint]=[], cueLatencyMs: [Double]=[], arrivedAt: Date?=nil, arrivalDistanceM: Double?=nil) {
        self.venueId=venueId; self.tagId=tagId; self.userId=userId; self.sessionId=sessionId; self.startedAt=startedAt; self.targetLabel=targetLabel
        self.steps=steps; self.obstacles=obstacles; self.cueLatencyMs=cueLatencyMs; self.arrivedAt=arrivedAt; self.arrivalDistanceM=arrivalDistanceM
    }
    public var arrived: Bool { arrivedAt != nil }
    /// The walked path, for splitting into progress points.
    public var path: [FloorPoint] { steps.map(\.point) }
}

extension Journey: Codable {
    enum CodingKeys: String, CodingKey {
        case venueId="venue_id", tagId="tag_id", userId="user_id", sessionId="session_id", startedAt="started_at", targetLabel="target_label"
        case steps, obstacles, cueLatencyMs="cue_latency_ms", arrivedAt="arrived_at", arrivalDistanceM="arrival_distance_m"
    }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        self.init(venueId:try c.decodeIfPresent(String.self,forKey:.venueId),tagId:try c.decode(String.self,forKey:.tagId),
                  userId:try c.decodeIfPresent(String.self,forKey:.userId),sessionId:try c.decode(String.self,forKey:.sessionId),
                  startedAt:try c.decode(Date.self,forKey:.startedAt),targetLabel:try c.decode(String.self,forKey:.targetLabel),
                  steps:try c.decodeIfPresent([Step].self,forKey:.steps) ?? [],obstacles:try c.decodeIfPresent([FloorPoint].self,forKey:.obstacles) ?? [],
                  cueLatencyMs:try c.decodeIfPresent([Double].self,forKey:.cueLatencyMs) ?? [],arrivedAt:try c.decodeIfPresent(Date.self,forKey:.arrivedAt),
                  arrivalDistanceM:try c.decodeIfPresent(Double.self,forKey:.arrivalDistanceM))
    }
    /// Every key is written, absent values as null, so a row is the same shape whether or not the walk arrived.
    public func encode(to encoder: Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(venueId,forKey:.venueId); try c.encode(tagId,forKey:.tagId); try c.encode(userId,forKey:.userId); try c.encode(sessionId,forKey:.sessionId)
        try c.encode(startedAt,forKey:.startedAt); try c.encode(targetLabel,forKey:.targetLabel); try c.encode(steps,forKey:.steps)
        try c.encode(obstacles,forKey:.obstacles); try c.encode(cueLatencyMs,forKey:.cueLatencyMs)
        try c.encode(arrivedAt,forKey:.arrivedAt); try c.encode(arrivalDistanceM,forKey:.arrivalDistanceM)
    }
    /// ISO 8601 dates, sorted keys: the same bytes on every run, so a stored journey diffs cleanly.
    public static let encoder: JSONEncoder={ let e=JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting=[.sortedKeys]; return e }()
    public static let decoder: JSONDecoder={ let d=JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

/// Builds a Journey from the per-frame tick: one step per `stepDistance` moved or `stepSeconds` elapsed, the blocked
/// cells seen on the trip, the cue latencies and the arrival. Pure; the phone feeds it poses and packets.
public struct JourneyRecorder: Equatable, Sendable {
    public static let stepDistance = 0.5
    public static let stepSeconds = 2.0
    public private(set) var journey: Journey
    /// The tag's levelled frame the journey is recorded in.
    public let frame: RoomFrame
    /// The target on the frame's floor.
    public let target: FloorPoint
    private let startUptime: Double
    private var lastStep: (position: Vector3, at: Double)?
    private var changedAt: Double?
    private var blocked: Set<FloorGrid.Cell> = []

    /// `target` is the held target's world position. Nil when the tag is not upright on a wall (no levelled frame):
    /// then there is no floor plan to record in.
    public init?(venueId: String?=nil, tagId: String, userId: String?=nil, sessionId: String, startedAt: Date, startUptime: Double, targetLabel: String, target: Vector3, frame: RoomFrame) {
        guard let level=frame.levelled, startUptime.isFinite, target.isFinite else { return nil }
        self.frame=level; self.startUptime=startUptime; self.target=FloorPoint(world:target,in:level)
        journey=Journey(venueId:venueId,tagId:tagId,userId:userId,sessionId:sessionId,startedAt:startedAt,targetLabel:targetLabel)
    }
    public static func == (a: JourneyRecorder, b: JourneyRecorder) -> Bool { a.journey == b.journey && a.frame == b.frame && a.target == b.target }

    /// A pose from the tick. The first sample is always a step; afterwards one per half metre or two seconds.
    public mutating func record(pose: CameraPose, now: Double) { record(pose:pose,now:now,force:false) }
    private mutating func record(pose: CameraPose, now: Double, force: Bool) {
        guard pose.isValid, now.isFinite, now>=startUptime, let heading=frame.heading(of:pose) else { return }
        if let last=lastStep {
            let moved=hypot(pose.position.x-last.position.x,pose.position.z-last.position.z)
            guard force ? (moved>0 || now>last.at) : (moved>=Self.stepDistance || now-last.at>=Self.stepSeconds) else { return }
        }
        let point=FloorPoint(pose:pose,in:frame)
        journey.steps.append(Journey.Step(t:now-startUptime,x:point.x,y:point.y,headingDeg:heading))
        lastStep=(pose.position,now)
    }
    /// Blocked floor-grid cells by their world centres (FloorGrid.center), kept once each as tag-frame cell centres.
    public mutating func noteBlocked(worldCentres: [Vector3], cellSize: Double) {
        guard cellSize.isFinite, cellSize>0 else { return }
        for centre in worldCentres where centre.isFinite {
            let tag=frame.tagPoint(world:centre)
            let cell=FloorGrid.Cell(Int(floor(tag.x/cellSize)),Int(floor(tag.y/cellSize)))
            if blocked.insert(cell).inserted { journey.obstacles.append(FloorPoint(tag.x,tag.y).cellCentre(cellSize:cellSize)) }
        }
    }
    /// The target or the progress point changed: the next packet that shows it closes a latency.
    public mutating func targetChanged(now: Double) { if now.isFinite { changedAt=now } }
    /// A packet showed the target (a column tapped or a cue drawn).
    public mutating func cueShown(now: Double) {
        guard let changedAt, now.isFinite, now>=changedAt else { return }
        journey.cueLatencyMs.append((now-changedAt)*1000); self.changedAt=nil
    }
    /// The walk ended: the last pose, when given, is the last step whatever the step rule says, and the distance from
    /// the last step to the target is kept, with the arrival time when the phone said "there".
    public mutating func end(pose: CameraPose?, now: Double, arrivedAt: Date?) {
        if let pose { record(pose:pose,now:now,force:true) }
        journey.arrivedAt=arrivedAt
        journey.arrivalDistanceM=journey.steps.last.map { $0.point.distance(to:target) }
    }
}

/// Progress points along a path: the first `spacing` metres in, then every `spacing` metres, and the last point is the
/// target. Chalk splits the same way (protocol/journey-v1.json).
public enum ProgressPoints {
    public static let spacing = 6.0
    public static func split(polyline: [FloorPoint], spacing: Double = spacing) -> [FloorPoint] {
        let path=polyline.filter(\.isFinite)
        guard let last=path.last, spacing.isFinite, spacing>0 else { return [] }
        var points: [FloorPoint]=[]
        var next=spacing, walked=0.0
        for (a,b) in zip(path,path.dropFirst()) {
            let length=a.distance(to:b)
            while length>0, walked+length>=next-1e-9 {
                let f=(next-walked)/length
                points.append(FloorPoint(a.x+(b.x-a.x)*f,a.y+(b.y-a.y)*f)); next += spacing
            }
            walked += length
        }
        // The target itself ends the list; a point that landed on it is not repeated.
        if let tail=points.last, tail.distance(to:last)<1e-6 { points.removeLast() }
        points.append(last)
        return points
    }
}

/// Leads the user along progress points: the next point is the target until the user is within `reachRadius` of it,
/// then the one after; the last point is the target itself, and reaching it is arrival.
public struct WaypointFollower: Equatable, Sendable {
    public static let reachRadius = 1.0
    public let points: [FloorPoint]
    public let reachRadius: Double
    public private(set) var index = 0
    public enum Event: Equatable, Sendable { case keep, advanced(Int), arrived }

    public init?(points: [FloorPoint], reachRadius: Double = reachRadius) {
        let usable=points.filter(\.isFinite)
        guard !usable.isEmpty, reachRadius.isFinite, reachRadius>0 else { return nil }
        self.points=usable; self.reachRadius=reachRadius
    }
    public var next: FloorPoint? { index<points.count ? points[index] : nil }
    public var arrived: Bool { index>=points.count }
    public var remaining: Int { max(0,points.count-index) }

    /// Advances past every point within reach, so a user who cut a corner is not sent back.
    public mutating func update(position: FloorPoint) -> Event {
        guard position.isFinite, !arrived else { return .keep }
        let before=index
        while index<points.count, points[index].distance(to:position)<=reachRadius { index += 1 }
        if arrived { return .arrived }
        return index>before ? .advanced(index) : .keep
    }
    /// The next point as the held target the pins point at, placed through the frame the points are in.
    public func target(frame: RoomFrame, label: String, worldEpoch: Int, now: Double) -> HeldTarget? {
        next.map { HeldTarget(position:$0.world(in:frame),label:label,worldEpoch:worldEpoch,setAt:now) }
    }
}
