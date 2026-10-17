import SwiftUI

@main
struct LanternApp:App {
    @StateObject private var model=LanternModel()
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            LanternView(model:model)
                .onChange(of:scenePhase) { phase in if phase == .background { model.stop() } }
        }
    }
}
