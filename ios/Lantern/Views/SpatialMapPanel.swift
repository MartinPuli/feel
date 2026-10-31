import SwiftUI
import RealityKit
import FeelCore

struct SpatialMapPanel: View {
    @ObservedObject var map: SpatialMapModel
    @ObservedObject var model: LanternModel
    var showsDiagnostics = false
    var wide = false
    private var isSyntheticMap: Bool { map.mode == .simulation || (map.mode == .trackingLost && model.mode == .stopped) }
    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: FeelSpacing.section))
        layout {
            controls.frame(width: wide ? 220 : nil, alignment: .leading)
            VStack(alignment: .leading, spacing: FeelSpacing.compact) {
                SpatialMapScene(chunks: map.chunks, pose: map.pose, revision: map.revision)
                    .frame(height: wide ? 180 : 200).clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text("Observed surfaces only. Gaps do not mean a clear path.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            }.frame(maxWidth: .infinity)
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(map.status(at: ProcessInfo.processInfo.systemUptime))
                    .font(FeelTypography.label).accessibilityIdentifier("spatialMapStatus")
            }
            if !isSyntheticMap {
                Text(model.status).font(FeelTypography.footnote)
                    .foregroundStyle(FeelTheme.secondary)
                    .accessibilityIdentifier("spatialMapSessionStatus")
            }
            Button("Start live map") { model.startSpatialMap() }
                .buttonStyle(FeelPrimaryButtonStyle()).disabled(!model.supportsSpatialMapping || model.isStarting)
                .accessibilityIdentifier("startSpatialMap")
                .accessibilityHint("Starts a new camera session and normal depth-based tactile guidance. Previous guidance and map alignment are reset.")
            Text("Uses this iPhone's camera and LiDAR. Also runs sensing and any connected puck.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            if !model.supportsSpatialMapping {
                Text("3D scanning is unavailable on this device. A supported LiDAR device is required.")
                    .font(FeelTypography.footnote)
            }
            Text("\(map.chunks.count) surface sections · \(map.triangleCount) triangles")
                .font(FeelTypography.footnote).accessibilityIdentifier("spatialMapCounts")
            Text(isSyntheticMap
                 ? "SIMULATION. Generated room geometry. Camera off; no simulated movement sent to hardware."
                 : "Current-session surfaces can include older observations.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                .accessibilityIdentifier("spatialMapNotice")
            if map.mode != .stopped {
                Button("Stop and clear map", role: .destructive) { model.stop() }
                    .buttonStyle(FeelStopButtonStyle()).accessibilityIdentifier("stopSpatialMap")
            }
            if showsDiagnostics {
                Button("Show simulated room") { model.simulateSpatialMap() }
                    .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("simulateSpatialMap")
                if map.mode == .simulation || (map.mode == .trackingLost && model.mode == .stopped) {
                    Button(map.mode == .simulation ? "Simulate tracking loss" : "Restore simulated tracking") { map.toggleDemoTracking() }
                        .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("spatialMapTracking")
                }
            }
        }
    }
}

/// Non-AR renderer: it does not start another camera session or request camera access.
private struct SpatialMapScene: UIViewRepresentable {
    let chunks: [SpatialMeshChunk]
    let pose: CameraPose?
    let revision: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.07, green: 0.09, blue: 0.08, alpha: 1))
        context.coordinator.attach(to: view)
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(chunks: chunks, pose: pose, revision: revision)
    }
    final class Coordinator {
        let root = AnchorEntity(world: .zero)
        let geometry = Entity()
        let camera = PerspectiveCamera()
        let marker = ModelEntity(mesh: .generateBox(size: [0.10, 0.06, 0.18]),
                                 materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
        var renderedRevision: Int?
        var renderedChunks: [UUID: SpatialMeshChunk] = [:]
        var renderedEntities: [UUID: ModelEntity] = [:]
        func attach(to view: ARView) {
            root.addChild(geometry); root.addChild(camera); root.addChild(marker)
            let light = DirectionalLight()
            light.light.intensity = 2500
            light.look(at: [0,0,0], from: [1,4,3], relativeTo: nil)
            root.addChild(light)
            camera.camera.fieldOfViewInDegrees = 50
            view.scene.addAnchor(root)
        }
        func update(chunks: [SpatialMeshChunk], pose: CameraPose?, revision: Int) {
            if renderedRevision != revision {
                let ids = Set(chunks.map(\.id))
                for id in renderedChunks.keys.filter({ !ids.contains($0) }) {
                    renderedEntities.removeValue(forKey: id)?.removeFromParent()
                    renderedChunks.removeValue(forKey: id)
                }
                for chunk in chunks where renderedChunks[chunk.id] != chunk {
                    renderedEntities.removeValue(forKey: chunk.id)?.removeFromParent()
                    renderedChunks.removeValue(forKey: chunk.id)
                    var descriptor = MeshDescriptor(name: chunk.id.uuidString)
                    descriptor.positions = .init(chunk.vertices.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) })
                    var faces = chunk.triangleIndices
                    if #available(iOS 18.0, *) { } else {
                        // Older RealityKit lacks two-sided materials. Show surfaces from either side.
                        for index in stride(from: 0, to: chunk.triangleIndices.count, by: 3) {
                            faces += [chunk.triangleIndices[index + 2], chunk.triangleIndices[index + 1], chunk.triangleIndices[index]]
                        }
                    }
                    descriptor.primitives = .triangles(faces)
                    if let mesh = try? MeshResource.generate(from: [descriptor]) {
                        let isFloor = chunk.classifications.allSatisfy { $0 == 2 }
                        var material = SimpleMaterial(color: isFloor ? UIColor(white: 0.25, alpha: 1) : UIColor(white: 0.78, alpha: 1), isMetallic: false)
                        if #available(iOS 18.0, *) { material.faceCulling = .none }
                        let entity = ModelEntity(mesh: mesh, materials: [material])
                        geometry.addChild(entity)
                        renderedChunks[chunk.id] = chunk; renderedEntities[chunk.id] = entity
                    }
                }
                renderedRevision = revision
            }
            let p = pose?.position ?? Vector3(0,1.2,1.4)
            let focus = SIMD3<Float>(Float(p.x), Float(p.y) - 0.5, Float(p.z) - 1.0)
            camera.look(at: focus, from: focus + SIMD3<Float>(3.0,4.2,5.0), relativeTo: nil)
            marker.isEnabled = pose != nil
            marker.position = [Float(p.x),Float(p.y),Float(p.z)]
            if let back = pose?.back, let up = pose?.up {
                marker.look(at: marker.position - SIMD3<Float>(Float(back.x),Float(back.y),Float(back.z)),
                            from: marker.position, upVector: [Float(up.x),Float(up.y),Float(up.z)], relativeTo: nil)
            }
        }
    }
}
