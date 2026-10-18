import SwiftUI

struct SavedWorldMapsPanel: View {
    @ObservedObject var maps: SavedWorldMaps
    let command: (VoiceCommand) -> [String: Any]
    var body: some View {
        DisclosureGroup("Keep this room for later") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save a mapped room and its places on this iPhone. Restoring needs the camera to recognize the same room before Recall is available.").font(.caption)
                Button("Save room and places") { _ = command(.saveWorldMap) }.disabled(maps.isBusy)
                Button("Restore saved room") { _ = command(.restoreWorldMap) }.disabled(maps.isBusy)
                Button("Delete saved room", role: .destructive) { _ = command(.deleteWorldMap) }
                Text(maps.message).font(.caption).accessibilityIdentifier("savedWorldStatus")
            }.padding(.vertical, 8)
        }
    }
}
