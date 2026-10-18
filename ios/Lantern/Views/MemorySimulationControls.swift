import SwiftUI

struct MemorySimulationControls: View {
    @ObservedObject var model: LanternModel
    var body: some View {
        DisclosureGroup("Simulate saved places") {
            VStack(alignment: .leading, spacing: 12) {
                Text("SIMULATION. No commands are sent to the puck.").font(.caption)
                Button("Start memory simulation") { model.startMemorySimulation() }
                if model.memorySimulation {
                    Text("Use Saved places to remember, then move and recall.").font(.caption)
                    HStack {
                        Button("Move forward 1 meter") { model.moveMemorySimulation(1) }
                        Button("Move back 1 meter") { model.moveMemorySimulation(-1) }
                    }
                    HStack {
                        Button("Turn left 90 degrees") { model.turnMemorySimulation(90) }
                        Button("Turn right 90 degrees") { model.turnMemorySimulation(-90) }
                    }
                    Button(model.simulatedMemoryTracking ? "Lose tracking" : "Recover tracking") { model.toggleMemorySimulationTracking() }
                }
            }.padding(.vertical, 8)
        }
    }
}
