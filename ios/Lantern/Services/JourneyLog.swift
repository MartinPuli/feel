import Foundation
import FeelCore

/// Every walk toward a chosen target, as a Journey (FeelCore Journey.swift) in the frame of the printed room tag: the
/// poses, the blocked cells seen on the way, the cue latencies and the arrival. A journey starts when a target is
/// chosen while a tag has been seen in this world and ends on arrival, stop, tracking loss or a target change. Each
/// one is kept as JSON under Application Support (beside RoomMemory) and `export` writes them all to Documents as one
/// array for the Files app. Each kept journey also leaves for the shared memory through `uploader` (the journeys table
/// Chalk reads). Nothing here reaches the pins. Main thread.
final class JourneyLog {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Journeys", isDirectory: true)
    }
    /// Files app → On My iPhone → FEEL → journeys.json (the app lists its Documents folder there).
    static var exportFile: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("journeys.json")
    }
    /// A walk is at least two steps: the starting pose alone says nothing about the way.
    static let minimumSteps = 2

    let directory: URL
    let exportFile: URL
    /// Where kept journeys go beyond this phone (SupabaseWriter in the app); nil keeps them on the phone only.
    var uploader: MemoryUploading?
    private let now: () -> Date
    /// One id per app run; every journey of the run carries it.
    let sessionId = UUID().uuidString.lowercased()
    private(set) var current: JourneyRecorder?
    /// Journeys kept so far: the stored ones, loaded once, then each one that ends.
    private(set) var journeys: [Journey]
    /// Walks that ended with too few steps to keep, for get_status.
    private(set) var dropped = 0

    init(directory: URL = JourneyLog.directory, exportFile: URL = JourneyLog.exportFile, now: @escaping () -> Date = Date.init) {
        self.directory = directory; self.exportFile = exportFile; self.now = now
        journeys = Self.load(directory)
    }
    private static func load(_ directory: URL) -> [Journey] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { file in (try? Data(contentsOf: file)).flatMap { try? Journey.decoder.decode(Journey.self, from: $0) } }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var isRecording: Bool { current != nil }

    /// A target was chosen with the tag seen in its world: a new journey replaces any current one (which ends unarrived).
    /// False, and nothing recorded, when the tag is not upright on a wall.
    @discardableResult
    func begin(targetLabel: String, target: Vector3, sighting: TagSighting, venueId: String? = nil, userId: String? = nil, startUptime: Double) -> Bool {
        end(arrived: false, pose: nil, now: startUptime)
        current = JourneyRecorder(venueId: venueId, tagId: sighting.tagId, userId: userId, sessionId: sessionId, startedAt: now(), startUptime: startUptime,
                                  targetLabel: targetLabel, target: target, frame: sighting.frame)
        return current != nil
    }
    func record(pose: CameraPose, now: Double) { current?.record(pose: pose, now: now) }
    func noteBlocked(worldCentres: [Vector3], cellSize: Double) { current?.noteBlocked(worldCentres: worldCentres, cellSize: cellSize) }
    func targetChanged(now: Double) { current?.targetChanged(now: now) }
    func cueShown(now: Double) { current?.cueShown(now: now) }

    /// Ends the current journey at `pose` (the last step, when known), arrived or not, and keeps it when it is a walk.
    /// Returns the journey kept, or nil when there was none or it was too short.
    @discardableResult
    func end(arrived: Bool, pose: CameraPose?, now: Double) -> Journey? {
        guard var recorder = current else { return nil }
        current = nil
        recorder.end(pose: pose, now: now, arrivedAt: arrived ? self.now() : nil)
        let journey = recorder.journey
        guard journey.steps.count >= Self.minimumSteps else { dropped += 1; return nil }
        journeys.append(journey)
        try? persist(journey)
        uploader?.upload(journey: journey)
        return journey
    }
    private static let fileStamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; return f
    }()
    /// `<started_at>-<session>.json`, written atomically, so a failed write leaves no half file.
    func file(for journey: Journey) -> URL {
        directory.appendingPathComponent("\(Self.fileStamp.string(from: journey.startedAt))-\(journey.sessionId.prefix(8)).json")
    }
    private func persist(_ journey: Journey) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Journey.encoder.encode(journey).write(to: file(for: journey), options: .atomic)
    }

    /// All journeys as one JSON array in Documents (Files app → FEEL → journeys.json), newest last. Returns the file.
    @discardableResult
    func export() throws -> URL {
        try FileManager.default.createDirectory(at: exportFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Journey.encoder.encode(journeys).write(to: exportFile, options: .atomic)
        return exportFile
    }

    /// For get_status: whether a journey is being recorded, its target and what it holds so far, and how many are stored.
    var status: [String: Any] {
        let journey = current?.journey
        return ["active": journey != nil, "target": journey?.targetLabel ?? "none", "steps": journey?.steps.count ?? 0,
                "obstacles": journey?.obstacles.count ?? 0, "cue_latencies": journey?.cueLatencyMs.count ?? 0,
                "stored": journeys.count, "export": exportFile.lastPathComponent,
                "note": "A journey records the walk for later; the pins show live depth, and a route is a suggested direction, never a clear path."]
    }
}
