import SwiftUI

/// Chalk gateway settings for "Where is X?", kept in Keychain, plus a self-test that sends a
/// bundled sample photo through the real request path. Lives in the Assistant panel.
struct WhereIsSetup: View {
    @ObservedObject var model: LanternModel
    @State private var host = ChalkConfiguration.defaultHost
    @State private var environment = ""
    @State private var key = ""
    @State private var modelName = ChalkConfiguration.defaultModel
    @State private var setupError = ""

    private var configured: Bool { model.chalkConfiguration?.isValid == true }

    var body: some View {
        FeelSection(title: "Where-is setup") {
            Text(configured ? "Where-is ready" : "Where-is not set up")
                .font(FeelTypography.label)
                .accessibilityIdentifier("whereIsStatus")
            Text("“Where is the desk?” sends one camera photo through Chalk's gateway to a vision model, then the pins point at the answer. These settings stay in Keychain.")
                .font(FeelTypography.footnote).foregroundStyle(FeelTheme.secondary)
            field("Gateway address", text: $host, identifier: "chalkHost", keyboard: .URL)
            field("Environment ID", text: $environment, identifier: "chalkEnvironment")
            SecureField(configured ? "Gateway key (saved)" : "Gateway key", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("chalkKey")
            field("Model", text: $modelName, identifier: "chalkModel")
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
        .onAppear {
            if let configuration = model.chalkConfiguration {
                host = configuration.apiHost; environment = configuration.environmentId; modelName = configuration.model
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, identifier: String, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
            .textFieldStyle(.roundedBorder).accessibilityLabel(title).accessibilityIdentifier(identifier)
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
