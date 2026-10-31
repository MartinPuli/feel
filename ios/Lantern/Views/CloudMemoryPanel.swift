import SwiftUI

struct CloudMemoryPanel: View {
    @ObservedObject var model: LanternModel
    @State private var result = ""
    @State private var historyObject = ""
    var body: some View {
        DisclosureGroup("Cloud memory") {
            VStack(alignment: .leading, spacing: FeelSpacing.section) {
                Text("Upload future finds, room landmarks, room structure and journeys to your account. Requires sign-in and a selected venue. No camera images or audio are included.").font(FeelTypography.caption)
                Toggle("Upload future memories", isOn: Binding(get: { model.memoryUploadsEnabled }, set: {
                    result = model.performVoiceCommand(.setMemoryUploads($0))["status"] as? String ?? "Unavailable."
                })).accessibilityIdentifier("memoryUploadConsent")
                Text("Sharing lets other FEEL users use future uploaded room records. Turning either option off does not delete earlier cloud records.").font(FeelTypography.caption)
                Toggle("Share future room records", isOn: Binding(get: { model.sharedRoomMemoryEnabled }, set: {
                    result = model.performVoiceCommand(.setSharedRoomMemory($0))["status"] as? String ?? "Unavailable."
                })).disabled(!model.memoryUploadsEnabled)
                Text("Read your past finds and approved shared room memories. This sends object names and recognized room tag identifiers to the memory service; it does not upload recordings.").font(FeelTypography.caption)
                Toggle("Read cloud memories", isOn: Binding(get: { model.contextReadsEnabled }, set: {
                    let reply = model.performVoiceCommand(.setContextReads($0))
                    result = reply["status"] as? String ?? reply["error"] as? String ?? "Unavailable."
                })).disabled(!model.contextReadsAvailable).accessibilityIdentifier("contextReadConsent")
                TextField("Object you last found", text: $historyObject).textInputAutocapitalization(.never)
                    .feelField()
                    .accessibilityIdentifier("lastSeenObject")
                Button("Check last confirmed location") {
                    let reply = model.performVoiceCommand(.lastSeen(historyObject))
                    result = reply["status"] as? String ?? reply["error"] as? String ?? "Unavailable."
                }.disabled(!model.contextReadsEnabled || historyObject.trimmingCharacters(in: .whitespaces).isEmpty)
                if let notice = model.lastSeenNotice { Text(notice).font(FeelTypography.caption).accessibilityIdentifier("lastSeenNotice") }
                Button("Check upload status") { result = model.memoryUploadStatus }
                Button("Export journeys to Files") { result = model.performVoiceCommand(.exportJourneys)["status"] as? String ?? "Could not export journeys." }
                Text(result).font(FeelTypography.caption).accessibilityIdentifier("cloudMemoryResult")
            }.padding(.vertical, FeelSpacing.compact)
                .buttonStyle(FeelSecondaryButtonStyle())
        }
    }
}
