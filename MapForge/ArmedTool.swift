import Foundation

/// Which armed tool claims a keystroke or a click on the Live View.
///
/// Extracted from `ControlView` because this render layer has **four gesture-composition
/// defects** on record plus a hit-testing one that killed a whole layer, and every one of
/// them was some version of "which handler took that event". None was reachable by a unit
/// test. The gestures themselves still are not — but the predicate deciding them is, so the
/// rule can be stated and held rather than inferred from the order of two `if`s.
///
/// At most one tool is armed at a time. `ControlView` enforces that when arming; `State`
/// answers what follows from it.
enum ArmedTool {
    /// What is armed on the Live View, gathered in one place — `ControlView.armed` — and
    /// asked every question about clicks and Esc from there, so the flags never travel
    /// apart and no two callers can assemble them differently.
    struct State: Equatable {
        /// `Add` is waiting for the click that says where.
        var hasArmedAdd = false
        /// A Measurement Shape is waiting for the click that places its Origin.
        var hasArmedShape = false
        /// A Measurement is on screen — the one being taken, not a Pinned one.
        var hasMeasurement = false
        /// Digits have been typed towards the Measurement's distance and not yet settled
        /// with Return: the one thing about a Measurement that Esc backs out of.
        var hasTypedDigits = false
        /// The Viewport rectangle is on the Map, its drag waiting.
        var isViewportArmed = false

        /// Whether a left-click on the Map belongs to the Map rather than to the Pawn drag
        /// underneath.
        ///
        /// The false case is the one that matters most: an idle Map has to let the click
        /// through, because dragging a token is the commonest action on this surface and a
        /// tap that swallowed it would break the common case to serve the rare one. The Map's
        /// tap is heard either way — an idle click picks or lets go of the Selection — but it
        /// only *claims* the click, ahead of the token under it, when this is true.
        var claimsLeftClick: Bool { hasArmedAdd || claimsDigits }

        /// Whether a typed digit means anything.
        ///
        /// Narrower than `claimsLeftClick` by the armed `Add`: digits type a distance, and
        /// only a Measurement has one. A token being placed has nothing to type into, so the
        /// keystroke must pass through to whatever else wants it.
        var claimsDigits: Bool { hasArmedShape || hasMeasurement }

        /// Whether anything is armed, for the Selection's purposes: Add, a Measurement —
        /// armed or on screen — or the Viewport.
        ///
        /// Wider than `claimsLeftClick` by the Viewport. A click with the rectangle armed is
        /// not claimed by the Map — the rectangle's own drag takes it — but it is not a pick
        /// either: the DM armed the Viewport to move what the table sees, and a click meant
        /// for that must not quietly change what is picked.
        var isArmed: Bool { claimsLeftClick || isViewportArmed }

        /// Where a left-click goes. `target` is the token under it as drawn,
        /// `PawnLayer.token(under:)` — the area each token's drag answers to, and the Pawn
        /// before the Light Marker it stands on, because the Pawn is drawn above it.
        ///
        /// Picking is ⇧'s alone, and only while nothing is armed. A plain click on a token is
        /// the start of its drag or nothing at all, so it neither picks the token nor drops
        /// the rest; a ⇧-click that misses every token is the DM reaching for one more and
        /// missing, which is no reason to let the others go either. Only a plain click on the
        /// bare Map ends the Selection.
        ///
        /// And none of this is a click at all when the release ends a drag (`endsDrag`, from
        /// `LiveViewPress`) — a rectangle, a Selection carried, any drag. The Map's tap is
        /// heard over the whole Live View, and nothing promises that SwiftUI fails it on
        /// movement; were it to fire on that mouse-up, a plain "click" on the bare Map would
        /// empty what the rectangle just picked, a ⇧-"click" would toggle a carried Pawn
        /// back out, and an armed tool would take a click the DM never made.
        func leftClick(isShiftDown: Bool, on target: LiveHitTest?,
                       endsDrag: Bool = false) -> Click {
            if endsDrag { return .nothing }
            if isArmed { return .armedTool }
            switch (isShiftDown, target) {
            case (true, let target?): return .toggle(target)
            case (false, nil): return .clearSelection
            default: return .nothing
            }
        }

        /// What this press of Esc backs out of. Esc peels back one layer per press: whatever
        /// is armed first, the Selection only once nothing is. The DM who armed a tool and
        /// changed their mind backs out of it without losing the Selection they picked; the
        /// next Esc lets it go.
        ///
        /// A Measurement on screen holds Esc only while digits are typed into it. Esc means
        /// "abandon the digits" there and deliberately not "dismiss" (right-click is the one
        /// dismissal, the objection ADR-0005 raised to a second), so a press made for the
        /// digits must not reach further and drop the Selection instead. With nothing typed
        /// the Measurement has nothing for Esc to undo, and the press goes on: otherwise a
        /// Measurement left on screen would keep the Selection from ever being let go. A
        /// Pinned Measurement is never in this at all — it is parked, not being taken.
        var escape: Escape {
            if hasArmedAdd { return .disarmAdd }
            if hasArmedShape { return .disarmShape }
            if hasMeasurement && hasTypedDigits { return .abandonDigits }
            if isViewportArmed { return .putViewportAway }
            return .clearSelection
        }
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

    /// What one press of Esc backs out of.
    enum Escape: Equatable {
        case disarmAdd
        case disarmShape
        /// Digits are typed towards the Measurement on screen, and the key is theirs: it
        /// abandons them and leaves the Measurement — and the Selection — where they are.
        case abandonDigits
        case putViewportAway
        case clearSelection
    }
}
