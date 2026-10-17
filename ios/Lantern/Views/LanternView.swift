import SwiftUI
import ARKit
import FeelCore

struct LanternView: View {
    @ObservedObject var model: LanternModel
    @ObservedObject private var voice: RealtimeVoiceSession
    private let signedInEmail: String?
    private let onSignOut: (() -> Void)?
    init(model: LanternModel, signedInEmail: String? = nil, onSignOut: (() -> Void)? = nil) {
        self.model = model
        self.voice = model.voice
        self.signedInEmail = signedInEmail
        self.onSignOut = onSignOut
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedPanel: CameraPanel?
    @State private var attemptedInitialStart = false
    @State private var controlsExpanded = false
    @State private var gridWalk = false
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
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presentedPanel)
        .font(FeelTypography.body)
        .tint(FeelTheme.accent)
        .fullScreenCover(isPresented: $gridWalk) { GridWalkView(model: model) }
        .onChange(of: presentedPanel) { panel in modalFocused = panel != nil }
        .onChange(of: model.voicePanel) { panel in
            guard let panel else { return }
            switch panel {
            case .settings: presentedPanel = .settings
            case .connection: presentedPanel = .connection
            case .assistant: presentedPanel = .voice
            case .closed: closePanel()
            }
            model.voicePanel = nil
        }
        .onChange(of: model.voiceControlsExpanded) { expanded in
            guard let expanded else { return }
            setControlsExpanded(expanded); model.voiceControlsExpanded = nil
        }
        .onChange(of: model.status) { _ in
            // Denied permission and unsupported hardware must not disappear in a closed drawer.
            if model.mode == .stopped && !model.isStarting { setControlsExpanded(true) }
        }
        .task {
            guard !attemptedInitialStart else { return }
            attemptedInitialStart = true
            // `-feelGridWalkDemo YES` opens grid walk on the synthetic scene (simulator screenshots, demo videos).
            if UserDefaults.standard.bool(forKey: "feelGridWalkDemo") { model.startSimulation(); gridWalk = true; return }
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
                        .font(.system(size: 17, weight: .bold))
                        .rotationEffect(.degrees(controlsExpanded ? 180 : 0))
                        .frame(width: 76, height: 48)
                        .foregroundStyle(FeelTheme.ink)
                        .feelBlock(shadow: 4)
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
                                .foregroundStyle(FeelTheme.ink)
                                .feelBlock(Circle(), shadow: 4)
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
                            PuckView(packet: model.packet, targetColumns: model.targetColumns)
                            guidance
                        }.padding(.horizontal, 20)
                    }
                    .frame(height: max(110, availableHeight - 285))
                    .accessibilityIdentifier("cameraReadingScroll")
                    sessionAction.padding(16)
                } else {
                    HStack(spacing: 20) {
                        PuckView(packet: model.packet, targetColumns: model.targetColumns, compact: true).frame(width: 200)
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
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(FeelTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(FeelTheme.divider, lineWidth: 1))
            }
        }
        .foregroundStyle(controlsExpanded ? FeelTheme.ink : Color.white)
        .padding(.horizontal, 16).padding(.bottom, 18)
    }

    @ViewBuilder private var compactAttention: some View {
        if model.mode == .live {
            HStack {
                if !model.calibrated {
                    Button(model.automaticFloorCalibrationSupported ? "Finding floor…" : "Floor setup") { presentedPanel = .settings }
                        .font(FeelTypography.label).frame(minHeight: 44)
                        .padding(.horizontal, 16).foregroundStyle(FeelTheme.ink).feelBlock(shadow: 4)
                } else if model.guidanceState != .live {
                    Button("Check sensing") { setControlsExpanded(true) }
                        .font(FeelTypography.label).frame(minHeight: 44)
                        .padding(.horizontal, 16).foregroundStyle(FeelTheme.ink).feelBlock(shadow: 4)
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
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .feelBlock(Circle(), shadow: 3)
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
                        WhereIsSetup(model: model)
                        VenuePackSetup(venue: model.venueInfo)
                    } else {
                        settings
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            .accessibilityIdentifier("cameraSettingsScroll")
            // The Assistant panel has its own pause control; the footer's copy would duplicate it.
            if model.mode != .stopped || model.isStarting || (voice.isActive && panel != .voice) {
                HStack {
                    if model.mode != .stopped || model.isStarting {
                        Button("Stop camera", role: .destructive) {
                            model.stop(); closePanel()
                        }
                        .buttonStyle(CameraPillButtonStyle(primary: false))
                        .accessibilityHint("Stops sensing and tactile output. The assistant keeps listening.")
                        .accessibilityIdentifier("panelStop")
                    }
                    if voice.isActive && panel != .voice {
                        Button("Pause assistant") { voice.pauseAssistant(); closePanel() }
                            .buttonStyle(CameraPillButtonStyle(primary: false))
                            .accessibilityHint("Stops the microphone and spoken responses.")
                    }
                }.padding(16)
            }
        }
        .frame(width: min(540, availableSize.width - 40), height: availableSize.height - 32)
        .foregroundStyle(FeelTheme.ink)
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(FeelTheme.divider, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("cameraFloatingPanel")
        .accessibilityAction(.escape) { closePanel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
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
                    Text("SIMULATION").font(FeelTypography.label).foregroundStyle(.black)
                        .padding(.horizontal, 10).frame(minHeight: 48)
                        .feelBlock(fill: FeelTheme.notice, shadow: 4)
                        .accessibilityIdentifier("sessionMode")
                }
            }
            Spacer(minLength: 0)
            VoiceControl(voice: voice) { presentedPanel = .voice }
            Button { gridWalk = true } label: {
                Image(systemName: "square.grid.3x3.fill").frame(width: 48, height: 48)
            }
            .background(FeelTheme.inset, in: Circle())
            .accessibilityLabel("Grid walk")
            .accessibilityHint("Full-screen pin grid without the camera image, for walking by the grid alone.")
            .accessibilityIdentifier("gridWalk")
            CameraConnectionButton(puck: model.puck) { presentedPanel = .connection }
            Button { presentedPanel = .settings } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(FeelTheme.ink).frame(width: 48, height: 48)
                    .feelBlock(Circle(), shadow: 4)
            }
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
                Button(model.automaticFloorCalibrationSupported ? "Finding floor…" : "Floor setup") { presentedPanel = .settings }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .accessibilityHint("Move slowly with the floor visible for automatic calibration. Open floor setup for the manual alternative.")
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
            if model.mode == .live {
                LiveSetup(model: model)
            } else {
                Text("Start the camera to calibrate the floor automatically.")
                    .foregroundStyle(FeelTheme.secondary)
            }
            DirectionArrowSettings(model: model)
            Button("Simulation") {
                model.startSimulation()
                controlsExpanded = true
                presentedPanel = nil
            }
            .buttonStyle(FeelSecondaryButtonStyle())
            .disabled(model.mode == .simulation)
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.packet.hex).font(FeelTypography.mono).textSelection(.enabled)
                }.font(FeelTypography.footnote).padding(.top, 12)
            }
            if let onSignOut {
                if let signedInEmail, !signedInEmail.isEmpty {
                    Text("Signed in as \(signedInEmail)").foregroundStyle(FeelTheme.secondary)
                }
                Button("Sign out", role: .destructive) { presentedPanel = nil; onSignOut() }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .accessibilityHint("Stops the camera and assistant and returns to the sign-in screen.")
                    .accessibilityIdentifier("signOut")
            }
        }
    }
}

