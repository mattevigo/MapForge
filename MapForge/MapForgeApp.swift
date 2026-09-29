import SwiftUI

@main
struct MapForgeApp: App {
    @StateObject private var appState = AppState.forThisLaunch

    var body: some Scene {
        Window("MapForge Control", id: "control") {
            ControlView()
                .environmentObject(appState)
                .onAppear {
                    ReturnDeselects.install()
                    ClickDeselects.install()
                    ClickSelectsAll.install()
                    appState.openWorkspaceFromLaunchArgumentsIfPresent()
                    appState.loadMapFromLaunchArgumentsIfPresent()
                }
        }
        // The width is the floor `ControlView` enforces anyway (ADR-0018) — a smaller number
        // here was silently overridden and only made the pair look like a choice. The
        // height is the one this line really decides: 480 opened a letterbox that showed
        // a strip of Map under two toolbars, and the first thing a DM did was drag it
        // taller. Applies to a first launch only; macOS restores the frame after that.
        .defaultSize(width: ControlView.minimumWindowWidth, height: 800)
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
