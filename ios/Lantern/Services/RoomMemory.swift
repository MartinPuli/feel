import Foundation
import FeelCore

/// What the phone remembers about the room it is in, keyed by the printed FEEL tag it last recognized: targets
/// confirmed on earlier visits, kept in the tag's frame, so a later "where is the exit?" can point the pins at
/// once instead of taking a photo, and the room's structure (the floor grid earlier sessions learned, FeelCore
/// RoomMap), so the route arrows can plan before the camera has seen the room. Memory only shortcuts the question
/// and seeds the planner; the pins always show live depth, and a remembered place is always spoken as a past
/// sighting. Main thread.
final class RoomMemory {
    private let store: RoomMemoryStore
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

    /// Keep a confirmed target for next time, in the tag frame. Nothing is kept without a tag frame from the target's world.
    @discardableResult
    func confirm(_ target: HeldTarget, confidence: Double) -> RoomAnchor? {
        guard let sighting, sighting.worldEpoch == target.worldEpoch else { return nil }
        let anchor = RoomAnchor(label: RoomAnchor.normalized(target.label), position: sighting.frame.tagPoint(world: target.position), confidence: confidence, seenAt: now())
        guard anchor.isUsable, let kept = try? store.append(anchor, tagId: sighting.tagId) else { return nil }
        anchors = kept
        shareAnchor(anchor, venueId: nil, tagId: sighting.tagId)
        return anchor
    }

    /// The write to the shared memory on Chalk: a Supabase REST insert into the anchors table with the signed-in
    /// user's JWT, `shared` set only when the user opted in. Not wired yet; the local store is the memory until then.
    func shareAnchor(_ anchor: RoomAnchor, venueId: String?, tagId: String) {}

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
        shareStructure(map, venueId: nil, tagId: tagId)
        return true
    }

    /// The upload of one visit to the shared memory on Chalk: a Supabase REST insert into the room_maps table with the
    /// signed-in user's JWT, `shared` set only when the user opted in. Not wired yet; the local store is the memory until then.
    func shareStructure(_ map: RoomMap, venueId: String?, tagId: String) {}

    /// The download of the room's structure as Chalk merged it from shared visits (named query `room_structure`,
    /// `RoomMemory.structure`) into the local store as one more visit, so even a first visit can route. Not wired yet.
    func fetchSharedStructure(venueId: String?, tagId: String) {}

    /// For get_status: how much of the room's structure is remembered at the tag in use, from how many visits, and
    /// whether the planner was seeded with it in this world.
    var structureStatus: [String: Any] {
        let merged = RoomMap.merge(structures)
        return ["tag": anchorsTagId ?? "none", "visits": structures.count, "cells": merged?.observedCount ?? 0, "blocked": merged?.blockedCount ?? 0,
                "seeded": seeded != nil,
                "note": "Remembered structure only seeds the route planner before the camera has seen the room; the pins show live depth."]
    }

    /// For get_status: the tag in use, what is remembered there, and how often memory answered or did not.
    var status: [String: Any] {
        ["tag": sighting?.tagId ?? "none", "remembered": RememberedTarget.remember(anchors).map(\.label), "hits": hits, "misses": misses,
         "note": "Remembered places are past sightings at this room's tag; the pins show live depth."]
    }
}
