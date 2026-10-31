import ARKit
import FeelCore

/// Queue-confined adapter. Copies ARKit buffers before they can be updated again.
/// Mesh is inspection data only, never evidence that unobserved space is clear.
final class ARSpatialMapCapture {
    private var store = SpatialMeshStore()
    private var sessionEpoch = 0
    private var worldEpoch = 0
    private var revision = 0
    private var lastPublished: TimeInterval = -.infinity
    private(set) var enabled = false
    private var supported = false
    private var pendingIDs: Set<UUID> = []
    private var pendingOrder: [UUID] = []

    func begin(sessionEpoch: Int, worldEpoch: Int, enabled: Bool, supported: Bool) {
        self.sessionEpoch = sessionEpoch; self.worldEpoch = worldEpoch
        self.enabled = enabled; self.supported = supported
        store.reset(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch)
        pendingIDs = []; pendingOrder = []; revision += 1; lastPublished = -.infinity
    }
    func stop() {
        enabled = false; pendingIDs = []; pendingOrder = []; store.reset(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch); revision += 1
    }
    func upsert(_ anchors: [ARAnchor]) {
        guard enabled, supported else { return }
        // Queue IDs, never ARKit buffers. FIFO order prevents frequently updated anchors starving others.
        for case let anchor as ARMeshAnchor in anchors where pendingOrder.count < 128 {
            if pendingIDs.insert(anchor.identifier).inserted { pendingOrder.append(anchor.identifier) }
        }
    }
    func remove(_ anchors: [ARAnchor]) {
        guard enabled else { return }
        for case let anchor as ARMeshAnchor in anchors {
            pendingIDs.remove(anchor.identifier); pendingOrder.removeAll { $0 == anchor.identifier }
            if store.remove(id: anchor.identifier, sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) { revision += 1 }
        }
    }
    func observation(pose: CameraPose, timestamp: TimeInterval, tracking: Bool, anchors: [ARAnchor]) -> SpatialMapUpdate? {
        guard enabled, timestamp.isFinite, timestamp - lastPublished >= 0.2 else { return nil }
        lastPublished = timestamp
        if tracking {
            let current = Dictionary(uniqueKeysWithValues: anchors.compactMap { ($0 as? ARMeshAnchor).map { ($0.identifier, $0) } })
            let currentIDs = Set(current.keys)
            if store.retain(ids: currentIDs, sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) { revision += 1 }
            pendingIDs.formIntersection(currentIDs)
            pendingOrder.removeAll { !currentIDs.contains($0) }
            let batch = Array(pendingOrder.prefix(6)); pendingOrder.removeFirst(batch.count)
            for id in batch {
                pendingIDs.remove(id)
                if let anchor = current[id], let chunk = Self.copy(anchor) {
                    _ = store.upsert(chunk, sessionEpoch: sessionEpoch, worldEpoch: worldEpoch)
                } else { _ = store.invalidate(id: id, sessionEpoch: sessionEpoch, worldEpoch: worldEpoch) }
                revision += 1
            }
        }
        return SpatialMapUpdate(sessionEpoch: sessionEpoch, worldEpoch: worldEpoch, chunks: store.snapshot,
                                geometryRevision: revision, pose: pose, timestamp: timestamp,
                                tracking: tracking, supported: supported)
    }
    private static func copy(_ anchor: ARMeshAnchor) -> SpatialMeshChunk? {
        let mesh = anchor.geometry, vertices = mesh.vertices, faces = mesh.faces
        guard vertices.format == .float3, vertices.count > 0, faces.count > 0,
              faces.indexCountPerPrimitive == 3, [2,4].contains(faces.bytesPerIndex) else { return nil }
        // Bounded diagnostic decimation. Missing triangles are unknown, never free space.
        let step = max(1, (faces.count + 2999) / 3000)
        var points: [Vector3] = [], indices: [UInt32] = [], classes: [UInt8] = []
        var remap: [Int: UInt32] = [:]
        for face in stride(from: 0, to: faces.count, by: step) {
            for corner in 0..<3 {
                let indexOffset = (face * 3 + corner) * faces.bytesPerIndex
                guard indexOffset >= 0, indexOffset + faces.bytesPerIndex <= faces.buffer.length else { return nil }
                let ptr = faces.buffer.contents().advanced(by: indexOffset)
                let index = faces.bytesPerIndex == 4 ? Int(ptr.loadUnaligned(as: UInt32.self)) : Int(ptr.loadUnaligned(as: UInt16.self))
                guard index < vertices.count else { return nil }
                if let existing = remap[index] { indices.append(existing); continue }
                let offset = vertices.offset + vertices.stride * index
                guard offset >= 0, offset + 12 <= vertices.buffer.length else { return nil }
                let v = vertices.buffer.contents().advanced(by: offset)
                let p = SIMD4<Float>(v.loadUnaligned(as: Float.self), v.advanced(by: 4).loadUnaligned(as: Float.self),
                                     v.advanced(by: 8).loadUnaligned(as: Float.self), 1)
                let world = anchor.transform * p
                let newIndex = UInt32(points.count); remap[index] = newIndex; indices.append(newIndex)
                points.append(Vector3(Double(world.x), Double(world.y), Double(world.z)))
            }
            if let source = mesh.classification {
                let offset = source.offset + source.stride * face
                guard face < source.count, offset >= 0, offset < source.buffer.length else { return nil }
                classes.append(source.buffer.contents().advanced(by: offset).load(as: UInt8.self))
            } else { classes.append(0) }
        }
        return SpatialMeshChunk(id: anchor.identifier, vertices: points, triangleIndices: indices, classifications: classes)
    }
}
