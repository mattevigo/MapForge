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
        static let recentWorkspaceBookmarks = "recentWorkspaceBookmarks"
        static let appleLanguages = "AppleLanguages"
        static let distanceUnit = "distanceUnit"
    }

    /// Enough to recognise a campaign in the picker, few enough to stay a list and not a
    /// history.
    static let recentsLimit = 20

    private let defaults: UserDefaults

    /// The name of the domain `defaults` writes to: the app's bundle identifier for the real
    /// preferences, the suite's name for a throwaway one.
    private let domain: String

    private let bookmarks: WorkspaceBookmarks

    /// The Mac's region, which decides the Distance Unit until the DM does.
    private let region: Locale

    init(defaults: UserDefaults = .standard,
         domain: String = Bundle.main.bundleIdentifier ?? "com.mattevigo.MapForge",
         bookmarks: WorkspaceBookmarks = .securityScoped,
         region: Locale = .autoupdatingCurrent) {
        self.defaults = defaults
        self.domain = domain
        self.bookmarks = bookmarks
        self.region = region
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
        let name = "MapForgeUITests.\(UUID().uuidString)"
        guard CommandLine.arguments.contains("--test-fresh-preferences"),
              let suite = UserDefaults(suiteName: name)
        else { return DisplayPreferences() }
        return DisplayPreferences(defaults: suite, domain: name)
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
        set {
            let paths = newValue.map(\.path)
            defaults.set(paths, forKey: Key.recentWorkspaces)
            // A bookmark lives exactly as long as its entry, so forgetting and the cap
            // drop it without either having to know it exists.
            recentBookmarks = recentBookmarks.filter { paths.contains($0.key) }
        }
    }

    /// Each recent Workspace's bookmark, keyed by the path `recentWorkspaces` lists it under.
    ///
    /// Beside the list rather than inside it, so the list keeps the shape every earlier
    /// version wrote: a downgrade still finds its recents, and an entry from before bookmarks
    /// is simply a path with nothing beside it.
    private var recentBookmarks: [String: Data] {
        get { defaults.dictionary(forKey: Key.recentWorkspaceBookmarks) as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: Key.recentWorkspaceBookmarks) }
    }

    /// Where a recent Workspace can be reached now, or nil when it cannot.
    ///
    /// Through its bookmark when it has one, which follows a folder the DM has moved. An
    /// entry from before bookmarks has only a path, and is upgraded here, quietly, if a
    /// bookmark can be made from it: always, unsandboxed, for a folder that exists; never,
    /// under the sandbox, which grants nothing for a path the DM has not chosen this launch.
    /// Then it reads as unavailable, and choosing the folder again stores its bookmark.
    func locateWorkspace(_ url: URL) -> URL? {
        let path = Workspace(url: url).url.path
        if let data = recentBookmarks[path] { return try? bookmarks.resolve(data) }
        guard recentWorkspaces.contains(where: { $0.path == path }),
              let data = try? bookmarks.make(url) else { return nil }
        recentBookmarks[path] = data
        return url
    }

    /// The Interface Language chosen on this Mac.
    ///
    /// Stored as the app's own `AppleLanguages`, which is what macOS reads to pick a
    /// localisation at launch — and what System Settings writes when a language is chosen for
    /// MapForge there, so either place reads the other's choice. Read from the app's own
    /// domain only: through `defaults` the key always answers, from the Mac's global language
    /// list or a launch argument, and "System" could never be told apart from a choice.
    var interfaceLanguage: InterfaceLanguage {
        get {
            (defaults.persistentDomain(forName: domain)?[Key.appleLanguages] as? [String])?
                .first.flatMap(InterfaceLanguage.init(code:)) ?? .system
        }
        set {
            if newValue == .system {
                defaults.removeObject(forKey: Key.appleLanguages)
            } else {
                defaults.set([newValue.rawValue], forKey: Key.appleLanguages)
            }
        }
    }

    /// The Distance Unit chosen on this Mac (ADR-0027), or the region's until one is.
    ///
    /// Only a region that measures in US units starts in feet. The choice, once made, is
    /// stored and outranks the region from then on — a DM who moves their Mac to another
    /// country has not changed the table they play at.
    var distanceUnit: DistanceUnit {
        get {
            defaults.string(forKey: Key.distanceUnit).flatMap(DistanceUnit.init(rawValue:))
                ?? (region.measurementSystem == .us ? .feet : .metres)
        }
        set { defaults.set(newValue.rawValue, forKey: Key.distanceUnit) }
    }

    /// Moves a Workspace to the front of the list, deduplicating and capping, and stores a
    /// fresh bookmark to it.
    ///
    /// `url` is the URL the app was handed the folder by — the open panel's, or a resolved
    /// bookmark's — which under the sandbox is the one carrying the grant. A fresh bookmark
    /// on every open is the refresh a stale one needs; when one cannot be made, the last one
    /// stored is kept. `previous` is the entry it was opened from, when that entry's folder
    /// has since moved: the list follows the folder rather than keeping both.
    func noteWorkspaceOpened(_ workspace: Workspace,
                             reachedThrough url: URL? = nil,
                             replacing previous: URL? = nil) {
        let replaced = previous.map(Workspace.init(url:))
        var recents = recentWorkspaces.filter {
            Workspace(url: $0) != workspace && Workspace(url: $0) != replaced
        }
        recents.insert(workspace.url, at: 0)
        recentWorkspaces = Array(recents.prefix(Self.recentsLimit))
        if let data = try? bookmarks.make(url ?? workspace.url) {
            recentBookmarks[workspace.url.path] = data
        }
    }

    /// Forgets a Workspace. The DM's gesture, never the app's: an unreachable folder stays
    /// listed until they say otherwise.
    func forgetWorkspace(_ url: URL) {
        let target = Workspace(url: url)
        recentWorkspaces = recentWorkspaces.filter { Workspace(url: $0) != target }
    }
}
