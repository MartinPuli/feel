import SwiftUI

struct SavedWorldMapsPanel: View {
    @ObservedObject var maps: SavedWorldMaps
    let command: (VoiceCommand) -> [String: Any]
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: FeelSpacing.page) {
                Text("Keep a mapped room and its remembered places on this iPhone for another visit. After restoring, wait for the camera to recognize the room, then choose a place to recall.")
                    .font(FeelTypography.body)
                    .foregroundStyle(FeelTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Save room and places") { _ = command(.saveWorldMap) }
                    .buttonStyle(FeelPrimaryButtonStyle())
                    .disabled(maps.isBusy)
                Button("Restore saved room") { _ = command(.restoreWorldMap) }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .disabled(maps.isBusy)
                    .accessibilityHint("Loads the saved room. Guidance stays paused until tracking is recovered and you choose Recall.")
                Button("Delete saved room", role: .destructive) { _ = command(.deleteWorldMap) }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .disabled(maps.isBusy)
                Text(maps.message)
                    .font(FeelTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("savedWorldStatus")
            }.padding(.vertical, FeelSpacing.compact)
        } label: {
            Text("Keep this room for later")
                .font(FeelTypography.headline)
                .frame(minHeight: FeelSpacing.minimumTouch)
        }
    }
}
