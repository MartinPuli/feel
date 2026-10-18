import Foundation
import FeelCore

protocol SharedMemoryReading: AnyObject {
    var isEnabled: Bool { get }
    var sessionIdentity: UUID? { get }
    func fetchStructure(venueId: String, tagId: String, completion: @escaping (Result<(map: RoomMap?, visits: Int), ChalkQueryError>) -> Void)
    func fetchAnchors(venueId: String, tagId: String, completion: @escaping (Result<[RoomAnchor], ChalkQueryError>) -> Void)
}
final class ChalkSharedMemory: SharedMemoryReading {
    private let client: ChalkQuerying
    init(client: ChalkQuerying) { self.client = client }
    var isEnabled: Bool { client.isEnabled }
    var sessionIdentity: UUID? { client.sessionIdentity }
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
/// sighting. A confirmed anchor and a kept visit also leave for the shared memory through `uploader`. Main thread.
final class RoomMemory {
    private let store: RoomMemoryStore
    /// Where anchors and room maps go beyond this phone (SupabaseWriter in the app); nil keeps them on the phone only.
    var uploader: MemoryUploading?
    var reader: SharedMemoryReading?
    var venue: () -> String? = { nil }
    var isLive: () -> Bool = { false }
    var onSharedStructure: ((TagSighting) -> Void)?
    /// Root clears a prior seeded from cloud memory when consent/session/venue is invalidated.
    var onSharedInvalidated: (() -> Void)?
    private struct SharedScope: Equatable {
        let account: UUID, venue: String, tag: String, world: Int
    }
    private var sharedScope: SharedScope?
    private var sharedGeneration = UUID()
    private var sharedMap: RoomMap?
    private var sharedAnchors: [RoomAnchor] = []
    private var fetchAfter = Date.distantPast
    private var sharedMessage = "not fetched"
    private var seededShared = false
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
    private var seededMap: RoomMap?
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
        if self.sighting?.tagId != sighting.tagId || self.sighting?.worldEpoch != sighting.worldEpoch { invalidateSharedMemory() }
        if anchorsTagId != sighting.tagId {
            anchors = store.anchors(for: sighting.tagId); structures = store.structures(for: sighting.tagId); anchorsTagId = sighting.tagId
        }
        self.sighting = sighting
    }
    /// The world changed (tracking reset) or sensing stopped: the frame means nothing now, and the floor grid it seeded is gone.
    func forgetTag() { sighting = nil; seeded = nil; invalidateSharedMemory() }

    /// The remembered place of `thing` as a target in the world `worldEpoch` (nil when sensing has no world right
    /// now), or nil, which counts as a miss. Only a tag seen in that same world can place it; the label is matched
    /// the way the anchors table stores it.
    func recall(_ thing: String, worldEpoch: Int?, now uptime: Double) -> HeldTarget? {
        guard let sighting, let worldEpoch, sighting.worldEpoch == worldEpoch, let target = RememberedTarget.remembered(thing, in: effectiveAnchors) else { misses += 1; return nil }
        hits += 1
        return HeldTarget(position: sighting.frame.worldPoint(tag: target.position), label: target.label, worldEpoch: sighting.worldEpoch, setAt: uptime)
    }