private struct CameraPillButtonStyle: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if primary {
                FeelPrimaryButtonStyle().makeBody(configuration: configuration)
            } else {
                FeelSecondaryButtonStyle().makeBody(configuration: configuration)
            }
        }
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
                .font(FeelTypography.label).foregroundStyle(puck.isConnected ? .black : FeelTheme.ink)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .feelBlock(fill: puck.isConnected ? FeelTheme.pin : FeelTheme.paper, shadow: 4)
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
        case .simulation: return model.guidanceCue.map { "SIMULATION · guiding: \($0.spoken)" } ?? "SIMULATION"
        case .trackingLost: return model.mode == .simulation ? "SIMULATION · Tracking lost" : "Tracking lost · Pins neutral"
        case .staleDepth: return "Waiting for depth · Pins neutral"
        case .invalidFrame: return "Depth unavailable · Pins neutral"
        case .uncalibrated: return "Finding floor · Pins neutral"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FeelTypography.label).accessibilityIdentifier("guidanceTitle")
            if model.mode == .simulation {
                Text("No simulated movement sent to hardware.")
                    .font(FeelTypography.footnote)
                    .accessibilityIdentifier("simulationNotice")
                if model.arrowsEnabled {
                    Button("Simulate V sign") { model.simulateSign() }
                        .buttonStyle(FeelSecondaryButtonStyle())
                        .accessibilityIdentifier("simulateSign")
                        .accessibilityHint("Plays the arrow a real V sign would request.")
                }
            } else {
                Text(model.status).font(FeelTypography.footnote).accessibilityIdentifier("sessionStatus")
                if model.mode == .live {
                    Text(model.pointingReadout).font(FeelTypography.footnote)
                        .foregroundStyle(FeelTheme.secondary).accessibilityIdentifier("pointingReadout")
                    if model.arrowsEnabled {
                        Text(model.directionReadout).font(FeelTypography.footnote)
                            .foregroundStyle(FeelTheme.secondary).accessibilityIdentifier("directionReadout")
                    }
                }
            }
            Text(puck.status).font(FeelTypography.footnote)
                .foregroundStyle(FeelTheme.secondary).accessibilityIdentifier("puckConnectionStatus")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PuckView: View {
    let packet: FeelPacket
    /// Several target columns tap together; nil falls back to the packet's single highlight.
    var targetColumns: ClosedRange<Int>? = nil
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
                        let target = active && ((targetColumns.map { $0.count > 1 && $0.contains(column) } ?? false) || packet.effectiveHighlight == UInt8(column))
                        // Raised pins are solid ink; target columns are orange; down pins are rings.
                        Circle()
                            .fill(target ? FeelTheme.pin : active ? FeelTheme.ink : FeelTheme.paper)
                            .overlay(Circle().strokeBorder(FeelTheme.border, lineWidth: 1))
                            .frame(maxWidth: compact ? 13 : 24).aspectRatio(1, contentMode: .fit)
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
        .accessibilityValue(packet.bands.enumerated().map { "Column \($0.offset + 1), band \($0.element)" }.joined(separator: ". ") + targetSummary)
    }

    private var targetSummary: String {
        if let span = targetColumns, span.count > 1 { return ". Target columns \(span.lowerBound + 1) to \(span.upperBound + 1)" }
        return packet.effectiveHighlight < 7 ? ". Target column \(Int(packet.effectiveHighlight) + 1)" : ". No target highlight"
    }
}

