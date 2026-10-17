import SwiftUI
import ARKit
import FeelCore

struct LanternView: View {
    @ObservedObject var model: LanternModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if dynamicTypeSize.isAccessibilitySize {
                            SessionStartControls(model: model, stacked: true)
                        }
                        let columns = geometry.size.width >= 720 && !dynamicTypeSize.isAccessibilitySize
                            ? [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]
                            : [GridItem(.flexible(), alignment: .top)]
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            overview
                            setup
                        }
                        diagnostics
                    }
                    .padding(20)
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("sessionScroll")
            }
            .background(FeelTheme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) { SessionControls(model: model) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(FeelTheme.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("FEEL").font(.title2.weight(.bold)).tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Label(model.mode.rawValue, systemImage: model.mode == .simulation ? "play.rectangle" : model.mode == .live ? "viewfinder" : "pause.circle")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(FeelTheme.accent)
                .background(FeelTheme.accent.opacity(0.10), in: Capsule())
                .accessibilityIdentifier("sessionMode")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            PuckView(packet: model.packet)
            Text(model.targetDescription)
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("targetStatus")
            Text("Neutral pins do not mean the area is clear.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuidanceSummary(state: model.guidanceState, mode: model.mode)
            if model.mode == .simulation {
                Label("SIMULATION: Synthetic inputs. No simulated movement sent to hardware.", systemImage: "info.circle")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .background(FeelTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.mode == .live {
                LiveSetup(model: model)
            } else {
                FeelSection(title: model.mode == .simulation ? "Explore the tactile pattern" : "Ready when you are", systemImage: "hand.raised") {
                    Text(model.mode == .simulation
                         ? "Watch the target move across seven columns. The loop also demonstrates tracking loss."
                         : "Connect your puck, start live sensing, then calibrate the floor before using depth estimates.")
                        .font(.body)
                    if model.mode == .stopped {
                        Text("No puck nearby? Simulation lets you explore the pattern on screen.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            PuckConnectionPanel(puck: model.puck)
            Text(model.status).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("sessionStatus")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var diagnostics: some View {
        DisclosureGroup("Packet and test notes") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.packet.hex).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("Columns run left to right. Rows run near (wrist) to far (fingers). One pin per column. A highlighted pin indicates target bearing; it does not establish a safe path.")
                Text("Unknown depth and lost tracking produce neutral pins. Neutral is not proof the area is clear. Indoor supervised prototype; use your usual mobility aid.")
            }.font(.footnote).padding(.top, 12)
        }
        .padding(20)
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SessionControls: View {
    @ObservedObject var model: LanternModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if !dynamicTypeSize.isAccessibilitySize {
                SessionStartControls(model: model, stacked: false)
            }
            Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(FeelStopButtonStyle())
                .accessibilityIdentifier("stopSession")
                .accessibilityHint("Stops sensing and sends neutral pins if connected.")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity)
        .background(FeelTheme.canvas)
        .overlay(alignment: .top) { Rectangle().fill(FeelTheme.border).frame(height: 0.5) }
    }
}

private struct SessionStartControls: View {
    @ObservedObject var model: LanternModel
    let stacked: Bool

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { model.startLive() } label: { Label("Live sensing", systemImage: "viewfinder") }
                .buttonStyle(FeelPrimaryButtonStyle())
                .disabled(model.mode == .live)
                .accessibilityHint("Starts camera sensing. Floor calibration is required.")
            Button { model.startSimulation() } label: { Label("Simulation", systemImage: "play.rectangle") }
                .buttonStyle(FeelSecondaryButtonStyle())
                .disabled(model.mode == .simulation)
                .accessibilityHint("Runs synthetic inputs without sending simulated movement to the puck.")
        }
    }
}

/// Presentation only. A live session is not evidence that guidance is valid.
struct GuidanceSummary: View {
    let state: GuidanceState
    let mode: LanternModel.RunMode

    var title: String {
        switch state {
        case .stopped: return "Your surroundings, through touch."
        case .live: return "Depth estimates active"
        case .simulation: return "A preview you can explore"
        case .trackingLost: return mode == .simulation ? "Simulated tracking loss" : "Tracking lost"
        case .staleDepth: return "Waiting for fresh depth"
        case .invalidFrame: return "Depth unavailable"
        case .uncalibrated: return "Calibrate to begin"
        }
    }

    var detail: String {
        switch state {
        case .stopped: return "Choose live sensing or try the simulation."
        case .live: return "Live depth estimates. Physical performance unverified."
        case .simulation: return "A virtual puck shows synthetic obstacles and a moving target."
        case .trackingLost: return mode == .simulation
            ? "All pins are neutral. The simulation will resume automatically."
            : "All pins are neutral. Hold the phone steady until tracking returns."
        case .staleDepth: return "All pins are neutral. Keep the camera uncovered and wait for a fresh reading."
        case .invalidFrame: return "All pins are neutral. Check the phone mount and restart live sensing if this continues."
        case .uncalibrated: return "Enter the camera height, then calibrate the floor. Pins remain neutral until calibration succeeds."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("guidanceTitle")
            Text(detail).font(.body).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PuckView: View {
    let packet: FeelPacket
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tactile view").font(.headline)
                Spacer()
                Text("Fingers / far").font(.caption).foregroundStyle(.secondary)
            }
            ForEach((1...4).reversed(), id: \.self) { band in
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<7, id: \.self) { column in
                        let active = packet.bands[column] == UInt8(band)
                        let target = active && packet.effectiveHighlight == UInt8(column)
                        Circle()
                            .fill(active ? FeelTheme.accent : Color(uiColor: .tertiarySystemFill))
                            .overlay {
                                if target {
                                    Circle().strokeBorder(FeelTheme.onAccent, lineWidth: 3).padding(4)
                                }
                            }
                            .frame(maxWidth: 22).aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Text("Left")
                Spacer()
                Text("Wrist / near")
                Spacer()
                Text("Right")
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Filled pin: depth  •  Ringed pin: target bearing")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
                    .font(.subheadline.weight(.semibold))
                Text("Mount landscape-left: rear camera forward, top edge to your left; keep the phone upright. Measure lens height above the floor.")
                    .font(.subheadline)
                Stepper(value: $model.cameraHeight, in: 0.6...2.1, step: 0.05) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera height").font(.subheadline)
                        Text(model.cameraHeight, format: .number.precision(.fractionLength(2))) + Text(" m")
                    }.monospacedDigit()
                }.accessibilityLabel("Camera height")
                    .accessibilityValue(String(format: "%.2f meters", model.cameraHeight))
                Button(model.calibrated ? "Recalibrate floor" : "Calibrate floor") { model.calibrate() }
                    .buttonStyle(FeelPrimaryButtonStyle())
                DisclosureGroup("Camera preview") {
                    CameraPreview(session: model.perception.session)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
            }
            FeelSection(title: "Find a target", systemImage: "scope") {
                Picker("Find", selection: $model.finder) {
                    ForEach(FinderMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode).disabled(mode == .chair && !model.detectorAvailable)
                    }
                }.pickerStyle(.menu)
                Text(model.detectorStatus).font(.footnote).foregroundStyle(.secondary)
                if model.finder == .door {
                    Text("Door candidate uses rectangle shape. It cannot confirm a door or a safe opening.").font(.footnote)
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
        FeelSection(title: "Puck connection", systemImage: "antenna.radiowaves.left.and.right") {
            Label(puck.isConnected ? "Puck connected" : "No puck connected", systemImage: puck.isConnected ? "checkmark.circle" : "link")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("puckConnectionStatus")
            Text(puck.status).font(.subheadline).foregroundStyle(.secondary)
            if puck.isConnected { Text(puck.boardStatus).font(.footnote) }
            DisclosureGroup("Manage connection") {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Scan for puck") { puck.scan() }.buttonStyle(FeelSecondaryButtonStyle())
                    Button("Disconnect") { puck.disconnect() }.buttonStyle(FeelSecondaryButtonStyle())
                        .accessibilityHint("Also cancels a pending connection.")
                    ForEach(puck.devices, id: \.identifier) { device in
                        Button("Connect \(device.name ?? "FEEL puck")") { puck.connect(device) }
                            .buttonStyle(FeelSecondaryButtonStyle())
                    }
                    if puck.devices.isEmpty {
                        Text("Turn on your puck, then scan. Nearby FEEL pucks will appear here.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            }
        }
    }
}

struct PeerPanel: View {
    @ObservedObject var peer: NearbyPeerService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(peer.status).font(.subheadline)
            Button("Find Beacon phones") { peer.start() }
                .buttonStyle(FeelSecondaryButtonStyle()).disabled(peer.running)
            Button("Stop finding") { peer.stop() }.buttonStyle(FeelSecondaryButtonStyle())
            if peer.running {
                Text("If no phones appear or the connection fails, stop finding and try again.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(peer.peers, id: \.self) { person in
                Button("Find \(person.displayName)") { peer.invite(person) }.buttonStyle(FeelSecondaryButtonStyle())
            }
            Text("The teammate accepts on Beacon. Keep both apps foreground. Direction can be unavailable; no tactile target is sent without a current AR direction.").font(.footnote)
        }
    }
}
