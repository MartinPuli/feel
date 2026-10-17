import SwiftUI
import UIKit

@main
struct LanternApp:App {
    @StateObject private var model=LanternModel()
    @StateObject private var auth=AuthModel.forLaunch()
    @Environment(\.scenePhase) private var scenePhase
    private var uiTesting: Bool { ProcessInfo.processInfo.arguments.contains("--uitesting") }
    var body:some Scene {
        WindowGroup {
            Group {
                if auth.canUseApp {
                    LanternView(model:model, signedInEmail: auth.signedInEmail,
                                onSignOut: auth.signedInEmail == nil ? nil : { auth.signOut() })
                } else {
                    SignInView(auth: auth)
                }
            }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { model.stop(); model.voice.enterBackground() }
                    if phase == .active && auth.canUseApp && !uiTesting {
                        model.voice.enterForeground()
                    }
                }
                .onChange(of: auth.canUseApp) { allowed in
                    if allowed {
                        UIAccessibility.post(notification: .screenChanged, argument: "Signed in.")
                        if !uiTesting { model.voice.enterForeground() }
                    } else {
                        // Signing out stops sensing, tactile output and the microphone.
                        model.stop(); model.voice.enterBackground()
                        UIAccessibility.post(notification: .screenChanged, argument: "Signed out.")
                    }
                }
        }
    }
}