private struct DirectionArrowSettings: View {
    @ObservedObject var model: LanternModel
    var body: some View {
        FeelSection(title: "Direction arrows", systemImage: "arrow.turn.up.right") {
            Toggle("Arrows on V sign", isOn: $model.arrowsEnabled)
                .font(FeelTypography.label)
                .accessibilityIdentifier("directionArrowsToggle")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LiveSetup: View {
    @ObservedObject var model: LanternModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeelSection(title: "Floor calibration", systemImage: "viewfinder") {
                Label(model.calibrated ? "Floor calibrated" : (model.automaticFloorCalibrationSupported ? "Looking for a stable floor" : "Measured height needed"), systemImage: model.calibrated ? "checkmark.circle" : "exclamationmark.circle")
                    .font(FeelTypography.label)
                Text(model.automaticFloorCalibrationSupported
                     ? "Keep the phone landscape-left, rear camera forward, with some floor visible. Calibration happens automatically when a stable floor is detected."
                     : "Automatic floor detection is unavailable on this device. Keep the phone landscape-left, rear camera forward, and enter its measured lens height.")
                    .font(FeelTypography.subheadline)
                Stepper(value: $model.cameraHeight, in: 0.6...2.1, step: 0.05) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manual camera height").font(FeelTypography.subheadline)
                        Text(model.cameraHeight, format: .number.precision(.fractionLength(2))) + Text(" m")
                    }.monospacedDigit()
                }.accessibilityLabel("Camera height")
                    .accessibilityValue(String(format: "%.2f meters", model.cameraHeight))
                Text("If automatic calibration cannot find the floor, measure the lens height above it and use the manual option below.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                Button("Use measured height") { model.calibrate() }
                    .buttonStyle(FeelPrimaryButtonStyle())
                Text(model.status)
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calibrationStatus")

            }
            FeelSection(title: "Record for replay", systemImage: "record.circle") {
                Toggle("Record depth", isOn: $model.recordingDepth)
                    .font(FeelTypography.label)
                    .accessibilityIdentifier("recordDepthToggle")
                Toggle("Include camera video", isOn: $model.recordingVideo)
                    .font(FeelTypography.label)
                    .disabled(model.recordingDepth)
                    .accessibilityIdentifier("recordVideoToggle")
                Text(model.recordingStatus ?? "Saves LiDAR depth, pose and detections, plus camera video if included, to Files › On My iPhone › FEEL › Recordings, for scoring the pins offline and watching them on the /replay page. Nothing leaves the phone until you share it. About 3 MB per second.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recordingStatus")
            }
            FeelSection(title: "Find a target", systemImage: "scope") {
                Picker("Find", selection: $model.finder) {
                    ForEach(FinderMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode).disabled(mode == .chair && !model.detectorAvailable)
                    }
                }.pickerStyle(.menu)
                Text(model.detectorStatus).font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
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
            ForEach(peer.peers, id: \.self) { person in
                Button("Find \(person.displayName)") { peer.invite(person) }.buttonStyle(FeelSecondaryButtonStyle())
            }
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
