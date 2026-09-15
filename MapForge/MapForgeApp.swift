import SwiftUI

@main
struct MapForgeApp: App {
    @StateObject private var appState = AppState.forThisLaunch

    var body: some Scene {
        Window("MapForge Control", id: "control") {
            ControlView()
                .environmentObject(appState)
                .onAppear {
                    appState.openWorkspaceFromLaunchArgumentsIfPresent()
                    appState.loadMapFromLaunchArgumentsIfPresent()
                }
        }
        .defaultSize(width: 560, height: 480)
    }
}

extension AppState {
    /// The app's composition root.
    ///
    /// This is the **only** place the real migration is wired in. It deletes the DM's roster
    /// from a real path in Application Support, so it is supplied explicitly here and nowhere
    /// else — an `AppState` built anywhere else, in a test or a preview, gets no migration and
    /// cannot touch that file. See `WorkspaceMigration.legacyURL` for why that is written down
    /// rather than assumed.
    @MainActor
    static var forThisLaunch: AppState {
        let preferences = DisplayPreferences.forThisLaunch
        return AppState(preferences: preferences,
                        migration: .forThisMac(preferences: preferences))
    }
}
