import SwiftUI
import ARKit
import FeelCore

struct LanternView: View {
    @ObservedObject var model: LanternModel
    @ObservedObject private var voice: RealtimeVoiceSession
    init(model: LanternModel) {
        self.model = model
        self.voice = model.voice
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedPanel: CameraPanel?
    @State private var attemptedInitialStart = false
    @State private var controlsExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var modalFocused: Bool

    private enum CameraPanel: String, Identifiable {
        case settings, connection, voice
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cameraSurface
                if presentedPanel == nil {
                    VStack(spacing: 0) {
                        header
                        if !controlsExpanded { compactAttention }
                        Spacer(minLength: 8)
                        controlDrawer(availableHeight: geometry.size.height)
                    }
                }

                if let panel = presentedPanel {
                    Color.black.opacity(0.6).ignoresSafeArea()
                        .onTapGesture { closePanel() }
                        .accessibilityHidden(true)
                    floatingPanel(panel, availableSize: geometry.size)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presentedPanel)
        .font(FeelTypography.body)
        .tint(FeelTheme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: presentedPanel) { panel in modalFocused = panel != nil }
        .onChange(of: model.voicePanel) { panel in
            guard let panel else { return }
            presentedPanel = panel == .settings ? .settings : .connection
            model.voicePanel = nil
        }
        .onChange(of: model.status) { _ in
            // Denied permission and unsupported hardware must not disappear in a closed drawer.
            if model.mode == .stopped && !model.isStarting { setControlsExpanded(true) }
        }
        .task {
            guard !attemptedInitialStart else { return }
            attemptedInitialStart = true
            if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                model.startLive()
                model.voice.enterForeground()
            }
        }
    }

