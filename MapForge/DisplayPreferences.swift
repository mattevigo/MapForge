import Foundation

/// What this **machine** knows, as opposed to what a Workspace knows.
///
/// ADR-0012 draws the line: `.mapforge/` travels with the game, `UserDefaults` stays with the
/// Mac. The active Party and the Player Display choice moved into `WorkspaceSettings`, so what
/// is left here is state that cannot travel — which Workspaces this Mac has opened, and, when
/// it is built, Calibration keyed by `DisplayIdentity`. Calibration is a ruler held against a
/// physical screen: the same reading whichever game is open, and meaningless on another Mac.
///
/// A named type rather than `@AppStorage` because the selection policy runs inside
/// `AppState.presentIfPossible()`, which is not a view context.
///
/// The name is a holdover twice over — it holds no per-display setting at all until
/// Calibration arrives. Kept rather than churn every call site, and because Calibration is
/// what it is shaped for.
final class DisplayPreferences {
    private enum Key {
        static let recentWorkspaces = "recentWorkspaces"
    }

    /// Enough to recognise a campaign in the picker, few enough to stay a list and not a
    /// history.
    static let recentsLimit = 20

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The preferences this launch should use: the real ones, or a throwaway suite when
    /// the UI tests are driving.
    ///
    /// A UI test that inherits the developer's remembered Player Display presents onto
    /// whichever screen they last ran a session on — so a Player window appears over a
    /// screen the test never asked for, the Control Window is relocated out from under it,
    /// and every control reports as "not hittable". The suite has to start from a machine
    /// that has never chosen a display, exactly as the unit tests do.
    ///
    /// It now also keeps the suite's *recent Workspaces* empty, which matters more: a test
    /// inheriting the developer's list would open their real game folder and edit their real
    /// roster. `AppState` pairs this with a throwaway Workspace — see
    /// `openWorkspaceFromLaunchArgumentsIfPresent`.
    static var forThisLaunch: DisplayPreferences {
        guard CommandLine.arguments.contains("--test-fresh-preferences"),
              let suite = UserDefaults(suiteName: "MapForgeUITests.\(UUID().uuidString)")
        else { return DisplayPreferences() }
        return DisplayPreferences(defaults: suite)
    }

    /// The Workspaces this Mac has opened, most recent first.
    ///
    /// The bootstrap pointer, and the one thing that cannot live inside a Workspace: it is how
    /// the app finds one at all. Nothing is ever removed automatically — a folder on an
    /// unplugged drive stays listed, so the DM sees an entry marked unavailable rather than a
    /// campaign that has silently vanished.
    var recentWorkspaces: [URL] {
        get {
            (defaults.array(forKey: Key.recentWorkspaces) as? [String] ?? [])
                .map { URL(fileURLWithPath: $0) }
        }
        set { defaults.set(newValue.map(\.path), forKey: Key.recentWorkspaces) }
    }

    /// Moves a Workspace to the front of the list, deduplicating and capping.
    func noteWorkspaceOpened(_ workspace: Workspace) {
        var recents = recentWorkspaces.filter { Workspace(url: $0) != workspace }
        recents.insert(workspace.url, at: 0)
        recentWorkspaces = Array(recents.prefix(Self.recentsLimit))
    }

    /// Forgets a Workspace. The DM's gesture, never the app's: an unreachable folder stays
    /// listed until they say otherwise.
    func forgetWorkspace(_ url: URL) {
        let target = Workspace(url: url)
        recentWorkspaces = recentWorkspaces.filter { Workspace(url: $0) != target }
    }
}
