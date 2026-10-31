import Foundation

/// A bounded, immutable diagnostic surface mesh in AR world coordinates, in metres.
/// Surface geometry does not establish free space or provide tactile guidance.
public struct SpatialMeshChunk: Equatable, Sendable, Codable {
    public static let maximumTriangles = 5_000
    public static let maximumVertices = 15_000

    public let id: UUID
    public let vertices: [Vector3]
    public let triangleIndices: [UInt32]
    /// One ARKit classification raw value per triangle. Unknown future values remain representable.
    public let classifications: [UInt8]
    public var triangleCount: Int { triangleIndices.count / 3 }

    public init?(id: UUID, vertices: [Vector3], triangleIndices: [UInt32], classifications: [UInt8]) {
        guard vertices.count >= 3, vertices.count <= Self.maximumVertices,
              !triangleIndices.isEmpty, triangleIndices.count <= Self.maximumTriangles * 3,
              triangleIndices.count.isMultiple(of: 3),
              classifications.count == triangleIndices.count / 3,
              vertices.allSatisfy(\.isFinite),
              triangleIndices.allSatisfy({ UInt64($0) < UInt64(vertices.count) }) else { return nil }
        self.id = id
        self.vertices = vertices
        self.triangleIndices = triangleIndices
        self.classifications = classifications
    }

    private enum CodingKeys: String, CodingKey { case id, vertices, triangleIndices, classifications }

    /// Decoding uses the same checks as live input instead of bypassing the geometry invariant.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(UUID.self, forKey: .id)
        let vertices = try values.decode([Vector3].self, forKey: .vertices)
        let indices = try values.decode([UInt32].self, forKey: .triangleIndices)
        let classes = try values.decode([UInt8].self, forKey: .classifications)
        guard let chunk = Self(id: id, vertices: vertices, triangleIndices: indices, classifications: classes) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid or oversized spatial mesh chunk"))
        }
        self = chunk
    }
}

/// Session-owned geometry cache for inspection only. Pose and observation freshness belong to the caller.
/// No mesh (including a floor-only mesh) is interpreted as evidence of a clear corridor here.
public struct SpatialMeshStore: Equatable, Sendable {
    public static let maximumChunks = 64
    public static let maximumTriangles = 80_000

    public let chunkLimit: Int
    public let triangleLimit: Int
    public private(set) var sessionEpoch: Int?
    public private(set) var worldEpoch: Int?
    private var chunks: [UUID: SpatialMeshChunk] = [:]
    /// Oldest update first. An explicit order avoids timestamp ties and counter overflow.
    private var updateOrder: [UUID] = []
    public private(set) var triangleCount = 0
    public var chunkCount: Int { chunks.count }
    public var snapshot: [SpatialMeshChunk] {
        chunks.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Smaller limits are useful for constrained viewers; larger values cannot bypass the global caps.
    public init(maxChunks: Int = Self.maximumChunks, maxTriangles: Int = Self.maximumTriangles) {
        chunkLimit = min(Self.maximumChunks, max(1, maxChunks))
        triangleLimit = min(Self.maximumTriangles, max(1, maxTriangles))
    }

    public mutating func reset(sessionEpoch: Int, worldEpoch: Int) {
        self.sessionEpoch = sessionEpoch
        self.worldEpoch = worldEpoch
        chunks.removeAll(keepingCapacity: true)
        updateOrder.removeAll(keepingCapacity: true)
        triangleCount = 0
    }

    /// An invalid replacement removes the prior same-ID chunk, rather than presenting it as updated evidence.
    /// Updates from another session or world never remove current geometry.
    @discardableResult
    public mutating func upsert(id: UUID, vertices: [Vector3], triangleIndices: [UInt32],
                                classifications: [UInt8], sessionEpoch: Int, worldEpoch: Int) -> Bool {
        guard accepts(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) else { return false }
        guard let chunk = SpatialMeshChunk(id: id, vertices: vertices, triangleIndices: triangleIndices,
                                           classifications: classifications) else {
            discard(id)
            return false
        }
        return upsert(chunk, sessionEpoch: sessionEpoch, worldEpoch: worldEpoch)
    }

    @discardableResult
    public mutating func upsert(_ chunk: SpatialMeshChunk, sessionEpoch: Int, worldEpoch: Int) -> Bool {
        guard accepts(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) else { return false }
        discard(chunk.id)
        guard chunk.triangleCount <= triangleLimit else { return false }
        while chunks.count >= chunkLimit || triangleCount > triangleLimit - chunk.triangleCount {
            guard let oldest = updateOrder.first else { return false }
            discard(oldest)
        }
        chunks[chunk.id] = chunk
        updateOrder.append(chunk.id)
        triangleCount += chunk.triangleCount
        return true
    }

    /// Returns whether an existing chunk was removed in the current world.
    @discardableResult
    public mutating func remove(id: UUID, sessionEpoch: Int, worldEpoch: Int) -> Bool {
        guard accepts(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) else { return false }
        return discard(id)
    }

    /// Use when an ARKit adapter cannot construct a valid replacement chunk.
    @discardableResult
    public mutating func invalidate(id: UUID, sessionEpoch: Int, worldEpoch: Int) -> Bool {
        remove(id: id, sessionEpoch: sessionEpoch, worldEpoch: worldEpoch)
    }

    /// Reconcile against a complete current-frame anchor set if an individual removal callback was missed.
    /// Anchor membership does not establish how recently each retained surface was observed.
    @discardableResult
    public mutating func retain(ids: Set<UUID>, sessionEpoch: Int, worldEpoch: Int) -> Bool {
        guard accepts(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) else { return false }
        let absent = chunks.keys.filter { !ids.contains($0) }
        for id in absent { discard(id) }
        return !absent.isEmpty
    }

    private func accepts(sessionEpoch: Int, worldEpoch: Int) -> Bool {
        self.sessionEpoch == sessionEpoch && self.worldEpoch == worldEpoch
    }

    @discardableResult
    private mutating func discard(_ id: UUID) -> Bool {
        guard let previous = chunks.removeValue(forKey: id) else { return false }
        triangleCount -= previous.triangleCount
        updateOrder.removeAll { $0 == id }
        return true
    }
}
