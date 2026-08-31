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
