import Foundation

/// App-level, per-display settings. The app's first persistence of any kind.
///
/// A named type rather than `@AppStorage` because the selection policy runs inside
/// `AppState.presentIfPossible()`, which is not a view context. Shaped so issue 04's
/// Calibration factor joins it keyed by the same `DisplayIdentity` — not built here.
final class DisplayPreferences {
    private enum Key {
        static let playerDisplayUUID = "playerDisplayUUID"
        static let playerDisplayName = "playerDisplayName"
    }

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
    static var forThisLaunch: DisplayPreferences {
        guard CommandLine.arguments.contains("--test-fresh-preferences"),
              let suite = UserDefaults(suiteName: "MapForgeUITests.\(UUID().uuidString)")
        else { return DisplayPreferences() }
        return DisplayPreferences(defaults: suite)
    }

    /// The Player Display chosen in an earlier session, if any. The name is a label
    /// only — matching is by UUID, so a renamed display still resolves.
    var rememberedPlayerDisplay: DisplayIdentity? {
        get {
            guard let uuid = defaults.string(forKey: Key.playerDisplayUUID) else { return nil }
            return DisplayIdentity(uuid: uuid,
                                   name: defaults.string(forKey: Key.playerDisplayName) ?? "")
        }
        set {
            defaults.set(newValue?.uuid, forKey: Key.playerDisplayUUID)
            defaults.set(newValue?.name, forKey: Key.playerDisplayName)
        }
    }
}
