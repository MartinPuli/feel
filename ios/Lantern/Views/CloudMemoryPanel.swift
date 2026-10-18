import SwiftUI

struct CloudMemoryPanel: View {
    @ObservedObject var model: LanternModel
    @State private var result = ""
    var body: some View {
        DisclosureGroup("Cloud memory") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Upload future finds, room landmarks, room structure and journeys to your account. Requires sign-in and a selected venue. No camera images or audio are included.").font(.caption)
                Toggle("Upload future memories", isOn: Binding(get: { model.memoryUploadsEnabled }, set: {
                    result = model.performVoiceCommand(.setMemoryUploads($0))["status"] as? String ?? "Unavailable."
                })).accessibilityIdentifier("memoryUploadConsent")
                Text("Sharing lets other FEEL users use future uploaded room records. Turning either option off does not delete earlier cloud records.").font(.caption)
                Toggle("Share future room records", isOn: Binding(get: { model.sharedRoomMemoryEnabled }, set: {
                    result = model.performVoiceCommand(.setSharedRoomMemory($0))["status"] as? String ?? "Unavailable."
                })).disabled(!model.memoryUploadsEnabled)
                Button("Check upload status") { result = model.memoryUploadStatus }
                Button("Export journeys to Files") { result = model.performVoiceCommand(.exportJourneys)["status"] as? String ?? "Could not export journeys." }
                Text(result).font(.caption).accessibilityIdentifier("cloudMemoryResult")
            }.padding(.vertical, 8)
        }
    }
}