    private var cameraSurface: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.mode == .live {
                CameraPreview(session: model.perception.session)
                    .ignoresSafeArea().accessibilityHidden(true)
            }
        }
    }

    private func setControlsExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            controlsExpanded = expanded
        }
    }

    private func closePanel() { presentedPanel = nil }

    private func controlDrawer(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Button { setControlsExpanded(!controlsExpanded) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 17, weight: .semibold))
                        .rotationEffect(.degrees(controlsExpanded ? 180 : 0))
                        .frame(width: 76, height: 48)
                        .background(FeelTheme.inset, in: Capsule())
                        .overlay(Capsule().strokeBorder(FeelTheme.border, lineWidth: 1))
                }
                .accessibilityLabel(controlsExpanded ? "Hide controls" : "Show controls")
                .accessibilityValue(controlsExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("controlsToggle")
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                    if abs(value.translation.height) > 35 {
                        setControlsExpanded(value.translation.height < 0)
                    }
                })
                if !controlsExpanded && (model.mode != .stopped || model.isStarting) {
                    HStack {
                        Spacer()
                        Button(role: .destructive) { model.stop() } label: {
                            Image(systemName: "stop.fill").frame(width: 48, height: 48)
                                .background(FeelTheme.inset, in: Circle())
                                .overlay(Circle().strokeBorder(FeelTheme.border, lineWidth: 1))
                        }
                        .accessibilityLabel("Stop")
                        .accessibilityIdentifier("stopSession")
                        .accessibilityHint("Stops sensing even with controls hidden.")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if controlsExpanded {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            PuckView(packet: model.packet)
                            guidance
                        }.padding(.horizontal, 20)
                    }
                    .frame(height: max(110, availableHeight - 285))
                    .accessibilityIdentifier("cameraReadingScroll")
                    sessionAction.padding(16)
                } else {
                    HStack(spacing: 20) {
                        PuckView(packet: model.packet, compact: true).frame(width: 200)
                        guidance.frame(maxWidth: .infinity, alignment: .leading)
                        sessionAction.frame(width: 164)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: 800)
        .background {
            if controlsExpanded {
                RoundedRectangle(cornerRadius: 24).fill(FeelTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(FeelTheme.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    @ViewBuilder private var compactAttention: some View {
        if model.mode == .live {
            HStack {
                if !model.calibrated {
                    Button("Calibrate") { presentedPanel = .settings }
                        .font(FeelTypography.label).frame(minHeight: 44)
                        .padding(.horizontal, 16).background(FeelTheme.inset, in: Capsule())
                } else if model.guidanceState != .live {
                    Button("Check sensing") { setControlsExpanded(true) }
                        .font(FeelTypography.label).frame(minHeight: 44)
                        .padding(.horizontal, 16).background(FeelTheme.inset, in: Capsule())
                        .accessibilityValue(model.status)
                }
                Spacer()
            }.padding(.horizontal, 20)
        }
    }

    private func floatingPanel(_ panel: CameraPanel, availableSize: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(panel == .connection ? "Connect puck" : panel == .voice ? "Assistant" : "Settings")
                    .font(FeelTypography.title3).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button { closePanel() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(FeelTheme.inset, in: Circle())
                }
                .accessibilityLabel("Close panel")
                .accessibilityIdentifier("closeCameraPanel")
                .accessibilityFocused($modalFocused)
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if panel == .connection {
                        PuckConnectionPanel(puck: model.puck)
                    } else if panel == .voice {
                        VoiceSetup(voice: voice) { closePanel() }
                    } else {
                        settings
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            .accessibilityIdentifier("cameraSettingsScroll")
            if model.mode != .stopped || model.isStarting || voice.isActive {
                HStack {
                    if model.mode != .stopped || model.isStarting {
                        Button("Stop camera", role: .destructive) {
                            model.stop(); closePanel()
                        }
                        .buttonStyle(CameraPillButtonStyle(primary: false))
                        .accessibilityHint("Stops sensing and tactile output. The assistant keeps listening.")
                        .accessibilityIdentifier("panelStop")
                    }
                    if voice.isActive {
                        Button("Pause assistant") { voice.pauseAssistant(); closePanel() }
                            .buttonStyle(CameraPillButtonStyle(primary: false))
                            .accessibilityHint("Stops the microphone and spoken responses.")
                    }
                }.padding(16)
            }
        }
        .frame(width: min(540, availableSize.width - 32), height: availableSize.height - 24)
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(FeelTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("cameraFloatingPanel")
        .accessibilityAction(.escape) { closePanel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("FEEL").font(FeelTypography.headline).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .foregroundStyle(FeelTheme.accent)
                        .background(FeelTheme.inset, in: Capsule())
                        .overlay(Capsule().strokeBorder(FeelTheme.border, lineWidth: 1))
                        .accessibilityIdentifier("feelWordmark")
                }
                if model.mode == .simulation {
                    Text("SIMULATION").font(FeelTypography.caption)
                        .accessibilityIdentifier("sessionMode")
                }
            }
            .frame(minHeight: 48)
            .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
            Spacer(minLength: 0)
            VoiceControl(voice: voice) { presentedPanel = .voice }
            CameraConnectionButton(puck: model.puck) { presentedPanel = .connection }
            Button { presentedPanel = .settings } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
            }
            .background(FeelTheme.inset, in: Circle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("cameraSettings")
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.mode == .stopped {
                Text("STOPPED").font(FeelTypography.caption)
                    .foregroundStyle(FeelTheme.secondary).accessibilityIdentifier("sessionMode")
            }
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
            Button { model.startLive() } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    Label("Start camera", systemImage: "camera.fill")
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 21, weight: .medium))
                        Text("Start camera").font(FeelTypography.label)
                    }.padding(.vertical, 6)
                }
            }
                .buttonStyle(CameraPillButtonStyle())
                .accessibilityIdentifier("startCamera")
        } else {
            Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(CameraPillButtonStyle(primary: false))
                .accessibilityIdentifier("stopSession")
                .accessibilityHint("Stops the camera and sends neutral pins if connected.")
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Assistant settings") { presentedPanel = .voice }
                .buttonStyle(FeelSecondaryButtonStyle())
                .accessibilityIdentifier("voiceSettings")
            if model.mode == .live {
                LiveSetup(model: model)
            } else {
                Text("Start the camera to calibrate and choose a target.")
                    .foregroundStyle(FeelTheme.secondary)
            }
            Button("Simulation") {
                model.startSimulation()
                controlsExpanded = true
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

private struct CameraPillButtonStyle: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FeelTypography.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(primary ? FeelTheme.onAccent : FeelTheme.accent)
            .background(primary ? FeelTheme.accent : FeelTheme.inset, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? FeelTheme.accent : FeelTheme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct CameraConnectionButton: View {
    @ObservedObject var puck: BluetoothPuck
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            Label(puck.status.hasPrefix("Write error:") ? "Connection error" : puck.isConnected ? "Connected" : "Connect puck", systemImage: "link")
                .labelStyle(CompactConnectionLabelStyle(compact: dynamicTypeSize.isAccessibilitySize))
                .font(FeelTypography.label)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(FeelTheme.inset, in: Capsule())
        }
        .accessibilityLabel(puck.isConnected ? "Connected puck" : "Connect puck")
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

private struct CompactConnectionLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}
