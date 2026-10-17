import SwiftUI

/// The reviewed venue pack FEEL reads without internet, collapsed into one row of the Assistant panel.
/// Once downloaded, every place is listed with what FEEL would say now, so VoiceOver works without the assistant.
struct VenuePackSetup: View {
    @ObservedObject var venue: VenueInfo
    @AppStorage("venuePackAddress") private var address = ""
    @State private var expanded = false
    @FocusState private var focused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Venue pack address (https://…)", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).submitLabel(.done).onSubmit { focused = false }
                    .feelField().accessibilityLabel("Venue pack address").accessibilityIdentifier("venuePackAddress")
                Button("Download venue pack") { focused = false; venue.download(from: address) }
                    .buttonStyle(FeelPrimaryButtonStyle())
                    .accessibilityIdentifier("downloadVenuePack")
                Text(venue.status)
                    .font(FeelTypography.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("venuePackStatus")
                ForEach(venue.overview, id: \.self) { line in
                    Text(line).font(FeelTypography.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if venue.pack != nil {
                    Button("Remove venue pack", role: .destructive) { venue.remove() }
                        .frame(minHeight: 44).font(FeelTypography.label)
                        .accessibilityIdentifier("removeVenuePack")
                }
            }
            .padding(.top, 12)
        } label: {
            Text(venue.pack.map { "Venue: \($0.venueName)" } ?? "Venue: none downloaded")
                .font(FeelTypography.label)
                .accessibilityHint("Reviewed venue information that works without internet. Collapsed by default.")
                .accessibilityIdentifier("venuePackRow")
        }
        .tint(FeelTheme.ink)
    }
}
