import SwiftUI
import ARKit
import FeelCore

struct LanternView:View {
    @ObservedObject var model:LanternModel
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack(alignment:.firstTextBaseline) {
                        Text("FEEL").font(.largeTitle.bold())
                        Spacer()
                        Text(model.mode.rawValue).font(.headline).padding(8).background(model.mode == .simulation ? Color.orange : Color.blue).foregroundColor(.white).clipShape(Capsule())
                    }
                    Text(model.guidanceState == .live ? "Live depth estimates · physical performance unverified" : model.guidanceState.rawValue).font(.headline)
                        .accessibilityLabel("Guidance state: \(model.guidanceState.rawValue)")
                    Text(model.status).foregroundStyle(.secondary)
                    HStack {
                        Button("Live sensing") { model.startLive() }.buttonStyle(.borderedProminent)
                        Button("Simulation") { model.startSimulation() }.buttonStyle(.bordered)
                        Button("Stop",role:.destructive) { model.stop() }.buttonStyle(.borderedProminent)
                    }.controlSize(.large)
                    if model.mode == .simulation { Text("SIMULATION: Synthetic inputs. No simulated movement sent to hardware.").font(.headline).foregroundColor(.orange) }
                    PuckView(packet:model.packet)
                    Text(model.targetDescription).font(.title3).accessibilityIdentifier("targetStatus")
                    if model.mode == .live {
                        CameraPreview(session:model.perception.session).frame(height:180).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
                        Text("Mount landscape-left: rear camera forward, top edge to your left; keep the phone upright. Measure lens height above the floor.")
                        Stepper(value:$model.cameraHeight,in:0.6...2.1,step:0.05) { Text(String(format:"Camera height: %.2f m",model.cameraHeight)) }
                        Button(model.calibrated ? "Recalibrate floor" : "Calibrate floor") { model.calibrate() }.buttonStyle(.bordered)
                        Picker("Find",selection:$model.finder) {
                            ForEach(FinderMode.allCases) { mode in Text(mode.rawValue).tag(mode).disabled(mode == .chair && !model.detectorAvailable) }
                        }.pickerStyle(.menu)
                        Text(model.detectorStatus).font(.footnote)
                        if model.finder == .door { Text("Door candidate uses rectangle shape. It cannot confirm a door or a safe opening.").font(.footnote) }
                        if model.finder == .teammate { PeerPanel(peer:model.peer) }
                    }
                    PuckConnectionPanel(puck:model.puck)
                    DisclosureGroup("Packet and test notes") {
                        VStack(alignment:.leading,spacing:8) {
                            Text(model.packet.hex).font(.system(.body,design:.monospaced)).textSelection(.enabled)
                            Text("Columns run left to right. Rows run near (wrist) to far (fingers). One pin per column. A highlighted pin indicates target bearing; it does not establish a safe path.")
                            Text("Unknown depth and lost tracking produce neutral pins. Neutral is not proof the area is clear. Indoor supervised prototype; use your usual mobility aid.")
                        }.font(.footnote)
                    }
                }.padding(20)
            }.navigationTitle("FEEL V1").navigationBarTitleDisplayMode(.inline)
        }
    }
}
struct PuckView:View {
    let packet:FeelPacket
    var body:some View {
        VStack(spacing:8) {
            Text("Fingers · far").font(.caption)
            ForEach((1...4).reversed(),id:\.self) { band in
                HStack(spacing:12) {
                    ForEach(0..<7,id:\.self) { column in
                        Circle().fill(packet.bands[column]==UInt8(band) ? (packet.effectiveHighlight==UInt8(column) ? Color.orange : Color.blue) : Color.gray.opacity(0.15))
                            .frame(width:28,height:28)
                    }
                }
            }
            Text("Left ← Wrist · near → Right").font(.caption)
        }.frame(maxWidth:.infinity).padding().background(Color.secondary.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:16))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("Virtual puck")
            .accessibilityValue(packet.bands.enumerated().map { "Column \($0.offset+1), band \($0.element)" }.joined(separator:". ") + (packet.effectiveHighlight < 7 ? ". Target column \(Int(packet.effectiveHighlight)+1)" : ". No target highlight"))
    }
}
struct CameraPreview:UIViewRepresentable {
    let session:ARSession
    func makeUIView(context:Context)->ARSCNView { let view=ARSCNView(); view.session=session; view.automaticallyUpdatesLighting=false; return view }
    func updateUIView(_ uiView:ARSCNView,context:Context) {}
}
struct PuckConnectionPanel:View {
    @ObservedObject var puck:BluetoothPuck
    var body:some View {
        DisclosureGroup("Puck connection") {
            VStack(alignment:.leading,spacing:10) {
                Text(puck.status); Text(puck.boardStatus).font(.caption)
                HStack { Button("Scan for puck") { puck.scan() }; Button("Disconnect") { puck.disconnect() } }.buttonStyle(.bordered)
                ForEach(puck.devices,id:\.identifier) { device in Button("Connect \(device.name ?? "FEEL puck")") { puck.connect(device) }.buttonStyle(.bordered) }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
struct PeerPanel:View {
    @ObservedObject var peer:NearbyPeerService
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text(peer.status)
            HStack { Button("Find Beacon phones") { peer.start() }; Button("Stop finding") { peer.stop() } }.buttonStyle(.bordered)
            ForEach(peer.peers,id:\.self) { person in Button("Find \(person.displayName)") { peer.invite(person) }.buttonStyle(.bordered) }
            Text("The teammate accepts on Beacon. Keep both apps foreground. Direction can be unavailable; no tactile target is sent without a current AR direction.").font(.footnote)
        }
    }
}