    /// Whether `recall` would answer for `thing`, without counting a hit or a miss.
    func remembers(_ thing: String, worldEpoch: Int?) -> Bool {
        guard let sighting, let worldEpoch, sighting.worldEpoch == worldEpoch else { return false }
        return RememberedTarget.remembered(thing, in: effectiveAnchors) != nil
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
        let local = RoomMap.merge(structures)
        let cloud = sharedScope != nil && sharedScope == currentScope() ? sharedMap : nil
        guard let merged = Self.mergePrior(local: local, shared: cloud) else { return nil }
        if let seeded, seeded == (sighting.tagId, sighting.worldEpoch), seededMap == merged { return nil }
        seededMap = merged
        seededShared = cloud != nil
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

    /// Downloaded records are scoped to this live world and account. They never enter local visit history or uploads.
    func fetchSharedStructure(venueId: String?, tagId: String) {
        guard let reader, let scope = currentScope(), scope.tag == tagId,
              venueId == nil || venueId == scope.venue else { return }
        if scope != sharedScope { invalidateSharedMemory(); sharedScope = scope }
        guard now() >= fetchAfter else { return }
        fetchAfter = .distantFuture; sharedMessage = "fetching"
        let generation = sharedGeneration
        reader.fetchStructure(venueId: scope.venue, tagId: tagId) { [weak self] result in
            guard let self, self.matches(scope, generation) else { return }
            switch result {
            case .failure:
                self.fetchAfter = self.now().addingTimeInterval(60); self.sharedMessage = "shared structure unavailable"
            case .success(let value):
                self.sharedMap = value.map
                self.sharedMessage = value.map == nil ? "nothing shared yet" : "shared structure available"
                if value.map != nil, let sighting = self.sighting { self.onSharedStructure?(sighting) }
            }
        }
        reader.fetchAnchors(venueId: scope.venue, tagId: tagId) { [weak self] result in
            guard let self, self.matches(scope, generation) else { return }
            switch result {
            case .failure: self.fetchAfter = self.now().addingTimeInterval(60)
            case .success(let values): self.sharedAnchors = Array(values.filter(\.isUsable).prefix(200))
            }
        }
    }
    func invalidateSharedMemory() {
        let removePrior = seededShared
        sharedGeneration = UUID(); sharedScope = nil; sharedMap = nil; sharedAnchors = []
        fetchAfter = .distantPast; sharedMessage = "not fetched"; seededShared = false
        if removePrior { seeded = nil; onSharedInvalidated?() }
    }
    private func currentScope() -> SharedScope? {
        guard isLive(), let reader, reader.isEnabled, let account = reader.sessionIdentity,
              let venue = venue(), RoomMemoryStore.isTagId(venue), let sighting,
              RoomMemoryStore.isTagId(sighting.tagId), sighting.frame.isValid else { return nil }
        return SharedScope(account: account, venue: venue, tag: sighting.tagId, world: sighting.worldEpoch)
    }
    private func matches(_ scope: SharedScope, _ generation: UUID) -> Bool {
        sharedGeneration == generation && sharedScope == scope && currentScope() == scope
    }
    private var effectiveAnchors: [RoomAnchor] {
        guard sharedScope != nil, sharedScope == currentScope() else { return anchors }
        let ownLabels = Set(anchors.map { RoomAnchor.normalized($0.label) })
        return anchors + sharedAnchors.filter { !ownLabels.contains(RoomAnchor.normalized($0.label)) }
    }
    /// Preserve every locally observed cell; cloud memory fills only locally unknown space, at matching resolution.
    static func mergePrior(local: RoomMap?, shared: RoomMap?) -> RoomMap? {
        guard let local else { return shared }
        guard let shared, local.cellSize == shared.cellSize, let union = RoomMap.merge([local, shared]) else { return local }
        var cells = union.cells
        for y in 0..<union.height { for x in 0..<union.width {
            let own = local.state(ix: union.minIX + x, iy: union.minIY + y)
            if own != .unknown { cells[y * union.width + x] = own }
        } }
        return RoomMap(cellSize: union.cellSize, originX: union.originX, originY: union.originY, width: union.width, height: union.height, cells: cells) ?? local
    }

    /// For get_status: how much of the room's structure is remembered at the tag in use, from how many visits, and
    /// whether the planner was seeded with it in this world.
    var structureStatus: [String: Any] {
        let merged = RoomMap.merge(structures)
        return ["tag": anchorsTagId ?? "none", "visits": structures.count, "cells": merged?.observedCount ?? 0, "blocked": merged?.blockedCount ?? 0,
                "seeded": seeded != nil, "shared": sharedScope != nil && sharedScope == currentScope() ? sharedMessage : "off or unavailable",
                "note": "Remembered structure only seeds the route planner before the camera has seen the room; the pins show live depth."]
    }

    /// For get_status: the tag in use, what is remembered there, and how often memory answered or did not.
    var status: [String: Any] {
        ["tag": sighting?.tagId ?? "none", "remembered": RememberedTarget.remember(effectiveAnchors).map(\.label), "hits": hits, "misses": misses,
         "note": "Remembered places are past sightings at this room's tag; the pins show live depth."]
    }
}
