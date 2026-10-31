import XCTest
@testable import FeelCore

final class SpatialMeshTests: XCTestCase {
    private let vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]
    private func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
    private func chunk(_ number: Int, triangles: Int = 1, classification: UInt8 = 2) -> SpatialMeshChunk {
        SpatialMeshChunk(id: id(number), vertices: vertices,
            triangleIndices: Array(repeating: [UInt32(0), 1, 2], count: triangles).flatMap { $0 },
            classifications: Array(repeating: classification, count: triangles))!
    }
    private func store(maxChunks: Int = 64, maxTriangles: Int = 80_000) -> SpatialMeshStore {
        var result = SpatialMeshStore(maxChunks: maxChunks, maxTriangles: maxTriangles)
        result.reset(sessionEpoch: 1, worldEpoch: 2)
        return result
    }

    func testAcceptsWorldGeometryAndPreservesUnknownClassification() throws {
        let value = chunk(1, classification: 255)
        XCTAssertEqual(value.vertices, vertices)
        XCTAssertEqual(value.triangleCount, 1)
        XCTAssertEqual(value.classifications, [255])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(SpatialMeshChunk.self, from: data), value)
    }

    func testRejectsMissingOrMismatchedTopology() {
        for indices: [UInt32] in [[], [0], [0, 1], [0, 1, 3], [0, 1, .max]] {
            XCTAssertNil(SpatialMeshChunk(id: id(1), vertices: vertices, triangleIndices: indices,
                classifications: [2]), "Invalid indices: \(indices)")
        }
        for classes: [UInt8] in [[], [2, 2]] {
            XCTAssertNil(SpatialMeshChunk(id: id(1), vertices: vertices,
                triangleIndices: [0, 1, 2], classifications: classes))
        }
        XCTAssertNil(SpatialMeshChunk(id: id(1), vertices: Array(vertices.prefix(2)),
            triangleIndices: [0, 1, 1], classifications: [2]))
    }

    func testRejectsNonfiniteCoordinatesOnEveryAxis() {
        for invalid in [Double.nan, .infinity, -.infinity] {
            for point in [Vector3(invalid, 0, 0), Vector3(0, invalid, 0), Vector3(0, 0, invalid)] {
                var input = vertices
                input[1] = point
                XCTAssertNil(SpatialMeshChunk(id: id(1), vertices: input,
                    triangleIndices: [0, 1, 2], classifications: [2]))
            }
        }
    }

    func testRejectsOversizedGeometryAndAcceptsBoundary() {
        XCTAssertEqual(chunk(1, triangles: SpatialMeshChunk.maximumTriangles).triangleCount, 5_000)
        XCTAssertNil(SpatialMeshChunk(id: id(1), vertices: vertices,
            triangleIndices: Array(repeating: [UInt32(0), 1, 2], count: 5_001).flatMap { $0 },
            classifications: Array(repeating: 2, count: 5_001)))
        XCTAssertNil(SpatialMeshChunk(id: id(1), vertices: Array(repeating: .zero, count: 15_001),
            triangleIndices: [0, 1, 2], classifications: [2]))
    }

    func testDecodedInvalidMeshCannotBypassValidation() throws {
        let encoded = try JSONEncoder().encode(chunk(1))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["triangleIndices"] = [0, 1, 9]
        let invalid = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(SpatialMeshChunk.self, from: invalid))
    }

    func testRequiresExplicitWorldAndResetClearsGeometry() {
        var cache = SpatialMeshStore()
        XCTAssertFalse(cache.upsert(chunk(1), sessionEpoch: 0, worldEpoch: 0))
        XCTAssertTrue(cache.snapshot.isEmpty)
        cache.reset(sessionEpoch: 1, worldEpoch: 2)
        XCTAssertTrue(cache.upsert(chunk(1), sessionEpoch: 1, worldEpoch: 2))
        cache.reset(sessionEpoch: 1, worldEpoch: 3)
        XCTAssertTrue(cache.snapshot.isEmpty)
        XCTAssertEqual(cache.triangleCount, 0)
        XCTAssertEqual(cache.worldEpoch, 3)
    }

    func testStaleSessionAndWorldCannotReplaceOrRemoveCurrentGeometry() {
        var cache = store()
        cache.upsert(chunk(1), sessionEpoch: 1, worldEpoch: 2)
        let before = cache
        for (session, world) in [(0, 2), (1, 1), (2, 2), (1, 3)] {
            XCTAssertFalse(cache.upsert(chunk(1, triangles: 2), sessionEpoch: session, worldEpoch: world))
            XCTAssertFalse(cache.remove(id: id(1), sessionEpoch: session, worldEpoch: world))
            XCTAssertFalse(cache.invalidate(id: id(1), sessionEpoch: session, worldEpoch: world))
            XCTAssertFalse(cache.upsert(id: id(1), vertices: [], triangleIndices: [], classifications: [],
                sessionEpoch: session, worldEpoch: world))
        }
        XCTAssertEqual(cache, before)
    }

    func testInvalidReplacementRemovesOldChunkWithoutDroppingOthers() {
        var cache = store()
        cache.upsert(chunk(1, triangles: 2), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(2), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertFalse(cache.upsert(id: id(1), vertices: vertices, triangleIndices: [0, 1, 20],
            classifications: [2], sessionEpoch: 1, worldEpoch: 2))
        XCTAssertEqual(cache.snapshot, [chunk(2)])
        XCTAssertEqual(cache.triangleCount, 1)
    }

    func testReplacementAndRemovalMaintainCountsAndSnapshotOrder() {
        var cache = store()
        cache.upsert(chunk(3), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(1), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(2), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(1, triangles: 3), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertEqual(cache.snapshot.map(\.id), [id(1), id(2), id(3)])
        XCTAssertEqual(cache.chunkCount, 3)
        XCTAssertEqual(cache.triangleCount, 5)
        XCTAssertTrue(cache.remove(id: id(1), sessionEpoch: 1, worldEpoch: 2))
        XCTAssertFalse(cache.remove(id: id(1), sessionEpoch: 1, worldEpoch: 2))
        XCTAssertEqual(cache.triangleCount, 2)
    }

    func testChunkCapacityEvictsOldestUpdateDeterministically() {
        var cache = store(maxChunks: 2)
        cache.upsert(chunk(3), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(1), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(3), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(2), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertEqual(cache.snapshot.map(\.id), [id(2), id(3)], "Updated chunk 3 is newer than chunk 1")
        XCTAssertEqual(cache.triangleCount, 2)
    }

    func testTriangleCapacityEvictsUntilEntireChunkFits() {
        var cache = store(maxTriangles: 5)
        for number in 1...3 { cache.upsert(chunk(number), sessionEpoch: 1, worldEpoch: 2) }
        cache.upsert(chunk(4, triangles: 4), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertEqual(cache.snapshot.map(\.id), [id(3), id(4)])
        XCTAssertEqual(cache.triangleCount, 5)
        XCTAssertFalse(cache.upsert(chunk(4, triangles: 6), sessionEpoch: 1, worldEpoch: 2))
        XCTAssertEqual(cache.snapshot, [chunk(3)], "An oversized replacement must not keep its old geometry")
    }

    func testGlobalCapsCannotBeRaisedByConfiguration() {
        var cache = store(maxChunks: .max, maxTriangles: .max)
        XCTAssertEqual(cache.chunkLimit, 64)
        XCTAssertEqual(cache.triangleLimit, 80_000)
        for number in 1...65 { cache.upsert(chunk(number), sessionEpoch: 1, worldEpoch: 2) }
        XCTAssertEqual(cache.chunkCount, 64)
        XCTAssertFalse(cache.snapshot.contains { $0.id == id(1) })
        cache.reset(sessionEpoch: 1, worldEpoch: 3)
        for number in 1...17 { cache.upsert(chunk(number, triangles: 5_000), sessionEpoch: 1, worldEpoch: 3) }
        XCTAssertEqual(cache.chunkCount, 16)
        XCTAssertEqual(cache.triangleCount, 80_000)
        XCTAssertFalse(cache.snapshot.contains { $0.id == id(1) })
    }

    func testEmptyAndFloorOnlyMeshesAreJustGeometryWithoutClearanceInference() {
        var cache = store()
        XCTAssertEqual(cache.snapshot, [])
        cache.upsert(chunk(1, classification: 2), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertEqual(cache.snapshot, [chunk(1, classification: 2)])
        XCTAssertTrue(cache.invalidate(id: id(1), sessionEpoch: 1, worldEpoch: 2))
        XCTAssertEqual(cache.snapshot, [])
        XCTAssertEqual(cache.triangleCount, 0)
    }

    func testFrameMembershipRemovesGeometryEvenWithoutRemovalCallback() {
        var cache = store()
        cache.upsert(chunk(1, triangles: 2), sessionEpoch: 1, worldEpoch: 2)
        cache.upsert(chunk(2), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertTrue(cache.retain(ids: [id(2), id(3)], sessionEpoch: 1, worldEpoch: 2))
        XCTAssertEqual(cache.snapshot, [chunk(2)]); XCTAssertEqual(cache.triangleCount, 1)
        XCTAssertFalse(cache.retain(ids: [id(2)], sessionEpoch: 1, worldEpoch: 2))
        XCTAssertTrue(cache.retain(ids: [], sessionEpoch: 1, worldEpoch: 2))
        XCTAssertEqual(cache.triangleCount, 0)
    }

    func testOldFrameMembershipCannotRemoveCurrentWorld() {
        var cache = store(); cache.upsert(chunk(1), sessionEpoch: 1, worldEpoch: 2)
        XCTAssertFalse(cache.retain(ids: [], sessionEpoch: 0, worldEpoch: 2))
        XCTAssertFalse(cache.retain(ids: [], sessionEpoch: 1, worldEpoch: 1))
        XCTAssertEqual(cache.snapshot, [chunk(1)])
    }
}
