import SwiftUI

/// Optional Chalk gateway settings for "Where is X?", collapsed into one row of the Assistant panel.
/// Without them Where-is runs on-device. The settings stay in Keychain; the self-test sends a bundled
/// sample photo through the real request path.
struct WhereIsSetup: View {
    @ObservedObject var model: LanternModel
    @State private var expanded = false
    @State private var host = ChalkConfiguration.defaultHost
    @State private var environment = ""
    @State private var key = ""
    @State private var modelName = ChalkConfiguration.defaultModel
    @State private var setupError = ""
    @FocusState private var focused: Field?
    private enum Field { case host, environment, key, model }

    private var configured: Bool { model.chalkConfiguration?.isValid == true }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                field("Gateway address", text: $host, identifier: "chalkHost", focus: .host, keyboard: .URL)
                field("Environment ID", text: $environment, identifier: "chalkEnvironment", focus: .environment)
                SecureField(configured ? "Gateway key (saved)" : "Gateway key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused, equals: .key).submitLabel(.done).onSubmit { focused = nil }
                    .feelField().accessibilityIdentifier("chalkKey")
                field("Model", text: $modelName, identifier: "chalkModel", focus: .model)
                if !setupError.isEmpty {
                    Text(setupError).font(FeelTypography.footnote).accessibilityIdentifier("chalkSetupError")
                }
                Button("Save Where-is setup") { save() }
                    .buttonStyle(FeelPrimaryButtonStyle())
                    .accessibilityIdentifier("saveChalkSetup")
                if configured {
                    Button("Test with a sample photo") { model.runWhereIsSelfTest() }
                        .buttonStyle(FeelSecondaryButtonStyle())
                        .disabled(model.whereIsSelfTestRunning)
                        .accessibilityIdentifier("whereIsSelfTest")
                    Text(model.whereIsSelfTest)
                        .font(FeelTypography.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("whereIsSelfTestResult")
                    Button("Forget Where-is setup", role: .destructive) {
                        model.forgetChalkConfiguration(); key = ""; environment = ""; setupError = ""
                    }
                    .frame(minHeight: 44).font(FeelTypography.label)
                    .accessibilityIdentifier("forgetChalkSetup")
                }
            }
            .padding(.top, 12)
        } label: {
            Text(configured ? "Where-is: Chalk ready" : "Where-is: on-device only")
                .font(FeelTypography.label)
                .accessibilityHint("Optional Chalk gateway for any object. Collapsed by default.")
                .accessibilityIdentifier("whereIsStatus")
        }
        .tint(FeelTheme.ink)
        .onAppear {
            if let configuration = model.chalkConfiguration {
                host = configuration.apiHost; environment = configuration.environmentId; modelName = configuration.model
            }
        }
    }

    /// Done on the keyboard dismisses it, so the next field is reachable on a landscape phone.
    private func field(_ title: String, text: Binding<String>, identifier: String, focus: Field, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focused, equals: focus).submitLabel(.done).onSubmit { focused = nil }
            .feelField().accessibilityLabel(title).accessibilityIdentifier(identifier)
    }

    private func save() {
        let trimmed = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        let savedKey = model.chalkConfiguration?.routerApiKey ?? ""
        let configuration = ChalkConfiguration(apiHost: trimmed(host), routerApiKey: key.isEmpty ? savedKey : trimmed(key),
                                               environmentId: trimmed(environment), model: trimmed(modelName))
        do {
            try model.saveChalkConfiguration(configuration)
            key = ""; setupError = ""
        } catch KeychainStoreError.invalid {
            setupError = "Use an HTTPS gateway address, an environment ID, a key of at least 16 characters and a model name."
        } catch {
            setupError = "Couldn't store the settings in Keychain on this device. Unlock the phone and try again."
        }
    }
}
