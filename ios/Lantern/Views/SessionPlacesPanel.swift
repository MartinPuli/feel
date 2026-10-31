import SwiftUI

struct SessionPlacesPanel: View {
    @ObservedObject var places: SessionPlaces
    let command: (VoiceCommand) -> [String: Any]
    @Binding var name: String
    @FocusState private var nameFocused: Bool
    @State private var rememberFormExpanded = false
    @State private var showsStatus = false
    @State private var statusDetail = ""
    var inline = false

    var body: some View {
        if inline {
            content
        } else {
            DisclosureGroup {
                content.padding(.vertical, FeelSpacing.compact)
            } label: {
                Text("Saved places")
                    .font(FeelTypography.headline)
                    .frame(minHeight: 44)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            if places.active {
                Button(role: .destructive) { _ = command(.stopPlaceGuidance) } label: {
                    Label("Stop place guidance", systemImage: "stop.fill")
                }
                .buttonStyle(FeelSecondaryButtonStyle())
                .accessibilityIdentifier("stopPlaceGuidance")
            }

            Button { rememberFormExpanded.toggle() } label: {
                Label("Remember a place", systemImage: rememberFormExpanded ? "chevron.up" : "chevron.down")
            }.buttonStyle(FeelSecondaryButtonStyle())
            .accessibilityIdentifier("rememberPlaceForm")
            .accessibilityValue(rememberFormExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Enter a name to save your current position or rename a saved place.")
            if rememberFormExpanded {
                VStack(alignment: .leading, spacing: FeelSpacing.compact) {
                    TextField("Place name", text: $name)
                        .feelField()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit { nameFocused = false }
                        .accessibilityLabel("Place name")
                        .accessibilityIdentifier("placeName")
                        .id("placeName")
                    Button("Remember here") { _ = command(.rememberPlace(name)) }
                        .buttonStyle(FeelPrimaryButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !places.contextAvailable)
                        .accessibilityHint(!places.contextAvailable ? "Start sensing and wait for tracking to remember a place."
                                           : name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a place name first."
                                           : "Saves your current position for this session. Save the room before stopping to keep it for another visit.")
                        .accessibilityIdentifier("rememberPlace")
                }.padding(.top, 8)
            }

            VStack(spacing: FeelSpacing.section) {
                Button("Set return point") { _ = command(.setReturnPoint) }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .disabled(!places.contextAvailable)
                    .accessibilityHint(places.contextAvailable ? "Remembers your current position as the return point for this session."
                                       : "Start sensing and wait for tracking to set a return point.")
                Button("Return") { _ = command(.returnToPoint) }
                    .buttonStyle(FeelSecondaryButtonStyle())
                    .disabled(places.memory.returnPoint == nil || !places.contextAvailable)
                    .accessibilityHint(!places.contextAvailable ? "Start sensing and wait for tracking to return."
                                       : places.memory.returnPoint == nil ? "Set a return point first."
                                       : "Points toward your return point. This does not establish a clear path.")
            }

            ForEach(places.memory.bookmarks) { place in
                SessionPlaceActions(id: place.id, name: place.name, replacementName: name,
                                    canRecall: places.contextAvailable, command: command)
            }

            Button("Status") {
                nameFocused = false
                statusDetail = places.message
                showsStatus = true
            }
            .buttonStyle(FeelSecondaryButtonStyle())
            .accessibilityLabel("Place status")
            .accessibilityValue(places.message)
            .accessibilityHint(places.memory.bookmarks.isEmpty
                               ? "No saved places. Open Remember a place and enter a name to save one."
                               : "Opens the current place status. Save the room before stopping to keep these places for another visit.")
            .accessibilityIdentifier("placeStatus")
        }
        .alert("Place status", isPresented: $showsStatus) {
            Button("Stop sensing", role: .destructive) { _ = command(.stop) }
            Button("Close", role: .cancel) {}
        } message: { Text(statusDetail) }
        .onChange(of: rememberFormExpanded) { expanded in
            if !expanded { nameFocused = false }
        }
        .onChange(of: places.message) { message in
            guard UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}

private struct SessionPlaceActions: View {
    let id: String
    let name: String
    let replacementName: String
    let canRecall: Bool
    let command: (VoiceCommand) -> [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: FeelSpacing.section) {
            Button("Recall \(name)") { _ = command(.recallPlace(id)) }
                .buttonStyle(FeelPrimaryButtonStyle())
                .disabled(!canRecall)
                .accessibilityHint(canRecall ? "Points toward this remembered place. This does not establish a clear path."
                                   : "Start sensing and wait for tracking to recall this place.")
            Button("Rename") { _ = command(.renamePlace(id, replacementName)) }
                .buttonStyle(FeelSecondaryButtonStyle())
                .disabled(replacementName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Rename \(name) using entered name")
                .accessibilityHint("Open Remember a place and enter the new name before renaming.")
            Button("Delete", role: .destructive) { _ = command(.deletePlace(id)) }
                .buttonStyle(FeelSecondaryButtonStyle())
                .accessibilityLabel("Delete \(name)")
        }
        .padding(.vertical, FeelSpacing.compact)
        .accessibilityElement(children: .contain)
    }
}
