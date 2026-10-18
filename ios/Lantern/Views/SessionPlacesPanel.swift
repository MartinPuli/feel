import SwiftUI

struct SessionPlacesPanel: View {
    @ObservedObject var places: SessionPlaces
    let command: (VoiceCommand) -> [String: Any]
    @State private var name = ""
    var body: some View {
        DisclosureGroup("Saved places") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Remember your current position for this camera session.")
                    .font(.caption)
                TextField("Place name", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("placeName")
                Button("Remember here") { _ = command(.rememberPlace(name)) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("rememberPlace")
                HStack {
                    Button("Set return point") { _ = command(.setReturnPoint) }
                    Button("Return") { _ = command(.returnToPoint) }
                        .disabled(places.memory.returnPoint == nil)
                }
                ForEach(places.memory.bookmarks) { place in
                    VStack(alignment: .leading) {
                        Button("Recall \(place.name)") { _ = command(.recallPlace(place.id)) }
                        HStack {
                            Button("Rename using entered name") { _ = command(.renamePlace(place.id, name)) }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityLabel("Rename \(place.name) using entered name")
                            Button("Delete", role: .destructive) { _ = command(.deletePlace(place.id)) }
                                .accessibilityLabel("Delete \(place.name)")
                        }.font(.caption)
                    }
                }
                if places.active { Button("Stop place guidance") { _ = command(.stopPlaceGuidance) } }
                Text(places.message).font(.caption).accessibilityIdentifier("placeStatus")
            }.padding(.vertical, 8)
        }
    }
}
