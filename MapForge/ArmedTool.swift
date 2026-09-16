import Foundation

/// Which armed tool claims a keystroke or a click on the Live View.
///
/// Extracted from `ControlView` because this render layer has **four gesture-composition
/// defects** on record plus a hit-testing one that killed a whole layer, and every one of
/// them was some version of "which handler took that event". None was reachable by a unit
/// test. The gestures themselves still are not — but the predicate deciding them is, so the
/// rule can be stated and held rather than inferred from the order of two `if`s.
///
/// At most one tool is armed at a time. `ControlView` enforces that when arming; these
/// answer what follows from it.
enum ArmedTool {
    /// Whether a left-click on the Map belongs to the Map rather than to the Pawn drag
    /// underneath.
    ///
    /// The false case is the one that matters most: an idle Map has to let the click through,
    /// because dragging a token is the commonest action on this surface and a tap that
    /// swallowed it would break the common case to serve the rare one.
    static func claimsLeftClick(hasArmedAdd: Bool, hasArmedShape: Bool,
                                hasMeasurement: Bool) -> Bool {
        hasArmedAdd || claimsDigits(hasArmedShape: hasArmedShape, hasMeasurement: hasMeasurement)
    }

    /// Whether a typed digit means anything.
    ///
    /// Narrower than `claimsLeftClick` by the armed `Add`: digits type a distance, and only
    /// a Measurement has one. A token being placed has nothing to type into, so the
    /// keystroke must pass through to whatever else wants it.
    static func claimsDigits(hasArmedShape: Bool, hasMeasurement: Bool) -> Bool {
        hasArmedShape || hasMeasurement
    }
}
