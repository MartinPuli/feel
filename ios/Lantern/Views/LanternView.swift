import SwiftUI
import ARKit
import FeelCore

/// Test scenes require an explicit developer/test launch; saved preferences cannot enable them.
enum FeelLaunchOptions {
    static func diagnosticsEnabled(arguments: [String]) -> Bool {
        !arguments.contains("--hide-diagnostics") &&
            (arguments.contains("--uitesting") || arguments.contains("--diagnostics"))
    }
    static func opensGridDemo(arguments: [String], savedPreference: Bool) -> Bool {
        diagnosticsEnabled(arguments: arguments) && savedPreference
    }
}

/// Task navigation stays independent from the live sensing session.
struct LanternView: View {
    @ObservedObject var model: LanternModel
    @ObservedObject private var voice: RealtimeVoiceSession
    @ObservedObject private var puck: BluetoothPuck
    private let signedInEmail: String?
    private let onSignOut: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTask: FeelTask = .surroundings
    @State private var presentedPanel: CameraPanel?
    @State private var attemptedInitialStart = false
    @State private var gridWalk = false
    @State private var findQuery = ""
    @State private var placeName = ""
    @State private var commandsOpenedFromFind = false
    @State private var scanOpenedFromHome = false
    @State private var descriptionResult = ""
    @State private var keyboardVisible = false
    @State private var controlsOpen = false
    @AccessibilityFocusState private var focusedControl: FocusTarget?
    @AccessibilityFocusState private var localCommandsFocused: Bool
    private var showsDiagnostics: Bool { FeelLaunchOptions.diagnosticsEnabled(arguments: ProcessInfo.processInfo.arguments) }

    init(model: LanternModel, signedInEmail: String? = nil, onSignOut: (() -> Void)? = nil) {
        self.model = model
        self.voice = model.voice
        self.puck = model.puck
        self.signedInEmail = signedInEmail
        self.onSignOut = onSignOut
    }

