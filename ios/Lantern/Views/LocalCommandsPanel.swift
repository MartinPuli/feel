import SwiftUI
import FeelCore

struct LocalCommandsPanel: View {
    @ObservedObject var model: LanternModel
    @ObservedObject var control: LocalVoiceControl
    @State private var text = ""
    var body: some View {
        DisclosureGroup("Commands without internet") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Local commands pause the online assistant. Tap Speak command, then Finish. You can also type.").font(.caption)
                Picker("Command language", selection: $model.localCommandLanguage) {
                    Text("English").tag(VoiceLanguage.en)
                    Text("Español").tag(VoiceLanguage.es)
                }
                HStack {
                    Button("Speak command") { model.startLocalCommand() }.disabled(control.isListening)
                    Button("Finish") { control.finish() }.disabled(!control.canFinish)
                    Button("Cancel") { control.cancel() }
                }
                TextField("For example: remember entrance", text: $text).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("localCommandText")
                Button("Run local command") { _ = model.performLocalCommand(text) }.disabled(text.isEmpty)
                Text(control.status).font(.caption)
                Text(model.localCommandStatus).font(.caption).accessibilityIdentifier("localCommandResult")
                Button("Resume online assistant") { model.resumeCloudAssistant() }
                Picker("Tactile highlights", selection: $model.tactileProfile) {
                    ForEach(AdaptiveProfile.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Text("Reduced highlighting changes tap frequency; obstacle bands remain unchanged.").font(.caption)
            }.padding(.vertical, 8)
        }
    }
}
