import SwiftUI
import ARKit
import FeelCore

struct LanternView: View {
    @ObservedObject var model: LanternModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedPanel: CameraPanel?
    @State private var attemptedInitialStart = false

    private enum CameraPanel: String, Identifiable {
        case settings, connection
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.mode == .live {
                CameraPreview(session: model.perception.session)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            } else if !dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder").font(.system(size: 36, weight: .ultraLight))
                    Text(model.mode == .simulation ? "Simulation · Camera off" : "Camera stopped")
                        .font(FeelTypography.subheadline)
                }
                .foregroundStyle(FeelTheme.secondary)
                .accessibilityIdentifier("cameraPlaceholder")
            }
            VStack(spacing: 0) {
                header
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            PuckView(packet: model.packet)
                            guidance
                        }.padding(16)
                    }
                    .background(Color.black.opacity(0.9))
                    .accessibilityIdentifier("cameraReadingScroll")
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .center, spacing: 20) {
                if !dynamicTypeSize.isAccessibilitySize {
                    PuckView(packet: model.packet, compact: true).frame(width: 210)
                    guidance.frame(maxWidth: .infinity, alignment: .leading)
                }
                sessionAction.frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 160)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.black)
        }
        .font(FeelTypography.body)
        .tint(FeelTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(item: $presentedPanel) { panel in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if panel == .connection {
                            PuckConnectionPanel(puck: model.puck)
                        } else {
                            settings
                        }
                    }.padding(20)
                }
                .accessibilityIdentifier("cameraSettingsScroll")
                .background(FeelTheme.canvas)
                .navigationTitle(panel == .connection ? "Connect puck" : "Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { presentedPanel = nil }.accessibilityIdentifier("closeCameraPanel")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Stop", role: .destructive) {
                        model.stop()
                        presentedPanel = nil
                    }
                    .buttonStyle(FeelStopButtonStyle())
                    .accessibilityIdentifier("panelStop")
                    .padding(16)
                    .background(FeelTheme.surface)
                }
            }
            .font(FeelTypography.body)
            .tint(FeelTheme.accent)
            .preferredColorScheme(.dark)
        }
        .task {
            // Once per screen lifetime: never restart after Stop, a sheet or backgrounding.
            guard !attemptedInitialStart else { return }
            attemptedInitialStart = true
            if !ProcessInfo.processInfo.arguments.contains("--uitesting") { model.startLive() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text("FEEL").font(FeelTypography.headline).accessibilityAddTraits(.isHeader)
            }
            Text(model.mode.rawValue).font(FeelTypography.caption)
                .accessibilityIdentifier("sessionMode")
            Spacer(minLength: 0)
            CameraConnectionButton(puck: model.puck) { presentedPanel = .connection }
            Button { presentedPanel = .settings } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("cameraSettings")
        }
        .padding(.horizontal, 20).padding(.vertical, 4)
        .background(Color.black.opacity(0.85))
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            CameraGuidance(model: model, puck: model.puck)
            if model.mode == .live && !model.calibrated {
                Button("Calibrate") { presentedPanel = .settings }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .accessibilityHint("Enter the measured camera height before starting tactile guidance.")
            }
        }
    }

    @ViewBuilder private var sessionAction: some View {
        if model.mode == .stopped && !model.isStarting {
            Button { model.startLive() } label: { Label("Start camera", systemImage: "camera") }
                .buttonStyle(FeelPrimaryButtonStyle())
                .accessibilityIdentifier("startCamera")
        } else {
            Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(FeelStopButtonStyle())
                .accessibilityIdentifier("stopSession")
                .accessibilityHint("Stops the camera and sends neutral pins if connected.")
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.mode == .live {
                LiveSetup(model: model)
            } else {
                Text("Start the camera to calibrate and choose a target.")
                    .foregroundStyle(FeelTheme.secondary)
            }
            Button("Simulation") {
                model.startSimulation()
                presentedPanel = nil
            }
            .buttonStyle(FeelSecondaryButtonStyle())
            .disabled(model.mode == .simulation)
            Text("Synthetic inputs. No simulated movement is sent to hardware.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.packet.hex).font(FeelTypography.mono).textSelection(.enabled)
                    Text("The dots show the puck, not positions in the camera image. Columns run left to right; rows run from near (wrist) to far (fingers). Filled dots show depth; a ring marks target bearing.")
                    Text("Neutral pins do not mean the area is clear. Unknown depth and lost tracking produce neutral pins. Indoor supervised prototype; use your usual mobility aid.")
                }.font(FeelTypography.footnote).padding(.top, 12)
            }
        }
    }
}

private struct CameraConnectionButton: View {
    @ObservedObject var puck: BluetoothPuck
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            Label(puck.isConnected ? "Connected" : "Connect puck", systemImage: "link")
                .font(FeelTypography.label)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(FeelTheme.inset, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityIdentifier("connectPuck")
        .accessibilityValue(puck.status)
    }
}

private struct CameraGuidance: View {
    @ObservedObject var model: LanternModel
    @ObservedObject var puck: BluetoothPuck

