import SwiftUI

struct VoiceControl: View {
    @ObservedObject var voice: GrokVoiceSession
    var compact = false
    var showCaption = true
    let openSetup: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button {
                if voice.isActive { voice.pauseAssistant() }
                else if !voice.isConfigured { openSetup() }
                else { voice.resumeAssistant() }
            } label: {
                HStack(spacing: 10) {
                    if voice.phase == .connecting { ProgressView().tint(FeelTheme.accent) }
                    else { Image(systemName: voice.isActive ? "mic.fill" : "mic.slash") }
                    if !compact { Text(voice.label).font(FeelTypography.label) }
                }
                .frame(minWidth: compact ? 48 : 180, minHeight: 48)
                .padding(.horizontal, compact ? 0 : 14)
                .foregroundStyle(FeelTheme.accent)
                .background(FeelTheme.inset, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isActive ? "Pause assistant" : voice.isConfigured ? "Resume assistant" : "Assistant settings")
            .accessibilityValue(voice.isActive ? voice.label : "Microphone off")
            .accessibilityHint(voice.isActive ? "Pauses the microphone. You can also say pause assistant." : "The assistant listens automatically when FEEL is open after voice setup.")
            .accessibilityIdentifier("voiceControl")
            if showCaption && !compact {
                if !voice.errorMessage.isEmpty {
                    Button { openSetup() } label: {
                        Text(voice.errorMessage).font(FeelTypography.footnote).lineLimit(2)
                    }
                    .accessibilityIdentifier("voiceRecovery")
                } else if !voice.caption.isEmpty {
                    Text(voice.caption).font(FeelTypography.footnote).lineLimit(2)
                        .accessibilityIdentifier("voiceCaption")
                }
            }
        }
        .frame(maxWidth: compact ? 48 : 420)
        .padding(compact ? 0 : 8)
        .background {
            if !compact && showCaption && (!voice.caption.isEmpty || !voice.errorMessage.isEmpty) {
                RoundedRectangle(cornerRadius: 20).fill(FeelTheme.surface)
            }
        }
    }
}

struct VoiceSetup: View {
    @ObservedObject var voice: GrokVoiceSession
    let close: () -> Void
    @State private var endpoint = ""
    @State private var accessToken = ""
    @State private var setupError = ""
    @State private var showSetup = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FEEL listens while the app is open. Say what you need.")
                .font(FeelTypography.body)
            Text("Use your phone or headphones. Say find a door, check sensing, or stop. You can interrupt at any time.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            Toggle("Useful updates", isOn: $voice.proactiveEnabled)
                .font(FeelTypography.label)
                .accessibilityHint("Announces target and sensing changes while voice is on.")
                .accessibilityIdentifier("proactiveVoice")
            Text("FEEL speaks when it finds your target or loses sensing. It stays quiet while you talk.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            if voice.needsMicrophoneSettings {
                Button("Allow microphone in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.buttonStyle(FeelSecondaryButtonStyle())
            }
            if voice.isConfigured && !showSetup {
                Button(voice.isActive ? "Pause assistant" : "Resume assistant") {
                    if voice.isActive { voice.pauseAssistant() } else { voice.resumeAssistant() }
                    close()
                }.buttonStyle(FeelPrimaryButtonStyle()).accessibilityIdentifier("startVoice")
                Button("Connection settings") { showSetup = true }
                    .frame(minHeight: 44).font(FeelTypography.label)
            } else {
                Text("One-time assistant setup")
                    .font(FeelTypography.headline).accessibilityAddTraits(.isHeader)
                Text("Enter your FEEL voice service address and access code. Your xAI API key stays on the server.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                TextField("https://your-service/session", text: $endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Voice service address")
                    .accessibilityIdentifier("voiceEndpoint")
                SecureField("Access code", text: $accessToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("voiceAccessCode")
                if !setupError.isEmpty { Text(setupError).font(FeelTypography.footnote).accessibilityIdentifier("voiceSetupError") }
                Button("Enable assistant") {
                    let token = accessToken.isEmpty && endpoint == voice.configuration?.endpoint ? voice.configuration?.accessToken ?? "" : accessToken
                    do {
                        try voice.saveConfiguration(endpoint: endpoint, accessToken: token)
                        accessToken = ""; voice.resumeAssistant(); close()
                    } catch { setupError = "Use an HTTPS service address and an access code of at least 32 characters." }
                }
                .buttonStyle(FeelPrimaryButtonStyle())
                .accessibilityIdentifier("saveVoiceSetup")
                if voice.isConfigured {
                    Button("Forget voice connection", role: .destructive) {
                        voice.forgetConfiguration(); endpoint = ""; accessToken = ""
                    }.frame(minHeight: 44)
                }
            }
            Text("Grok receives microphone audio and the app status needed to answer while FEEL is open. Camera images stay on your phone. Listening pauses in the background and resumes when you return, unless you pause the assistant.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
        }
        .onAppear { endpoint = voice.configuration?.endpoint ?? "" }
    }
}
