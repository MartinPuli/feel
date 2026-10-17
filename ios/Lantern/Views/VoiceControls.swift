import SwiftUI

struct VoiceControl: View {
    @ObservedObject var voice: GrokVoiceSession
    let openSetup: () -> Void

    var body: some View {
        Button(action: openSetup) {
            Group {
                if voice.phase == .connecting { ProgressView().tint(FeelTheme.accent) }
                else { Image(systemName: voice.isActive ? "mic.fill" : "mic.slash") }
            }
            .font(.system(size: 18, weight: .bold))
            .frame(width: 48, height: 48)
            .foregroundStyle(voice.isActive ? .black : FeelTheme.ink)
            .feelBlock(Circle(), fill: voice.isActive ? FeelTheme.pin : FeelTheme.paper, shadow: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assistant settings")
        .accessibilityValue(voice.isActive ? voice.label : "Microphone off")
        .accessibilityHint("Opens assistant status and pause or resume controls. You can also say pause assistant.")
        .accessibilityIdentifier("voiceControl")
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
            Text(voice.label).font(FeelTypography.headline)
            if !voice.errorMessage.isEmpty {
                Text(voice.errorMessage).font(FeelTypography.footnote)
                    .accessibilityIdentifier("voiceRecovery")
            } else if !voice.caption.isEmpty {
                Text(voice.caption).font(FeelTypography.body)
                    .accessibilityIdentifier("voiceCaption")
            }
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
