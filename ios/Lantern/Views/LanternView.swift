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
        case settings, connection, voice, memory
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
                Rectangle().fill(FeelTheme.paper)
                    .overlay(Rectangle().strokeBorder(FeelTheme.ink, lineWidth: FeelTheme.borderWidth))
                    .background(Rectangle().fill(FeelTheme.ink).offset(x: 6, y: 6))
            }
        }
        .foregroundStyle(controlsExpanded ? FeelTheme.ink : Color.white)
        .padding(.horizontal, 16).padding(.bottom, 18)
    }

    @ViewBuilder private var compactAttention: some View {
        if model.mode == .live {
            HStack {
                if !model.calibrated {
                    Button("Calibrate") { presentedPanel = .settings }
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
                Text(panel == .connection ? "Connect puck" : panel == .voice ? "Assistant" : panel == .memory ? "My Places" : "Settings")
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
                    } else if panel == .memory {
                        memory
                    } else if panel == .voice {
                        VoiceSetup(voice: voice) { closePanel() }
                        WhereIsSetup(model: model)
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
        .feelBlock(shadow: 8)
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
            CameraConnectionButton(puck: model.puck) { presentedPanel = .connection }
            Button { presentedPanel = .memory } label: {
                Image(systemName: "mappin.and.ellipse").frame(width: 48, height: 48)
            }
            .background(FeelTheme.inset, in: Circle())
            .accessibilityLabel("My Places")
            .accessibilityIdentifier("memoryPlaces")
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

    private var memory: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.memoryControlsVisible {
                PuckView(packet: model.packet).accessibilityIdentifier("memoryPuck")
                MemoryPanel(model: model)
            } else {
                Text("Start the camera to remember places in this session, or try Memory simulation.")
                    .foregroundStyle(FeelTheme.secondary)
            }
            if model.mode != .live {
                Button("Memory simulation") {
                    model.startSimulation(memory: true)
                    controlsExpanded = true
                }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .disabled(model.mode == .simulation && model.simulationScene == .memory)
                    .accessibilityIdentifier("memorySimulation")
                    .accessibilityHint("Preview remembering and recalling places without moving hardware.")
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.mode == .live {
                LiveSetup(model: model)
            } else {
                Text("Start the camera to calibrate.")
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
            Text("Synthetic inputs. No simulated movement is sent to hardware.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            AdvancedPanel(model: model, voice: model.localVoice)

            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.packet.hex).font(FeelTypography.mono).textSelection(.enabled)
                }.font(FeelTypography.footnote).padding(.top, 12)
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
                            .overlay(Circle().strokeBorder(FeelTheme.ink, lineWidth: compact ? 1.5 : 2.5))
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
                Label(model.calibrated ? "Floor calibrated" : "Calibration required", systemImage: model.calibrated ? "checkmark.circle" : "exclamationmark.circle")
                    .font(FeelTypography.label)
                Text("Phone landscape-left, rear camera forward.")
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
                        Text(mode.rawValue).tag(mode).disabled((mode == .chair && !model.detectorAvailable) || (mode == .teammate && model.restoredMapSession))
                    }
                }.pickerStyle(.menu)
                if model.restoredMapSession {
                    Text("Teammate ranging needs a fresh camera session. Stop, then Start camera to leave the saved map.").font(FeelTypography.footnote)
                }
                Text(model.detectorStatus).font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                if model.finder == .door {
                    Text("Door candidate uses rectangle shape. It cannot confirm a door or a safe opening.").font(FeelTypography.footnote)
                }
                if model.finder == .teammate && !model.restoredMapSession { PeerPanel(peer: model.peer) }

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

struct MemoryPanel:View {
    @ObservedObject var model:LanternModel
    @FocusState private var editingName:Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var rowLayout: AnyLayout { dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12)) }
    var body:some View {
        FeelSection(title: "My Places", systemImage: "mappin.and.ellipse") {
            VStack(alignment:.leading,spacing:12) {
                Text("Remember the current phone position. Places and the return point are cleared when sensing stops, restarts, or is interrupted.").font(FeelTypography.footnote)
                Text(model.memoryNotice).accessibilityIdentifier("memoryNotice")
                rowLayout {
                    TextField("Place name",text:$model.placeName).textFieldStyle(.roundedBorder)
                        .focused($editingName).submitLabel(.done).onSubmit { editingName=false }
                        .accessibilityLabel("Place name").accessibilityIdentifier("placeName")
                    Button("Remember") { editingName=false; model.remember() }.buttonStyle(FeelPrimaryButtonStyle()).accessibilityIdentifier("rememberPlace")
                        .accessibilityHint("Save your current tracked phone position with this name")
                }
                Text("\(model.spatialMemory.bookmarks.count) places in this session").accessibilityIdentifier("placesCount")
                if !model.spatialMemory.bookmarks.isEmpty {
                    Picker("Saved place",selection:Binding(get:{ model.spatialMemory.selectedID ?? "" },set:{ if !$0.isEmpty { model.selectPlace($0) } })) {
                        Text("Choose a place").tag("")
                        ForEach(model.spatialMemory.bookmarks) { place in Text(place.name).tag(place.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("savedPlaces")
                    rowLayout {
                        Button("Recall") { editingName=false; model.recall() }.buttonStyle(FeelPrimaryButtonStyle()).disabled(model.selectedPlace == nil).accessibilityIdentifier("recallPlace")
                        Button("Rename") { editingName=false; model.renameSelectedPlace() }.disabled(model.selectedPlace == nil)
                        Button("Delete",role:.destructive) { editingName=false; model.deleteSelectedPlace() }.disabled(model.selectedPlace == nil)
                    }.buttonStyle(FeelSecondaryButtonStyle())
                }
                rowLayout {
                    Button("Set return point") { editingName=false; model.setReturnPoint() }.accessibilityIdentifier("setReturnPoint")
                        .accessibilityHint("Replace the return point with your current tracked phone position")
                    Button("Return") { model.returnToPoint() }.disabled(model.spatialMemory.returnPoint == nil).accessibilityIdentifier("returnToPoint")
                    Button("Stop guidance") { model.stopMemoryGuidance() }.accessibilityIdentifier("stopMemoryGuidance")
                }.buttonStyle(FeelSecondaryButtonStyle())
                if model.spatialMemory.returnPoint != nil { Text("Return point is set for this session.").font(FeelTypography.footnote) }
                if let guidance=model.memoryGuidance {
                    Text(model.mode == .live && model.guidanceState != .live ? "Place guidance paused: \(model.guidanceState.rawValue)" : "Place guidance: \(guidance.state.rawValue)")
                        .font(FeelTypography.headline).accessibilityIdentifier("memoryGuidanceState")
                }
                if model.mode == .simulation,model.simulationScene == .memory {
                    Divider()
                    Text("SIMULATED motion").font(FeelTypography.headline)
                    Text(String(format:"Position x %.1f m, z %.1f m · yaw %.0f°",model.simulatedPosition.x,model.simulatedPosition.z,model.simulatedYaw)).font(FeelTypography.footnote)
                    rowLayout {
                        Button("Move forward 1 m") { model.simulateMove(metres:1) }.accessibilityIdentifier("simForward")
                        Button("Move back 1 m") { model.simulateMove(metres:-1) }.accessibilityIdentifier("simBack")
                        Button("Turn left 45°") { model.simulateTurn(degrees:45) }.accessibilityIdentifier("simLeft")
                        Button("Turn right 45°") { model.simulateTurn(degrees:-45) }.accessibilityIdentifier("simRight")
                    }.buttonStyle(FeelSecondaryButtonStyle())
                    Toggle("Simulated tracking available",isOn:$model.simulatedTracking).accessibilityIdentifier("simTracking")
                    Button("Reset simulated session") { model.resetSimulatedSession() }.accessibilityIdentifier("simResetSession")
                    Text("Synthetic pose and a fixed nearby obstacle in column 3. Movement only changes the virtual scene; no simulated commands move the physical puck.").font(FeelTypography.footnote)
                }
                Text("Range follows the phone's camera plane; horizontal distance uses the floor plane. Arrival means within 0.35 m horizontally and 0.75 m vertically. A highlighted place does not establish a clear route.").font(FeelTypography.footnote)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

struct AdvancedPanel:View {
    @ObservedObject var model:LanternModel
    @ObservedObject var voice:LocalVoiceControl
    @FocusState private var editingCommand:Bool
    var body:some View {
        DisclosureGroup("Voice, saved map and feedback") {
            VStack(alignment:.leading,spacing:14) {
                Text("This panel accepts typed or on-device speech commands. The separate Assistant uses OpenAI. Camera text and barcode labels never execute commands.").font(.footnote)
                Picker("Command language",selection:$model.commandLanguage) { Text("English").tag(VoiceLanguage.en); Text("Spanish").tag(VoiceLanguage.es) }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Command",text:$model.commandText).textFieldStyle(.roundedBorder).focused($editingCommand)
                        .submitLabel(.done).onSubmit { editingCommand=false }.accessibilityIdentifier("commandText")
                    Button("Run command") { editingCommand=false; model.submitTypedCommand() }.buttonStyle(FeelPrimaryButtonStyle()).accessibilityIdentifier("runCommand")
                }
                Text(model.commandLanguage == .en ? "remember Desk · recall Desk · return · stop · list places · find barcode" : "recuerda Mesa · recupera Mesa · vuelve · para · lista lugares · busca código").font(.footnote)
                ViewThatFits(in: .horizontal) {
                    HStack { speechActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { speechActions }
                }.buttonStyle(.bordered)
                Text(voice.status).accessibilityIdentifier("voiceStatus")
                Text("Starting local speech pauses the Assistant. Resume it from Assistant settings afterward.").font(.footnote)
                if !voice.transcript.isEmpty { Text(voice.transcript).font(.footnote) }
                Text(model.commandNotice).accessibilityIdentifier("commandNotice")
                Text("Speech requires on-device support for the selected language. There is no cloud recognition fallback. Type a command if speech is unavailable.").font(.footnote)
                Divider()
                Picker("Target tap profile",selection:$model.adaptiveProfile) {
                    Text("Standard").tag(AdaptiveProfile.standard); Text("Reduced").tag(AdaptiveProfile.reduced); Text("Automatic").tag(AdaptiveProfile.automatic)
                }.pickerStyle(.menu).accessibilityIdentifier("adaptiveProfile")
                Text("Obstacle pins stay unchanged. Reduced target taps use 1.8 seconds quiet, then 0.6 seconds highlighted. Automatic chooses reduced when any near obstacle appears and waits 2.4 seconds clear before resuming standard.").font(.footnote)
                Divider()
                Text("One saved local map").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack { mapActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { mapActions }
                }.buttonStyle(.bordered)
                Text(model.mapNotice).accessibilityIdentifier("mapNotice")
                Text("Save replaces the previous local map and its places. Load starts a new session in the same physical area; places stay inactive until relocalization succeeds. Select and Recall explicitly afterward. Simulation never creates a real AR map.").font(.footnote)
            }.padding(.top,8)
        }
    }
    @ViewBuilder private var speechActions: some View {
                    Button("Start speaking") { editingCommand=false; model.startVoiceCommand() }.disabled(voice.isListening)
                    Button("Finish speaking") { voice.finish() }.disabled(!voice.canFinish)
                    Button("Cancel speech") { voice.cancel() }
                    Button("Read result") { model.readCommandResult() }.disabled(voice.isListening)
    }
    @ViewBuilder private var mapActions: some View {
                    Button("Save map") { model.saveMap() }.disabled(model.mode != .live || model.mapBusy || model.restoringMap)
                    Button("Load map") { model.loadMap() }.disabled(model.mode != .live || model.mapBusy)
                    Button("Delete saved map",role:.destructive) { model.deleteSavedMap() }.disabled(model.mapBusy)
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
