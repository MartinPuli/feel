import Foundation
import FeelCore

/// The shared memory read back: the room's structure as Chalk merged it (nil while nobody shared a visit) with the
/// number of visits that voted, and the targets remembered at the tag as anchors. `ChalkMemory` in the app;
/// completions on the main thread.
protocol SharedMemoryReading: AnyObject {
    func fetchStructure(venueId: String, tagId: String, completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void)
    func fetchAnchors(venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void)
}

/// The app's reader: the two named queries over one query client.
final class ChalkSharedMemory: SharedMemoryReading {
    private let client: ChalkQuerying
    init(client: ChalkQuerying) { self.client = client }
    func fetchStructure(venueId: String, tagId: String, completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void) {
        ChalkMemory.roomStructure(client, venueId: venueId, tagId: tagId, completion: completion)
    }
    func fetchAnchors(venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void) {
        ChalkMemory.roomAnchors(client, venueId: venueId, tagId: tagId, completion: completion)
    }
}

/// What the phone remembers about the room it is in, keyed by the printed FEEL tag it last recognized: targets
/// confirmed on earlier visits, kept in the tag's frame, so a later "where is the exit?" can point the pins at
/// once instead of taking a photo, and the room's structure (the floor grid earlier sessions learned, FeelCore
/// RoomMap), so the route arrows can plan before the camera has seen the room. Memory only shortcuts the question
/// and seeds the planner; the pins always show live depth, and a remembered place is always spoken as a past
/// sighting. A confirmed anchor and a kept visit also leave for the shared memory through `uploader`, and what every
/// phone shared comes back through `reader` as one more visit and more sightings in the local store. Main thread.
final class RoomMemory {
    private let store: RoomMemoryStore
    /// Where anchors and room maps go beyond this phone (SupabaseWriter in the app); nil keeps them on the phone only.
    var uploader: MemoryUploading?
    /// Where the shared memory is read back from (Chalk's `room_structure` and `room_anchors`); nil keeps the phone's own stores.
    var reader: SharedMemoryReading?
    /// The venue a room is filed under when `fetchSharedStructure` is given none: the loaded venue pack's; nil (no venue selected) fetches nothing.
    var venue: () -> String? = { nil }
    /// Called on the main thread after a download added to the tag's structure visits, so the planner can be seeded with it.
    var onSharedStructure: ((String) -> Void)?
    /// Tags whose shared memory was fetched this run, so the download happens once per tag; a failure allows one retry a minute later.
    private var fetched: [String: Date] = [:]
    private(set) var sharedStatus = "not fetched"
    static let retryAfterFailure: TimeInterval = 60
    private let now: () -> Date
    /// The tag's frame in the current ARKit world, from the last recognition this session; a tracking reset clears it.
    private(set) var sighting: TagSighting?
    /// What is stored for the tag last seen; stays loaded until another tag is seen.
    private(set) var anchors: [RoomAnchor] = []
    /// The structure visits stored for the tag last seen (RoomMemoryStore.structures), loaded with its anchors.
    private(set) var structures: [RoomMap] = []
    private var anchorsTagId: String?
    /// The planner is seeded once per tag and world; cleared with the tag frame, since the floor grid goes with it.
    private var seeded: (tagId: String, worldEpoch: Int)?
    /// A session that classified fewer cells than this only glanced at the room; it is not a vote on its structure.
    static let minimumVisitCells = 20
    private(set) var hits = 0
    private(set) var misses = 0

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RoomMemory")
    }

    init(store: RoomMemoryStore = RoomMemoryStore(directory: RoomMemory.directory), now: @escaping () -> Date = Date.init) {
        self.store = store; self.now = now
    }

    /// A tag was recognized: load what is remembered at it (once per tag) and keep its frame for this world.
    func sawTag(_ sighting: TagSighting) {
        if anchorsTagId != sighting.tagId {
            anchors = store.anchors(for: sighting.tagId); structures = store.structures(for: sighting.tagId); anchorsTagId = sighting.tagId
        }
        self.sighting = sighting
    }
    /// The world changed (tracking reset) or sensing stopped: the frame means nothing now, and the floor grid it seeded is gone.
    func forgetTag() { sighting = nil; seeded = nil }

    /// The remembered place of `thing` as a target in the world `worldEpoch` (nil when sensing has no world right
    /// now), or nil, which counts as a miss. Only a tag seen in that same world can place it; the label is matched
    /// the way the anchors table stores it.
    func recall(_ thing: String, worldEpoch: Int?, now uptime: Double) -> HeldTarget? {
        guard let sighting, let worldEpoch, sighting.worldEpoch == worldEpoch, let target = RememberedTarget.remembered(thing, in: anchors) else { misses += 1; return nil }
        hits += 1
        return HeldTarget(position: sighting.frame.worldPoint(tag: target.position), label: target.label, worldEpoch: sighting.worldEpoch, setAt: uptime)
    }

    /// Whether `recall` would answer for `thing`, without counting a hit or a miss.
    func remembers(_ thing: String, worldEpoch: Int?) -> Bool {
        guard let sighting, let worldEpoch, sighting.worldEpoch == worldEpoch else { return false }
        return RememberedTarget.remembered(thing, in: anchors) != nil
    }

    /// Keep a confirmed target for next time, in the tag frame. Nothing is kept without a tag frame from the target's world.
    @discardableResult
    func confirm(_ target: HeldTarget, confidence: Double) -> RoomAnchor? {
        guard let sighting, sighting.worldEpoch == target.worldEpoch else { return nil }
        let anchor = RoomAnchor(label: RoomAnchor.normalized(target.label), position: sighting.frame.tagPoint(world: target.position), confidence: confidence, seenAt: now())
        guard anchor.isUsable, let kept = try? store.append(anchor, tagId: sighting.tagId) else { return nil }
        anchors = kept
        uploader?.upload(anchor: anchor, tagId: sighting.tagId)
        return anchor
    }

    // MARK: Room structure

    /// The merged structure of earlier visits for the route planner, the first time this tag is seen in this world
    /// (every world starts with an empty floor grid); nil afterwards, and nil while no visit is stored. The planner uses
    /// it only where the camera has not classified a cell yet.
    func structureToSeed(for sighting: TagSighting) -> RoomMap? {
        guard anchorsTagId == sighting.tagId else { return nil }
        if let seeded, seeded == (sighting.tagId, sighting.worldEpoch) { return nil }
        guard let merged = RoomMap.merge(structures) else { return nil }
        seeded = (sighting.tagId, sighting.worldEpoch)
        return merged
    }

    /// What the camera saw this session, kept as one more visit to the room behind `tagId` when it saw enough of it;
    /// the newest ten visits stay (RoomMemoryStore.keepStructures). Nothing here reaches the pins.
    @discardableResult
    func keepStructure(_ map: RoomMap, tagId: String) -> Bool {
        guard map.observedCount >= Self.minimumVisitCells, let kept = try? store.appendStructure(map, tagId: tagId) else { return false }
        if anchorsTagId == tagId { structures = kept }
        uploader?.upload(structure: map, tagId: tagId, seenAt: now())
        return true
    }

    /// The download of the room's structure as Chalk merged it from shared visits (named query `room_structure`,
    /// `RoomMemory.structure`) into the local store as one more visit, so even a first visit can route, and of the
    /// targets remembered there (`room_anchors`) as sightings the local store did not have. Once per tag per run;
    /// nothing happens without a `reader`. The merged map counts as one visit among this phone's own, and the same
    /// map is never stored twice, so a phone that visits daily keeps its own ten visits and Chalk's current vote.
    func fetchSharedStructure(venueId: String?, tagId: String) {
        guard let reader else { return }
        guard let venue = venueId ?? self.venue() else { sharedStatus = "no venue selected"; return }
        let at = now()
        if let last = fetched[tagId], at < last { return }
        fetched[tagId] = .distantFuture
        sharedStatus = "fetching"
        reader.fetchStructure(venueId: venue, tagId: tagId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.fetched[tagId] = self.now().addingTimeInterval(Self.retryAfterFailure)
                self.sharedStatus = "failed: \(error)"
            case .success(let shared):
                self.sharedStatus = shared.map == nil ? "nothing shared yet" : "\(shared.visits) shared visit\(shared.visits == 1 ? "" : "s") merged"
                guard let map = shared.map else { return }
                let existing = self.anchorsTagId == tagId ? self.structures : self.store.structures(for: tagId)
                guard !existing.contains(map), let kept = try? self.store.appendStructure(map, tagId: tagId) else { return }
                if self.anchorsTagId == tagId { self.structures = kept }
                self.onSharedStructure?(tagId)
            }
        }
        reader.fetchAnchors(venueId: venue, tagId: tagId) { [weak self] result in
            guard let self, case .success(let shared) = result else { return }
            var kept = self.anchorsTagId == tagId ? self.anchors : self.store.anchors(for: tagId)
            for anchor in shared where !kept.contains(anchor) {
                guard let next = try? self.store.append(anchor, tagId: tagId) else { break }
                kept = next
            }
            if self.anchorsTagId == tagId { self.anchors = kept }
        }
    }

    /// For get_status: how much of the room's structure is remembered at the tag in use, from how many visits, whether
    /// the planner was seeded with it in this world, and what the download of the shared structure did.
    var structureStatus: [String: Any] {
        let merged = RoomMap.merge(structures)
        return ["tag": anchorsTagId ?? "none", "visits": structures.count, "cells": merged?.observedCount ?? 0, "blocked": merged?.blockedCount ?? 0,
                "seeded": seeded != nil, "shared": reader == nil ? "no reader in this build" : sharedStatus,
                "note": "Remembered structure only seeds the route planner before the camera has seen the room; the pins show live depth."]
    }

    /// For get_status: the tag in use, what is remembered there, and how often memory answered or did not.
    var status: [String: Any] {
        ["tag": sighting?.tagId ?? "none", "remembered": RememberedTarget.remember(anchors).map(\.label), "hits": hits, "misses": misses,
         "note": "Remembered places are past sightings at this room's tag; the pins show live depth."]
    }
}
