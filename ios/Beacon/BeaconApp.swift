import SwiftUI

@main
struct BeaconApp:App {
    @StateObject private var peer=NearbyPeerService(role:.beacon)
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        Image(systemName:"dot.radiowaves.left.and.right").font(.system(size:56)).accessibilityHidden(true)
                        Text("FEEL Beacon").font(.largeTitle.bold())
                        Text("Let a teammate find this phone. Both people must keep their app open.")
                        Text(peer.status).font(.headline).accessibilityIdentifier("beaconStatus")
                        HStack { Button("Start sharing") { peer.start() }.buttonStyle(.borderedProminent); Button("Stop",role:.destructive) { peer.stop() }.buttonStyle(.bordered) }.controlSize(.large)
                        if let name=peer.invitationName {
                            Text("Allow \(name) to find this phone?").font(.headline)
                            HStack { Button("Accept") { peer.acceptInvitation(true) }.buttonStyle(.borderedProminent); Button("Decline",role:.cancel) { peer.acceptInvitation(false) }.buttonStyle(.bordered) }
                        }
                        if let name=peer.connectedName { Text("Connected to \(name)") }
                        if let distance=peer.distance { Text(String(format:"Measured distance: %.1f m",distance)) }
                        Text("Requires compatible Ultra Wideband iPhones and local-network permission. Keep the rear cameras facing one another. No microphone, contact list, cloud account or location history is used.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }
            }.onChange(of:scenePhase) { phase in if phase == .background { peer.stop() } }
        }
    }
}
