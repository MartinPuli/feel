import SwiftUI

@main
struct BeaconApp: App {
    @StateObject private var peer = NearbyPeerService(role: .beacon)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                BeaconView(peer: peer)
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background { peer.stop() }
            }
        }
    }
}

private struct BeaconView: View {
    @ObservedObject var peer: NearbyPeerService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var invitationFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction

                if let name = peer.invitationName {
                    invitation(from: name)
                }

                FeelSection(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(peer.status)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("beaconStatus")

                        if let name = peer.connectedName {
                            Label("Connected to \(name)", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let distance = peer.distance {
                            Text(String(format: "Measured distance: %.1f m", distance))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if peer.running {
                            Text("If sharing fails or a connection stalls, tap Stop, then Start sharing to try again.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                FeelSection(title: "Before you connect", systemImage: "hand.raised") {
                    Text("Requires compatible Ultra Wideband iPhones and local-network permission. Keep the rear cameras facing one another. No microphone, contact list, cloud account or location history is used.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(FeelTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sessionControls
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: peer.invitationName) { name in
            invitationFocused = name != nil
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(FeelTheme.accent)
                .frame(width: 64, height: 64)
                .background(FeelTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            Text("FEEL Beacon")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Let a teammate find this phone. Both people must keep their app open.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func invitation(from name: String) -> some View {
        FeelSection(title: "Connection request", systemImage: "person.crop.circle.badge.questionmark") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Allow \(name) to find this phone?")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($invitationFocused)

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 12))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Button("Accept") { peer.acceptInvitation(true) }
                        .buttonStyle(FeelPrimaryButtonStyle())
                    Button("Decline", role: .cancel) { peer.acceptInvitation(false) }
                        .buttonStyle(FeelSecondaryButtonStyle())
                }
            }
        }
    }

    private var sessionControls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button("Start sharing") { peer.start() }
                .buttonStyle(FeelPrimaryButtonStyle())
                .disabled(peer.running)
                .accessibilityHint(peer.running ? "Sharing has already started. Stop to end the session." : "Allows Lantern phones to request a connection. You choose whether to accept.")
            Button("Stop", role: .destructive) { peer.stop() }
                .buttonStyle(FeelStopButtonStyle())
                .disabled(!peer.running)
                .accessibilityHint("Ends sharing and disconnects your teammate.")
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(FeelTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(FeelTheme.border).frame(height: 1)
        }
    }
}
