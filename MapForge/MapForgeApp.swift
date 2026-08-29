import SwiftUI

@main
struct MapForgeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("MapForge Control", id: "control") {
            ControlView()
                .environmentObject(appState)
        }
        .defaultSize(width: 560, height: 480)
    }
}
