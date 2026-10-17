import SwiftUI

struct VoiceControl: View {
    @ObservedObject var voice: RealtimeVoiceSession
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

/// The Assistant panel: status, a typed fallback, two toggles, and the one-time connection.
/// Explanations live in accessibility hints, not on screen.
struct VoiceSetup: View {
    @ObservedObject var voice: RealtimeVoiceSession
    let close: () -> Void
    @State private var endpoint = ""
    @State private var accessToken = ""
    @State private var setupError = ""
    @State private var showSetup = false
    @State private var typedRequest = ""
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
            if voice.audioUnavailable {
                Text("No sound output here. Captions still work.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .accessibilityIdentifier("voiceAudioUnavailable")
            }
            if voice.isActive {
                HStack(spacing: 10) {
                    TextField("Type a request", text: $typedRequest)
                        .feelField().submitLabel(.send)
                        .onSubmit { sendTyped() }
                        .accessibilityLabel("Type a request")
                        .accessibilityHint("The same as saying it.")
                        .accessibilityIdentifier("voiceTypedRequest")
                    Button("Send") { sendTyped() }
                        .buttonStyle(FeelSecondaryButtonStyle()).frame(width: 96)
                        .disabled(typedRequest.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("voiceSend")
                }
            }
            Toggle("Spoken replies", isOn: Binding(get: { voice.spokenOutputEnabled }, set: { voice.setSpokenOutput($0) }))
                .font(FeelTypography.label)
                .accessibilityHint("Mute speech while keeping voice commands. Say speak again to unmute.")
                .accessibilityIdentifier("spokenReplies")
            Toggle("Useful updates", isOn: $voice.proactiveEnabled)
                .font(FeelTypography.label)
                .accessibilityHint("Announces nearby obstacles, target changes and sensing changes while voice is on.")
                .accessibilityIdentifier("proactiveVoice")
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
                TextField("Voice service address (https://…/session)", text: $endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .feelField().accessibilityLabel("Voice service address")
                    .accessibilityIdentifier("voiceEndpoint")
                SecureField("Access code", text: $accessToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .feelField().accessibilityIdentifier("voiceAccessCode")
                if !setupError.isEmpty { Text(setupError).font(FeelTypography.footnote).accessibilityIdentifier("voiceSetupError") }
                Button("Enable assistant") {
                    let token = accessToken.isEmpty && endpoint == voice.configuration?.endpoint ? voice.configuration?.accessToken ?? "" : accessToken
                    do {
                        try voice.saveConfiguration(endpoint: endpoint, accessToken: token)
                        accessToken = ""; voice.resumeAssistant(); close()
                    } catch {
                        setupError = "Use an HTTPS service address and an access code of at least 32 characters, not a raw API key."
                    }
                }
                .buttonStyle(FeelPrimaryButtonStyle())
                .accessibilityIdentifier("saveVoiceSetup")
                if voice.isConfigured {
                    Button("Forget voice connection", role: .destructive) {
                        voice.forgetConfiguration(); endpoint = ""; accessToken = ""
                    }.frame(minHeight: 44)
                }
            }
            Text("Microphone audio goes to OpenAI while FEEL is open.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
        }
        .onAppear { endpoint = voice.configuration?.endpoint ?? "" }
    }

    private func sendTyped() {
        if voice.sendText(typedRequest) { typedRequest = "" }
    }
}
