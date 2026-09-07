import SwiftUI

@main
struct MapForgeApp: App {
    @StateObject private var appState = AppState(preferences: .forThisLaunch)

    var body: some Scene {
        Window("MapForge Control", id: "control") {
            ControlView()
                .environmentObject(appState)
                .onAppear { appState.loadMapFromLaunchArgumentsIfPresent() }
        }
        .defaultSize(width: 560, height: 480)
    }
}
