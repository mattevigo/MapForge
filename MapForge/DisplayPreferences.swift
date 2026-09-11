import Foundation

/// App-level settings. The app's first persistence of any kind.
///
/// A named type rather than `@AppStorage` because the selection policy runs inside
/// `AppState.presentIfPossible()`, which is not a view context. Shaped so issue 04's
/// Calibration factor joins it keyed by the same `DisplayIdentity` — not built here.
///
/// It began as per-display settings and now also remembers the active Party. The name is
/// kept rather than churn every call site: what these have in common is that they are small
/// choices a DM can remake with one click, which is exactly what distinguishes them from the
/// authored data `FogStore` and `PartyStore` guard.
final class DisplayPreferences {
    private enum Key {
        static let playerDisplayUUID = "playerDisplayUUID"
        static let playerDisplayName = "playerDisplayName"
        static let activePartyID = "activePartyID"
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

    /// The Party the Control Window offers, remembered across launches — a DM runs one
    /// campaign per sitting, so the choice is made rarely and should not be remade daily.
    ///
    /// An ID rather than the Party itself: the roster lives in `PartyStore`, and duplicating
    /// it here would give the app two answers to "what is this Party called". An ID naming a
    /// Party that no longer exists resolves to nil at the point of use, not here — deleting a
    /// Party must not have to reach into preferences to stay consistent.
    var activePartyID: UUID? {
        get {
            guard let string = defaults.string(forKey: Key.activePartyID) else { return nil }
            return UUID(uuidString: string)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.activePartyID) }
    }
}
