import Foundation

/// When the **Map Fit** toggle can be pressed, and when Map Fit has to put itself away.
///
/// Map Fit fits the Map to the Player Display, so it means nothing without one. The
/// toggle is unavailable then — and a DM who unplugs the screen while fitted must not be left
/// with Map Fit on behind a toggle they cannot press. It switches itself off instead, the way
/// an armed Viewport rectangle puts itself away (`ViewportToggle.staysShowing`) and Solo
/// Sight clears itself rather than waiting to be noticed. The next Player Display starts at
/// True Scale, which is where every launch starts too.
///
/// Pure policy beside `ViewportToggle`, so the rule is stated once where a test can ask it,
/// and `AppState` applies it wherever the Player Display is resolved.
enum MapFitToggle {
    /// Whether the DM can switch Map Fit on or off: only with a Player Display to fit to.
    static func isAvailable(hasDisplay: Bool) -> Bool { hasDisplay }

    /// Whether Map Fit, already on, stays on. Not once the Player Display has gone.
    static func staysOn(hasDisplay: Bool) -> Bool {
        isAvailable(hasDisplay: hasDisplay)
    }
}