    private var title: String {
        switch model.guidanceState {
        case .stopped: return model.isStarting ? "Opening camera" : "Camera stopped"
        case .live: return model.targetDescription
        case .simulation: return "SIMULATION"
        case .trackingLost: return model.mode == .simulation ? "SIMULATION · Tracking lost" : "Tracking lost · Pins neutral"
        case .staleDepth: return "Waiting for depth · Pins neutral"
        case .invalidFrame: return "Depth unavailable · Pins neutral"
        case .uncalibrated: return "Calibration required · Pins neutral"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FeelTypography.label).accessibilityIdentifier("guidanceTitle")
            if model.mode == .simulation {
                Text("No simulated movement sent to hardware.")
                    .font(FeelTypography.footnote)
                    .accessibilityIdentifier("simulationNotice")
            } else {
                Text(model.status).font(FeelTypography.footnote).accessibilityIdentifier("sessionStatus")
            }
            Text(puck.status).font(FeelTypography.footnote)
                .foregroundStyle(FeelTheme.secondary).accessibilityIdentifier("puckConnectionStatus")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PuckView: View {
    let packet: FeelPacket
    var compact = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Puck").font(FeelTypography.caption)
                Spacer()
                Text("Far").font(FeelTypography.caption).foregroundStyle(FeelTheme.secondary)
            }
            ForEach((1...4).reversed(), id: \.self) { band in
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<7, id: \.self) { column in
                        let active = packet.bands[column] == UInt8(band)
                        let target = active && packet.effectiveHighlight == UInt8(column)
                        Circle()
                            .fill(active ? FeelTheme.accent : FeelTheme.inactivePin)
                            .overlay {
                                if target {
                                    Circle().strokeBorder(FeelTheme.onAccent, lineWidth: compact ? 1.5 : 3).padding(compact ? 2 : 4)
                                }
                            }
                            .frame(maxWidth: compact ? 12 : 22).aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Text("Left")
                Spacer()
                Text("Near")
                Spacer()
                Text("Right")
            }.font(FeelTypography.caption).foregroundStyle(FeelTheme.secondary)
        }
        .padding(compact ? 0 : 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Virtual puck")
        .accessibilityValue(packet.bands.enumerated().map { "Column \($0.offset + 1), band \($0.element)" }.joined(separator: ". ") + (packet.effectiveHighlight < 7 ? ". Target column \(Int(packet.effectiveHighlight) + 1)" : ". No target highlight"))
    }
}

private struct LiveSetup: View {
    @ObservedObject var model: LanternModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeelSection(title: "Floor calibration", systemImage: "viewfinder") {
                Label(model.calibrated ? "Floor calibrated" : "Calibration required", systemImage: model.calibrated ? "checkmark.circle" : "exclamationmark.circle")
                    .font(FeelTypography.label)
                Text("Mount landscape-left: rear camera forward, top edge to your left; keep the phone upright. Measure lens height above the floor.")
                    .font(FeelTypography.subheadline)
                Stepper(value: $model.cameraHeight, in: 0.6...2.1, step: 0.05) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera height").font(FeelTypography.subheadline)
                        Text(model.cameraHeight, format: .number.precision(.fractionLength(2))) + Text(" m")
                    }.monospacedDigit()
                }.accessibilityLabel("Camera height")
                    .accessibilityValue(String(format: "%.2f meters", model.cameraHeight))
                Button(model.calibrated ? "Recalibrate floor" : "Calibrate floor") { model.calibrate() }
                    .buttonStyle(FeelPrimaryButtonStyle())
                Text(model.status)
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calibrationStatus")

            }
            FeelSection(title: "Find a target", systemImage: "scope") {
                Picker("Find", selection: $model.finder) {
                    ForEach(FinderMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode).disabled(mode == .chair && !model.detectorAvailable)
                    }
                }.pickerStyle(.menu)
                Text(model.detectorStatus).font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                if model.finder == .door {
                    Text("Door candidate uses rectangle shape. It cannot confirm a door or a safe opening.").font(FeelTypography.footnote)
                }
                if model.finder == .teammate { PeerPanel(peer: model.peer) }
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct PuckConnectionPanel: View {
    @ObservedObject var puck: BluetoothPuck
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(puck.isConnected ? "Puck connected" : "No puck connected", systemImage: puck.isConnected ? "checkmark.circle" : "link")
                .font(FeelTypography.label)
                .accessibilityIdentifier("puckConnectionStatus")
            Text(puck.status).font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            if puck.isConnected { Text(puck.boardStatus).font(FeelTypography.footnote) }
            Button("Scan again") { puck.scan() }.buttonStyle(FeelSecondaryButtonStyle())
            ForEach(puck.devices, id: \.identifier) { device in
                Button("Connect \(device.name ?? "FEEL puck")") { puck.connect(device) }
                    .buttonStyle(FeelPrimaryButtonStyle())
            }
            Button("Disconnect") { puck.disconnect() }.buttonStyle(FeelSecondaryButtonStyle())
                .accessibilityHint("Also cancels a pending connection.")
            if puck.devices.isEmpty && !puck.isConnected {
                Text("Turn on your puck. Choose it when it appears.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            }
        }
        .onAppear { if !puck.isConnected { puck.scan() } }
        .onDisappear { puck.stopScanning() }
    }
}

struct PeerPanel: View {
    @ObservedObject var peer: NearbyPeerService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(peer.status).font(FeelTypography.subheadline)
            Button("Find Beacon phones") { peer.start() }
                .buttonStyle(FeelSecondaryButtonStyle()).disabled(peer.running)
            Button("Stop finding") { peer.stop() }.buttonStyle(FeelSecondaryButtonStyle())
            if peer.running {
                Text("If no phones appear or the connection fails, stop finding and try again.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            }
            ForEach(peer.peers, id: \.self) { person in
                Button("Find \(person.displayName)") { peer.invite(person) }.buttonStyle(FeelSecondaryButtonStyle())
            }
            Text("The teammate accepts on Beacon. Keep both apps foreground. Direction can be unavailable; no tactile target is sent without a current AR direction.").font(FeelTypography.footnote)
        }
    }
}
