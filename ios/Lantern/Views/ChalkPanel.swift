import SwiftUI

struct ChalkPanel: View {
    @ObservedObject var model: LanternModel
    @State private var token=""
    var body: some View {
        DisclosureGroup("Chalk understanding") {
            VStack(alignment:.leading,spacing:12) {
                Toggle("Use Chalk for commands",isOn:$model.cloudEnabled).accessibilityIdentifier("cloudEnabled")
                Text("Understand natural requests about your current places. Turn this off to use local finder commands. Direction and Stop remain on this phone.").font(.footnote)
                Toggle("Share command text and place names",isOn:$model.cloudSharing).accessibilityIdentifier("cloudSharing")
                Text("Sends your final typed or spoken command, place IDs and names, language, session ID, return-point availability and tracking state to your FEEL server and its configured AI provider. No audio, camera frames, coordinates or AR maps are sent.").font(.footnote)
                Toggle("Keep requests and corrections for evaluation",isOn:$model.cloudFeedbackConsent).accessibilityIdentifier("cloudRetention")
                Text("Optional. Allows the server to retain these requests and your explicit feedback. Turning this off stops future command text and context retention; it does not delete previously retained records. Basic request IDs, action types and timing may still be stored. Ask the server operator to delete retained records.").font(.footnote)
                DisclosureGroup("Connection") {
                    VStack(alignment:.leading,spacing:8) {
                        TextField("HTTPS FEEL server",text:$model.cloudEndpoint).textContentType(.URL).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("cloudEndpoint")
                        SecureField("FEEL app token",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("cloudToken")
                        Button("Save connection") { model.saveCloudConnection(token:token); token="" }.buttonStyle(.bordered)
                        Text("Use the FEEL server app token, never a Chalk provider key. Saving an empty token removes the saved credential.").font(.footnote)
                    }.padding(.top,8)
                }
                if model.cloudPending {
                    ProgressView("Understanding…")
                    Button("Cancel request") { model.cancelCloud() }.buttonStyle(.bordered)
                }
                Text(model.cloudNotice).accessibilityIdentifier("cloudNotice")
                if let latency=model.cloudLatency { Text(String(format:"Request round trip: %.0f ms",latency)).font(.footnote).accessibilityIdentifier("cloudLatency") }
                if model.cloudFeedbackAvailable {
                    Text("Did FEEL understand you?").font(.headline)
                    Picker("Correct destination, if needed",selection:$model.cloudCorrectedPlace) {
                        Text("No destination correction").tag("")
                        ForEach(model.spatialMemory.bookmarks,id:\.id) { place in Text(place.name).tag(place.id) }
                    }.pickerStyle(.menu)
                    Button("Correct") { model.sendCloudFeedback(correct:true) }.buttonStyle(.bordered)
                    Button("Incorrect — send feedback") { model.sendCloudFeedback(correct:false) }.buttonStyle(.bordered)
                    Text("Feedback never starts movement or changes your destination.").font(.footnote)
                }
            }.padding(.top,8)
        }
    }
}
