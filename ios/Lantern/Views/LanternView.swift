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
                        Button("Memory simulation") { model.startSimulation(memory:true) }.buttonStyle(.bordered).accessibilityIdentifier("memorySimulation")
                        Button("Stop",role:.destructive) { model.stop() }.buttonStyle(.borderedProminent)
                    }.controlSize(.large)
                    if model.mode == .simulation { Text("SIMULATION: Synthetic inputs. No simulated movement sent to hardware.").font(.headline).foregroundColor(.orange) }
                    if model.memoryControlsVisible { MemoryPanel(model:model) }
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
            }.navigationTitle("FEEL V2").navigationBarTitleDisplayMode(.inline)
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


struct MemoryPanel:View {
    @ObservedObject var model:LanternModel
    @FocusState private var editingName:Bool
    var body:some View {
        GroupBox("My Places") {
            VStack(alignment:.leading,spacing:12) {
                Text("Remember the current phone position. Places and the return point are cleared when sensing stops, restarts, or is interrupted.").font(.footnote)
                Text(model.memoryNotice).accessibilityIdentifier("memoryNotice")
                HStack {
                    TextField("Place name",text:$model.placeName).textFieldStyle(.roundedBorder)
                        .focused($editingName).submitLabel(.done).onSubmit { editingName=false }
                        .accessibilityLabel("Place name").accessibilityIdentifier("placeName")
                    Button("Remember") { editingName=false; model.remember() }.buttonStyle(.borderedProminent).accessibilityIdentifier("rememberPlace")
                        .accessibilityHint("Save your current tracked phone position with this name")
                }
                Text("\(model.spatialMemory.bookmarks.count) places in this session").accessibilityIdentifier("placesCount")
                if !model.spatialMemory.bookmarks.isEmpty {
                    Picker("Saved place",selection:Binding(get:{ model.spatialMemory.selectedID ?? "" },set:{ if !$0.isEmpty { model.selectPlace($0) } })) {
                        Text("Choose a place").tag("")
                        ForEach(model.spatialMemory.bookmarks) { place in Text(place.name).tag(place.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("savedPlaces")
                    HStack {
                        Button("Recall") { editingName=false; model.recall() }.buttonStyle(.borderedProminent).disabled(model.selectedPlace == nil).accessibilityIdentifier("recallPlace")
                        Button("Rename") { editingName=false; model.renameSelectedPlace() }.disabled(model.selectedPlace == nil)
                        Button("Delete",role:.destructive) { editingName=false; model.deleteSelectedPlace() }.disabled(model.selectedPlace == nil)
                    }.buttonStyle(.bordered)
                }
                HStack {
                    Button("Set return point") { editingName=false; model.setReturnPoint() }.accessibilityIdentifier("setReturnPoint")
                        .accessibilityHint("Replace the return point with your current tracked phone position")
                    Button("Return") { model.returnToPoint() }.disabled(model.spatialMemory.returnPoint == nil).accessibilityIdentifier("returnToPoint")
                    Button("Stop guidance") { model.stopMemoryGuidance() }.accessibilityIdentifier("stopMemoryGuidance")
                }.buttonStyle(.bordered)
                if model.spatialMemory.returnPoint != nil { Text("Return point is set for this session.").font(.footnote) }
                if let guidance=model.memoryGuidance {
                    Text(model.mode == .live && model.guidanceState != .live ? "Place guidance paused: \(model.guidanceState.rawValue)" : "Place guidance: \(guidance.state.rawValue)")
                        .font(.headline).accessibilityIdentifier("memoryGuidanceState")
                }
                if model.mode == .simulation,model.simulationScene == .memory {
                    Divider()
                    Text("SIMULATED motion").font(.headline)
                    Text(String(format:"Position x %.1f m, z %.1f m · yaw %.0f°",model.simulatedPosition.x,model.simulatedPosition.z,model.simulatedYaw)).font(.footnote)
                    HStack {
                        Button("Move forward 1 m") { model.simulateMove(metres:1) }.accessibilityIdentifier("simForward")
                        Button("Move back 1 m") { model.simulateMove(metres:-1) }.accessibilityIdentifier("simBack")
                        Button("Turn left 45°") { model.simulateTurn(degrees:45) }.accessibilityIdentifier("simLeft")
                        Button("Turn right 45°") { model.simulateTurn(degrees:-45) }.accessibilityIdentifier("simRight")
                    }.buttonStyle(.bordered)
                    Toggle("Simulated tracking available",isOn:$model.simulatedTracking).accessibilityIdentifier("simTracking")
                    Button("Reset simulated session") { model.resetSimulatedSession() }.accessibilityIdentifier("simResetSession")
                    Text("Synthetic pose and a fixed nearby obstacle in column 3. Movement only changes the virtual scene; no simulated commands move the physical puck.").font(.footnote)
                }
                Text("Range follows the phone's camera plane; horizontal distance uses the floor plane. Arrival means within 0.35 m horizontally and 0.75 m vertically. A highlighted place does not establish a clear route.").font(.footnote)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
