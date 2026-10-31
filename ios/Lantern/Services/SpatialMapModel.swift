import Foundation
import Combine
import FeelCore

/// Diagnostic geometry only. This path never supplies clearance or tactile commands.
struct SpatialMapUpdate {
    let sessionEpoch: Int
    let worldEpoch: Int
    let chunks: [SpatialMeshChunk]
    let geometryRevision: Int
    let pose: CameraPose?
    let timestamp: TimeInterval
    let tracking: Bool
    let supported: Bool
}

final class SpatialMapModel: ObservableObject {
    enum Mode: String { case stopped, waiting, live, simulation, trackingLost, unsupported }
    @Published private(set) var mode: Mode = .stopped
    @Published private(set) var chunks: [SpatialMeshChunk] = []
    @Published private(set) var pose: CameraPose?
    @Published private(set) var revision = 0
    private(set) var timestamp: TimeInterval?
    private var expectedSession: Int?
    private var worldEpoch = -1
    private var minimumWorldEpoch = -1
    private var geometryRevision = -1
    var triangleCount: Int { chunks.reduce(0) { $0 + $1.triangleCount } }

    func prepare(sessionEpoch: Int) {
        stop(); expectedSession = sessionEpoch; mode = .waiting
    }
    func apply(_ update: SpatialMapUpdate) {
        guard expectedSession == update.sessionEpoch, update.worldEpoch >= worldEpoch, update.worldEpoch >= minimumWorldEpoch,
              update.timestamp.isFinite, timestamp.map({ update.timestamp >= $0 }) ?? true else { return }
        guard update.supported, update.tracking, update.pose?.isValid == true else {
            // Loss of tracking must not preserve a live marker just because the pose is unusable.
            if update.worldEpoch != worldEpoch {
                chunks = []; geometryRevision = -1; revision += 1
            }
            worldEpoch = update.worldEpoch; timestamp = update.timestamp; pose = nil
            mode = update.supported ? .trackingLost : .unsupported
            return
        }
        guard update.worldEpoch != worldEpoch || update.geometryRevision >= geometryRevision else { return }
        let newWorld = update.worldEpoch != worldEpoch
        worldEpoch = update.worldEpoch
        if newWorld || geometryRevision != update.geometryRevision {
            chunks = update.chunks; geometryRevision = update.geometryRevision; revision += 1
        }
        pose = update.pose; timestamp = update.timestamp
        mode = !update.supported ? .unsupported : !update.tracking ? .trackingLost : chunks.isEmpty ? .waiting : .live
    }
    func invalidate() {
        guard expectedSession != nil else { return }
        minimumWorldEpoch = max(minimumWorldEpoch, worldEpoch + 1)
        chunks = []; pose = nil; timestamp = nil; geometryRevision = -1; revision += 1; mode = .trackingLost
    }
    func stop() {
        expectedSession = nil; worldEpoch = -1; minimumWorldEpoch = -1; geometryRevision = -1
        chunks = []; pose = nil; timestamp = nil; mode = .stopped; revision += 1
    }
    func status(at now: TimeInterval) -> String {
        switch mode {
        case .stopped: return "Map stopped"
        case .simulation: return "SIMULATION — synthetic room"
        case .unsupported: return "Scene reconstruction unavailable on this device"
        case .trackingLost: return "Tracking unavailable — retained geometry is not current"
        case .waiting, .live:
            guard let timestamp else { return "Waiting for a live scan" }
            guard now.isFinite, now >= timestamp, now - timestamp <= 0.75 else { return "Scan data is stale — geometry is not current" }
            return mode == .waiting ? "Waiting for observed surfaces" : "Live scan — accumulated surfaces, not clearance"
        }
    }
    func showDemo() {
        stop(); chunks = Self.demoRoom; pose = CameraPose(position: Vector3(0, 1.2, 1.4))
        mode = .simulation; revision += 1
    }
    func toggleDemoTracking() {
        guard expectedSession == nil, !chunks.isEmpty, mode == .simulation || mode == .trackingLost else { return }
        mode = mode == .simulation ? .trackingLost : .simulation
    }
    /// Fixed, generated geometry; never labeled as recorded or sensed.
    static var demoRoom: [SpatialMeshChunk] {
        func quad(_ id: String, _ points: [Vector3], _ classification: UInt8) -> SpatialMeshChunk {
            SpatialMeshChunk(id: UUID(uuidString: id)!, vertices: points,
                             triangleIndices: [0,1,2,0,2,3], classifications: [classification,classification])!
        }
        return [
            quad("00000000-0000-0000-0000-000000000001", [Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)], 2),
            quad("00000000-0000-0000-0000-000000000002", [Vector3(-2,0,-2),Vector3(-2,2.2,-2),Vector3(2,2.2,-2),Vector3(2,0,-2)], 1),
            quad("00000000-0000-0000-0000-000000000003", [Vector3(-2,0,2),Vector3(-2,2.2,2),Vector3(-2,2.2,-2),Vector3(-2,0,-2)], 1),
            quad("00000000-0000-0000-0000-000000000004", [Vector3(0.2,0.5,-0.7),Vector3(0.8,0.5,-0.7),Vector3(0.8,0.5,-0.1),Vector3(0.2,0.5,-0.1)], 6),
            quad("00000000-0000-0000-0000-000000000005", [Vector3(0.2,0.5,-0.7),Vector3(0.2,1.1,-0.7),Vector3(0.8,1.1,-0.7),Vector3(0.8,0.5,-0.7)], 6)
        ]
    }
}