    private enum FocusTarget: Hashable { case voice, connection, settings, status, preview, scan, close, menu, menuClose }
    private enum CameraPanel: String, Identifiable {
        case settings, connection, voice, commands, advanced, spatialMap, status, preview
        var id: String { rawValue }
        var title: String {
            switch self {
            case .settings: return "Settings"
            case .connection: return "Connect puck"
            case .voice: return "Voice controls"
            case .commands: return "Local commands"
            case .advanced: return "Advanced tools"
            case .spatialMap: return "3D scan"
            case .status: return "Status"
            case .preview: return "Camera"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                FeelTheme.canvas.ignoresSafeArea()
                if model.mode == .live {
                    CameraPreview(session: model.perception.session)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                if presentedPanel == nil {
                    if !controlsOpen {
                        cameraHome
                    } else {
                    VStack(spacing: 0) {
                        if !keyboardVisible {
                            header
                            taskNavigation
                        }
                        ScrollViewReader { proxy in
                            ScrollView {
                                taskContent(width: geometry.size.width)
                                    .frame(maxWidth: 1040, alignment: .leading)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, FeelSpacing.page).padding(.vertical, FeelSpacing.compact)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .accessibilityIdentifier("cameraReadingScroll")
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                                let field = selectedTask == .find ? "findQuery" : selectedTask == .places ? "placeName" : nil
                                guard let field else { return }
                                // UIKit may retain the scroll offset from before the header collapsed.
                                DispatchQueue.main.async { proxy.scrollTo(field, anchor: .top) }
                            }
                        }
                        sessionBar(panel: false).accessibilitySortPriority(2)
                    }
                    .background(FeelTheme.canvas)
                    .accessibilityAction(.escape) { controlsOpen = false }
                    }
                }
                if let panel = presentedPanel {
                    floatingPanel(panel, availableSize: geometry.size)
                        .transition(.opacity)
                }
            }
        }
        .font(FeelTypography.body)
        .foregroundStyle(FeelTheme.ink)
        .tint(FeelTheme.accent)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: presentedPanel)
        .fullScreenCover(isPresented: $gridWalk) { GridWalkView(model: model) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onReceive(puck.$isConnected.removeDuplicates().dropFirst()) { connected in
            // Keep this observer alive while settings, results or the keyboard hide the header.
            guard !connected, UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement,
                                 argument: "Puck disconnected. Tactile feedback is unavailable.")
        }
        .onChange(of: presentedPanel) { panel in
            if panel != nil { focusedControl = .close }
        }
        .onChange(of: controlsOpen) { open in
            Task { @MainActor in
                await Task.yield()
                focusedControl = open ? .menuClose : .menu
            }
        }
        .onChange(of: model.mode) { mode in
            if mode != .live { descriptionResult = "" }
        }
        .onChange(of: model.describeNotice) { notice in
            guard model.mode == .live, let notice else { return }
            UIAccessibility.post(notification: .announcement, argument: notice)
        }
        .onChange(of: model.guidanceState) { state in
            guard UIAccessibility.isVoiceOverRunning else { return }
            switch state {
            case .trackingLost, .staleDepth, .invalidFrame, .uncalibrated:
                UIAccessibility.post(notification: .announcement, argument: sensingSummary)
            default: break
            }
        }
        .onChange(of: model.status) { status in
            // Startup failures leave the camera stopped; never announce the live status stream.
            guard UIAccessibility.isVoiceOverRunning, model.mode == .stopped, !model.isStarting else { return }
            UIAccessibility.post(notification: .announcement, argument: status)
        }
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
            controlsOpen = expanded
            selectedTask = .surroundings
            model.voiceControlsExpanded = nil
        }
        .task {
            guard !attemptedInitialStart else { return }
            attemptedInitialStart = true
            if FeelLaunchOptions.opensGridDemo(arguments: ProcessInfo.processInfo.arguments,
                                               savedPreference: UserDefaults.standard.bool(forKey: "feelGridWalkDemo")) {
                model.startSimulation(); gridWalk = true; return
            }
            if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                model.startLive()
                model.voice.enterForeground()
            }
        }
    }

    /// The readout uses the same post-processing packet as the BLE sender. It is
    /// a schematic, not a camera-registered map or confirmation of servo motion.
    private var cameraHome: some View {
        VStack(spacing: FeelSpacing.compact) {
            HStack(spacing: FeelSpacing.section) {
                if model.mode == .stopped && !model.isStarting {
                    Button { model.startLive() } label: {
                        Image(systemName: "camera.fill").frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Start camera")
                    .accessibilityIdentifier("startCamera")
                } else {
                    Button { model.stop(); descriptionResult = "" } label: {
                        Image(systemName: "stop.fill").frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Stop sensing")
                    .accessibilityIdentifier("stopSession")
                    .accessibilityHint("Stops the camera and tactile guidance. Voice is controlled separately.")
                }
                Spacer(minLength: 12)
                Button {
                    if voice.isActive { voice.pauseAssistant() }
                    else if voice.isConfigured { voice.resumeAssistant() }
                    else { presentedPanel = .voice }
                } label: {
                    Image(systemName: voice.isActive ? "mic.slash" : "waveform").frame(width: 48, height: 48)
                }
                .accessibilityLabel(voice.isActive ? "Pause voice" : "Talk to FEEL")
                .accessibilityValue(voice.isActive ? voice.label : "Microphone off")
                .accessibilityIdentifier("talkToFeel")
                .accessibilityFocused($focusedControl, equals: .voice)
                Button { controlsOpen = true } label: {
                    Image(systemName: "line.3.horizontal").frame(width: 48, height: 48)
                }
                .accessibilityLabel("Menu")
                .accessibilityIdentifier("cameraMenu")
                .accessibilityFocused($focusedControl, equals: .menu)
            }
            .buttonStyle(CameraOverlayButtonStyle())
            .accessibilitySortPriority(2)
            Spacer(minLength: 0)
            Button { presentedPanel = .status } label: {
                VStack(spacing: FeelSpacing.compact) {
                    Text(sensingLabel).font(FeelTypography.caption)
                    if !dynamicTypeSize.isAccessibilitySize {
                        PuckView(packet: model.packet, targetColumns: model.targetColumns, compact: true)
                            .accessibilityHidden(true)
                    }
                    Text(model.mode == .simulation ? "Test signal · no movement sent" : puck.isConnected ? "Requested pins" : "Preview · puck disconnected")
                        .font(FeelTypography.caption)
                }
                .padding(FeelSpacing.section)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 240)
                .background(FeelTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(sensingLabel), sensing status")
            .accessibilityValue(sensingSummary)
            .accessibilityHint("Opens sensing status and tactile signal details. Neutral does not mean a clear path.")
            .accessibilityIdentifier("sensingStatus")
            .accessibilityFocused($focusedControl, equals: .status)
        }
        .padding(FeelSpacing.section)
    }

    private var header: some View {
        HStack(spacing: FeelSpacing.compact) {
            Button {
                controlsOpen = false
            } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to camera")
                .accessibilityIdentifier("closeCameraMenu")
                .accessibilityFocused($focusedControl, equals: .menuClose)
            Text("feel").font(FeelTypography.brand).accessibilityHidden(true)
            Spacer(minLength: 8)
            Button { presentedPanel = .voice } label: {
                Label("Voice", systemImage: voice.isActive ? "mic.fill" : "mic.slash")
                    .labelStyle(.iconOnly)
                    .font(FeelTypography.label).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice controls")
            .accessibilityValue(voice.isActive ? voice.label : "Microphone off")
            .accessibilityIdentifier("voiceControl")
            .accessibilityFocused($focusedControl, equals: .voice)
            CameraConnectionButton(puck: model.puck) { presentedPanel = .connection }
                .accessibilityFocused($focusedControl, equals: .connection)
            Button { presentedPanel = .settings } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("cameraSettings")
            .accessibilityFocused($focusedControl, equals: .settings)
        }
        .padding(.horizontal, FeelSpacing.page).padding(.vertical, FeelSpacing.tight)
    }

    private var taskNavigation: some View {
        HStack(spacing: FeelSpacing.compact) {
            ForEach(FeelTask.allCases) { task in
                Button { selectedTask = task } label: {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize { Text(task == .surroundings ? "Around me" : task.title) }
                        else { Label(task.title, systemImage: task.symbol) }
                    }
                        .font(FeelTypography.label)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selectedTask == task ? FeelTheme.onAccent : FeelTheme.ink)
                        .background(selectedTask == task ? FeelTheme.accent : FeelTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.title)
                .accessibilityAddTraits(selectedTask == task ? [.isSelected] : [])
                .accessibilityIdentifier(task.identifier)
            }
        }
        .padding(.horizontal, FeelSpacing.page).padding(.vertical, FeelSpacing.tight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }

    @ViewBuilder private func taskContent(width: CGFloat) -> some View {
        switch selectedTask {
        case .surroundings:
            surroundings(wide: width >= 700 && !dynamicTypeSize.isAccessibilitySize)
        case .find:
            FeelFindScreen(model: model, query: $findQuery, commandsFocused: $localCommandsFocused,
                           wide: width >= 700 && !dynamicTypeSize.isAccessibilitySize) {
                commandsOpenedFromFind = true
                presentedPanel = .commands
            }
        case .places:
            VStack(alignment: .leading, spacing: FeelSpacing.section) {
                SessionPlacesPanel(places: model.places, command: model.performVoiceCommand, name: $placeName, inline: true)
                SavedWorldMapsPanel(maps: model.savedMaps, command: model.performVoiceCommand)
            }
        }
    }

    private func surroundings(wide: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: FeelSpacing.section), count: wide ? 2 : 1), spacing: FeelSpacing.section) {
            Button { presentedPanel = .status } label: {
                Label(sensingLabel, systemImage: "waveform.path")
            }
            .buttonStyle(FeelSecondaryButtonStyle())
            .accessibilityIdentifier("sensingStatus")
            .accessibilityLabel("\(sensingLabel), sensing status")
            .accessibilityValue(sensingSummary)
            .accessibilityHint("Opens camera and device status. Frontal sensing does not establish a clear path.")
            .accessibilityFocused($focusedControl, equals: .status)
            describeButton
            Button { scanOpenedFromHome = true; presentedPanel = .spatialMap } label: { Label("3D scan", systemImage: "viewfinder") }
                .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("homeSpatialMap")
                .accessibilityHint("Opens real camera and LiDAR scan controls.")
                .accessibilityFocused($focusedControl, equals: .scan)
            Button { controlsOpen = false } label: { Label("Camera", systemImage: "camera") }
                .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("cameraPreview")
                .accessibilityHint("Returns to the full-screen camera and device signal.")
                .accessibilityFocused($focusedControl, equals: .preview)
            if model.mode == .live && !model.calibrated {
                Button("Floor setup") { presentedPanel = .settings }
                    .buttonStyle(FeelSecondaryButtonStyle()).accessibilityValue("Finding floor. Pins neutral.")
            }
            if model.mode == .simulation {
                Button("Simulate V sign") { model.simulateSign() }
                    .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("simulateSign")
            }
        }
    }

    private var sensingLabel: String {
        switch model.guidanceState {
        case .stopped: return model.isStarting ? "Starting camera" : "Camera off"
        case .live: return "Sensing"
        case .simulation: return "SIMULATION"
        case .trackingLost: return "Tracking lost"
        case .staleDepth: return "Waiting for depth"
        case .invalidFrame: return "Depth unavailable"
        case .uncalibrated: return "Finding floor"
        }
    }

    private var sensingSummary: String {
        let cue = model.guidanceCue.map { "Guiding: \($0.spoken)." } ?? ""
        let neutral = model.guidanceState == .live || model.guidanceState == .simulation ? "" : "Pins neutral."
        return "\(model.mode.rawValue). \(sensingLabel). \(neutral) \(cue) \(model.status). \(puck.status)"
    }

    private var describeButton: some View {
        Button {
            let result = model.performVoiceCommand(.describeAhead)
            descriptionResult = result["error"] as? String ?? ""
            UIAccessibility.post(notification: .announcement, argument: descriptionResult.isEmpty ? "Looking." : descriptionResult)
        } label: { Label("Describe", systemImage: "text.viewfinder") }
        .buttonStyle(FeelSecondaryButtonStyle())
        .disabled(!model.whereIsAvailable)
        .accessibilityIdentifier("describeAhead")
        .accessibilityLabel("Describe ahead")
        .accessibilityValue(model.describeNotice ?? (model.descriptionPending ? "Looking" : descriptionResult))
        .accessibilityHint(model.whereIsAvailable ? "Requests a spoken description of the current scene." : "Requires the live camera and fresh tracking.")
    }

    private var tactileReadout: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            PuckView(packet: model.packet, targetColumns: model.targetColumns, compact: true)
            Text("Six directions · four distance bands")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
        }
        .padding(FeelSpacing.section)
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sessionBar(panel: Bool) -> some View {
        HStack(spacing: FeelSpacing.section) {
            if model.mode == .stopped && !model.isStarting {
                Button { model.startLive() } label: { Label("Start camera", systemImage: "camera.fill") }
                    .buttonStyle(FeelPrimaryButtonStyle())
                    .accessibilityIdentifier("startCamera")
            } else {
                Button(role: .destructive) {
                    model.stop()
                    descriptionResult = ""
                    if panel { closePanel() }
                } label: { Label(dynamicTypeSize.isAccessibilitySize ? "Stop" : "Stop sensing", systemImage: "stop.fill") }
                    .buttonStyle(FeelStopButtonStyle())
                    .accessibilityLabel("Stop sensing")
                    .accessibilityIdentifier(panel ? "panelStop" : "stopSession")
                    .accessibilityHint("Stops the camera and tactile guidance. Use Pause voice to stop the microphone.")
            }
            Button {
                if voice.isActive { voice.pauseAssistant() }
                else if voice.isConfigured { voice.resumeAssistant() }
                else { presentedPanel = .voice }
            } label: {
                Label(voice.isActive ? "Pause voice" : dynamicTypeSize.isAccessibilitySize ? "Talk" : "Talk to FEEL", systemImage: voice.isActive ? "mic.slash" : "waveform")
            }
            .buttonStyle(FeelSecondaryButtonStyle())
            .accessibilityLabel(voice.isActive ? "Pause voice" : "Talk to FEEL")
            .accessibilityIdentifier("talkToFeel")
            .accessibilityValue(voice.isActive ? voice.label : "Microphone off")
            .accessibilityHint(voice.isConfigured ? "Controls the microphone and spoken responses." : "Opens voice setup. The microphone stays off until you enable it.")
        }
        .padding(.horizontal, FeelSpacing.page).padding(.vertical, FeelSpacing.compact)
        .background(FeelTheme.surface)
    }

    private func floatingPanel(_ panel: CameraPanel, availableSize: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: FeelSpacing.section) {
                Text(panel.title).font(FeelTypography.title3).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: closePanel) {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close panel")
                .accessibilityIdentifier("closeCameraPanel")
                .accessibilityFocused($focusedControl, equals: .close)
            }.padding(.horizontal, FeelSpacing.page).padding(.top, FeelSpacing.tight)
            ScrollView {
                VStack(alignment: .leading, spacing: FeelSpacing.section) {
                    switch panel {
                    case .connection: PuckConnectionPanel(puck: model.puck)
                    case .voice:
                        VoiceSetup(voice: voice) { closePanel() }
                        Button("Commands without internet") {
                            commandsOpenedFromFind = false
                            presentedPanel = .commands
                        }
                            .buttonStyle(FeelSecondaryButtonStyle())
                    case .commands:
                        LocalCommandsPanel(model: model, control: model.localVoice)
                    case .settings: settings
                    case .spatialMap:
                        SpatialMapPanel(map: model.spatialMap, model: model,
                                        showsDiagnostics: showsDiagnostics,
                                        wide: availableSize.width >= 650 && !dynamicTypeSize.isAccessibilitySize)
                    case .status:
                        CameraGuidance(model: model, puck: model.puck)
                        if let notice = model.describeNotice { Text(notice).font(FeelTypography.body) }
                        tactileReadout
                        Text("Frontal sensing only. Keep using your usual mobility aid. Neutral pins and missing map surfaces do not mean the path is clear.")
                            .font(FeelTypography.body)
                    case .preview:
                        if model.mode == .live {
                            CameraPreview(session: model.perception.session)
                                .frame(height: 180).accessibilityHidden(true)
                        } else { Text("Camera off").font(FeelTypography.body) }
                    case .advanced:
                        WhereIsSetup(model: model)
                        VenuePackSetup(venue: model.venueInfo)
                        if showsDiagnostics { MemorySimulationControls(model: model) }
                        ChalkCommandsPanel(coordinator: model.chalkCommands)
                        CloudMemoryPanel(model: model)
                        DisclosureGroup("Packet details") {
                            Text(model.packet.hex).font(FeelTypography.mono).textSelection(.enabled)
                        }
                    }
                }.padding(.horizontal, FeelSpacing.page).padding(.vertical, FeelSpacing.compact)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("cameraSettingsScroll")
            if model.mode != .stopped || model.isStarting || voice.isActive { sessionBar(panel: true) }
        }
        .frame(width: min(dynamicTypeSize.isAccessibilitySize ? 800 : 720, availableSize.width - 24),
               height: max(160, availableSize.height - 16))
        .background(FeelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("cameraFloatingPanel")
        .accessibilityAction(.escape, closePanel)
    }

    private func closePanel() {
        let returnToCommands = presentedPanel == .commands && commandsOpenedFromFind
        let focus: FocusTarget = presentedPanel == .connection ? .connection
            : presentedPanel == .voice || presentedPanel == .commands ? .voice
            : presentedPanel == .status ? .status : presentedPanel == .preview ? .preview
            : presentedPanel == .spatialMap && scanOpenedFromHome ? .scan : .settings
        presentedPanel = nil
        Task { @MainActor in
            await Task.yield()
            if returnToCommands { localCommandsFocused = true }
            else { focusedControl = controlsOpen || focus == .status || focus == .voice ? focus : .menu }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            Button { scanOpenedFromHome = false; presentedPanel = .spatialMap } label: {
                Label("Live 3D scan", systemImage: "viewfinder")
            }.buttonStyle(FeelPrimaryButtonStyle()).accessibilityIdentifier("openSpatialMap")
            Button("Advanced tools") { presentedPanel = .advanced }
                .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("advancedTools")
            if showsDiagnostics {
                Button("Simulation") {
                    model.startSimulation(); selectedTask = .surroundings; closePanel()
                }.buttonStyle(FeelSecondaryButtonStyle()).disabled(model.mode == .simulation)
                Button("Pin grid") { closePanel(); gridWalk = true }
                    .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("gridWalk")
                    .accessibilityHint("Opens the six-column visual diagnostic. It is not an accessible substitute for tactile feedback.")
            }
            DisclosureGroup("Tactile guidance") { DirectionArrowSettings(model: model) }
            if model.mode == .live { LiveSetup(model: model) }
            else {
                Text("Floor setup becomes available when the camera starts.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            }
            if let onSignOut {
                if let signedInEmail, !signedInEmail.isEmpty {
                    Text("Signed in as \(signedInEmail)").font(FeelTypography.footnote)
                }
                Button("Sign out", role: .destructive) { presentedPanel = nil; onSignOut() }
                    .buttonStyle(FeelSecondaryButtonStyle()).accessibilityIdentifier("signOut")
                    .accessibilityHint("Stops sensing and voice and returns to sign in.")
            }
        }
    }
}

private struct CameraOverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(FeelTheme.ink)
            .background(FeelTheme.canvas, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
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
                .labelStyle(.iconOnly)
                .font(FeelTypography.label).foregroundStyle(puck.isConnected ? .black : FeelTheme.ink)
                .frame(width: 44, height: 44)
                .background(puck.isConnected ? FeelTheme.pin : FeelTheme.surface, in: RoundedRectangle(cornerRadius: 10))
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
        VStack(alignment: .leading, spacing: FeelSpacing.compact) {
            Text(title).font(FeelTypography.title2).accessibilityIdentifier("guidanceTitle")
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
            } else if model.mode == .stopped {
                // While live the title alone carries the sensing state; the status line only
                // explains why the camera could not start.
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
    /// Several target columns tap together; nil falls back to the packet's single highlight.
    var targetColumns: ClosedRange<Int>? = nil
    var compact = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: FeelSpacing.section), count: PuckLayout.physicalColumnCount)

    var body: some View {
        VStack(spacing: FeelSpacing.compact) {
            HStack {
                Text("Puck").font(FeelTypography.caption)
                Spacer()
                Text("Far").font(FeelTypography.caption).foregroundStyle(FeelTheme.secondary)
            }
            ForEach((1...4).reversed(), id: \.self) { band in
                LazyVGrid(columns: columns, spacing: FeelSpacing.section) {
                    ForEach(PuckLayout.activeColumns, id: \.self) { column in
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
        .accessibilityValue(Self.signalSummary(packet: packet, targetColumns: targetColumns))
    }

    static func signalSummary(packet: FeelPacket, targetColumns: ClosedRange<Int>?) -> String {
        let pins = PuckLayout.activeColumns.map { "Column \($0), band \(packet.bands[$0])" }.joined(separator: ". ")
        if let span = targetColumns, span.count > 1 { return pins + ". Target columns \(span.lowerBound) to \(span.upperBound)" }
        return pins + (PuckLayout.activeColumns.contains(Int(packet.effectiveHighlight)) ? ". Target column \(Int(packet.effectiveHighlight))" : ". No target highlight")
    }
}

private struct DirectionArrowSettings: View {
    @ObservedObject var model: LanternModel
    var body: some View {
        FeelSection(title: "Direction arrows", systemImage: "arrow.turn.up.right") {
            Toggle("Arrows on V sign", isOn: $model.arrowsEnabled)
                .font(FeelTypography.label)
                .accessibilityIdentifier("directionArrowsToggle")
            Text("Choose a target, then hold a V sign about 30 cm in front of the camera for half a second. The pins draw one arrow along a route around mapped obstacles to the target. Later arrows play only when the route changes noticeably or you sign again. Anything within 0.9 m always shows instead.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Path wave: while you turn, a dot runs along the far row from the centre toward the route, again and again, so a one-column opening such as a doorway is easy to find. When the route is outside the pins' field the dot runs to the edge: keep turning. It never covers an obstacle pin, and a target that turns out of view is remembered for a few seconds.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The map covers only what the camera has seen in this room. Objects under 10 cm, glass and moving people can be missed. A suggested direction, not a safe route.")
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
                Text("If automatic calibration cannot find the floor, measure the lens height above it and use the manual option below. Once calibrated, the floor follows the phone at that height, so stairs and ramps keep working; recalibrate if you change how the phone is worn.")
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
                if model.finder == .teammate { PeerPanel(model: model, peer: model.peer) }
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
        view.accessibilityIgnoresInvertColors = true
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct PuckConnectionPanel: View {
    @ObservedObject var puck: BluetoothPuck
    var body: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
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
    @ObservedObject var model: LanternModel
    @ObservedObject var peer: NearbyPeerService
    var body: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            Text(peer.status).font(FeelTypography.subheadline)
            Button("Find Beacon phones") { _ = model.performVoiceCommand(.scanTeammates) }
                .buttonStyle(FeelSecondaryButtonStyle()).disabled(peer.running || !model.canFindTeammates)
            Button("Stop finding") { peer.stop() }.buttonStyle(FeelSecondaryButtonStyle())
            ForEach(peer.peers, id: \.self) { person in
                Button("Find \(person.displayName)") {
                    guard model.canFindTeammates else { return }
                    peer.invite(person)
                }.buttonStyle(FeelSecondaryButtonStyle()).disabled(!model.canFindTeammates)
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
