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
    @State private var provider: VoiceProvider = .grok
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
                Text("Sound output is unavailable on this device. Captions and actions still work.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .accessibilityIdentifier("voiceAudioUnavailable")
            }
            if voice.isActive {
                HStack(spacing: 10) {
                    TextField("Type a request", text: $typedRequest)
                        .feelField().submitLabel(.send)
                        .onSubmit { sendTyped() }
                        .accessibilityLabel("Type a request")
                        .accessibilityHint("The same as saying it. Useful in a loud room or with a keyboard.")
                        .accessibilityIdentifier("voiceTypedRequest")
                    Button("Send") { sendTyped() }
                        .buttonStyle(FeelSecondaryButtonStyle()).frame(width: 96)
                        .disabled(typedRequest.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("voiceSend")
                }
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
                Picker("Voice service", selection: $provider) {
                    Text("Grok").tag(VoiceProvider.grok)
                    Text("OpenAI").tag(VoiceProvider.openai)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("voiceProvider")
                Text(provider == .grok
                     ? "Grok through your FEEL voice service: enter its address and access code. Your xAI API key stays on the server."
                     : "OpenAI Realtime. Enter your OpenAI API key; it stays in this phone's Keychain. Or enter a token service address and its access code instead.")
                    .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
                    .accessibilityIdentifier("voiceProviderNote")
                TextField(provider == .grok ? "https://your-service/session" : "Token service address (optional)", text: $endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .feelField().accessibilityLabel("Voice service address")
                    .accessibilityIdentifier("voiceEndpoint")
                SecureField(provider == .grok ? "Access code" : (endpoint.isEmpty ? "OpenAI API key" : "Access code"), text: $accessToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .feelField().accessibilityIdentifier("voiceAccessCode")
                if !setupError.isEmpty { Text(setupError).font(FeelTypography.footnote).accessibilityIdentifier("voiceSetupError") }
                Button("Enable assistant") {
                    let token = accessToken.isEmpty && endpoint == voice.configuration?.endpoint ? voice.configuration?.accessToken ?? "" : accessToken
                    do {
                        try voice.saveConfiguration(provider: provider, endpoint: endpoint, accessToken: token)
                        accessToken = ""; voice.resumeAssistant(); close()
                    } catch {
                        setupError = provider == .grok
                            ? "Use an HTTPS service address and an access code of at least 32 characters, not a raw API key."
                            : "Enter an OpenAI API key of at least 32 characters, or an HTTPS token service address with its access code."
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
            Text("\(voice.configuration?.provider.displayName ?? provider.displayName) receives microphone audio and the app status needed to answer while FEEL is open. Camera images leave the phone only for a Where-is request. Listening pauses in the background and resumes when you return, unless you pause the assistant.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
        }
        .onAppear {
            endpoint = voice.configuration?.endpoint ?? ""
            provider = voice.configuration?.provider ?? .grok
        }
    }

    private func sendTyped() {
        if voice.sendText(typedRequest) { typedRequest = "" }
    }
}
