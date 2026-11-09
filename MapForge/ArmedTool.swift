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
    /// swallowed it would break the common case to serve the rare one. The Map's tap is now
    /// heard either way — an idle click picks or lets go of the Selection — but it still
    /// only *claims* the click, ahead of the token under it, when this is true.
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

    // MARK: The Selection

    /// What a left-click on the Live View does, once the armed tools have had their say.
    enum Click: Equatable {
        /// Something is armed, and the click is its — ⇧ or not, exactly as before there was
        /// a Selection.
        case armedTool
        /// ⇧-click on a Pawn or a Light Marker: in if it was out, out if it was in.
        case toggle(LiveHitTest)
        /// A plain click on the bare Map: the Selection ends.
        case clearSelection
        case nothing
    }

    /// Whether anything is armed, for the Selection's purposes: Add, a Measurement — armed
    /// or on screen — or the Viewport.
    ///
    /// Wider than `claimsLeftClick` by the Viewport. A click with the rectangle armed is not
    /// claimed by the Map — the rectangle's own drag takes it — but it is not a pick either:
    /// the DM armed the Viewport to move what the table sees, and a click meant for that
    /// must not quietly change what is picked.
    static func isArmed(hasArmedAdd: Bool, hasArmedShape: Bool, hasMeasurement: Bool,
                        isViewportArmed: Bool) -> Bool {
        claimsLeftClick(hasArmedAdd: hasArmedAdd, hasArmedShape: hasArmedShape,
                        hasMeasurement: hasMeasurement) || isViewportArmed
    }

    /// Where a left-click goes. `target` is what `LiveHitTest` finds under it — the Pawn
    /// before the Light Marker it stands on, because the Pawn is drawn above it.
    ///
    /// Picking is ⇧'s alone, and only while nothing is armed. A plain click on a token is
    /// the start of its drag or nothing at all, so it neither picks the token nor drops the
    /// rest; a ⇧-click that misses every token is the DM reaching for one more and missing,
    /// which is no reason to let the others go either. Only a plain click on the bare Map
    /// ends the Selection.
    static func leftClick(isArmed: Bool, isShiftDown: Bool, on target: LiveHitTest?) -> Click {
        if isArmed { return .armedTool }
        switch (isShiftDown, target) {
        case (true, let target?): return .toggle(target)
        case (false, nil): return .clearSelection
        default: return .nothing
        }
    }

    /// What one press of Esc backs out of.
    enum Escape: Equatable {
        case disarmAdd
        case disarmShape
        /// A Measurement is on screen, and the key is its own: it abandons typed digits and
        /// leaves the Measurement — and the Selection — where they are.
        case measurement
        case putViewportAway
        case clearSelection
    }

    /// Esc peels back one layer per press: whatever is armed first, the Selection only once
    /// nothing is. The DM who armed a tool and changed their mind backs out of it without
    /// losing the party they picked; the next Esc lets the party go.
    ///
    /// A Measurement on screen never lets Esc through. Esc already means "abandon the
    /// digits" there and deliberately not "dismiss" (right-click is the one dismissal, the
    /// objection ADR-0005 raised to a second), so a press made for the digits must not reach
    /// further and drop the Selection instead.
    static func escape(hasArmedAdd: Bool, hasArmedShape: Bool, hasMeasurement: Bool,
                       isViewportArmed: Bool) -> Escape {
        if hasArmedAdd { return .disarmAdd }
        if hasArmedShape { return .disarmShape }
        if hasMeasurement { return .measurement }
        if isViewportArmed { return .putViewportAway }
        return .clearSelection
    }
}
