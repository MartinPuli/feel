import SwiftUI

struct ChalkCommandsPanel: View {
    @ObservedObject var coordinator: ChalkCommandCoordinator
    @State private var utterance = ""
    @State private var token = ""
    @State private var correction = ""
    @State private var confirmingDeletion = false

    var body: some View {
        DisclosureGroup("Cloud place commands") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Interpret requests about saved places. Local Stop and local commands remain available.").font(.caption)
                Toggle("Share requests with Chalk", isOn: $coordinator.sharingEnabled)
                    .accessibilityIdentifier("chalkCommandSharing")
                Text("Sends your text and saved place names through the FEEL service to Chalk and its model provider.")
                    .font(.caption)
                Toggle("Save requests for feedback and evaluation", isOn: $coordinator.retentionEnabled)
                Text("Optional retention on the FEEL service. Provider retention is configured separately.").font(.caption)
                DisclosureGroup("Service setup") {
                    TextField("HTTPS service root", text: $coordinator.endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).textFieldStyle(.roundedBorder)
                    SecureField("FEEL app access token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Button("Save access token") { if coordinator.saveToken(token) { token = "" } }
                            .disabled(token.isEmpty)
                        if coordinator.hasToken { Button("Remove token") { _ = coordinator.saveToken(""); token = "" } }
                    }
                    Text("Use a dedicated app token, never a Chalk provider key.").font(.caption)
                }
                TextField("For example: take me back to the entrance", text: $utterance)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("chalkCommandText")
                HStack {
                    Button("Send request") { coordinator.submit(utterance) }
                        .disabled(utterance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isBusy)
                    if coordinator.isBusy { Button("Cancel request") { coordinator.cancel() } }
                }
                Text(coordinator.status).font(.caption).accessibilityIdentifier("chalkCommandStatus")
                if coordinator.canGiveFeedback {
                    HStack {
                        Button("That was correct") { coordinator.submitFeedback(correct: true) }
                        Button("That was wrong") { coordinator.submitFeedback(correct: false) }
                    }.disabled(coordinator.isBusy)
                    if !coordinator.correctionPlaces.isEmpty {
                        Picker("Intended place", selection: $correction) {
                            Text("Choose a place").tag("")
                            ForEach(coordinator.correctionPlaces, id: \.id) { place in Text(place.name).tag(place.id) }
                        }
                        Button("Save destination correction") {
                            coordinator.submitFeedback(correct: false, correctedPlaceId: correction)
                        }.disabled(correction.isEmpty || coordinator.isBusy)
                    }
                }
                Button("Delete command history on this server", role: .destructive) { confirmingDeletion = true }
                    .disabled(coordinator.isBusy || coordinator.historySessionCount == 0)
                    .confirmationDialog("Delete this device's saved command sessions?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                        Button("Delete saved sessions", role: .destructive) { coordinator.deleteHistory() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Deletes FEEL command traces and corrections for sessions recorded by this device. It does not delete saved places or provider logs.")
                    }
            }.padding(.vertical, 8)
        }
    }
}
