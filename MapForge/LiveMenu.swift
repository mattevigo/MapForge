import Foundation

/// What the Live View's right-click menu offers, for whatever is under the cursor.
///
/// Pure policy beside `LiveHitTest` and `MeasurementControl`, and for a reason found the
/// hard way: the first version of this lived inside the view as a chain of `if`s, and the
/// chain got it wrong. A Pawn under the cursor suppressed the pin section entirely, so a
/// pinned Measurement with a Pawn standing inside it could never be unpinned — the DM's
/// only way out was to move the token off it first.
///
/// The rule that replaces it: the sections are **independent**. The menu is about
/// everything under the cursor, not the topmost thing only. A Pawn contributes its own
/// items; a Measurement under the same point contributes pin or unpin; the shape list is
/// what pin replaces, because picking a shape and pinning one are two answers to the same
/// question and only one can be on the menu at a time.
enum LiveMenu {
    /// Which pin action a Measurement under the cursor offers, if any.
    enum Pin: Equatable {
        case pin
        case unpin(Measurement.ID)
    }

    /// What a Measurement under the cursor is. Mirrors `ControlView.MeasurementHit`, taken
    /// as an input so this stays testable without the view.
    enum MeasurementUnderCursor: Equatable {
        case live
        case pinned(Measurement.ID)
    }

    struct Items: Equatable {
        /// Whether `Edit…` and `Delete` are offered, and for what.
        var editsTarget: Bool
        /// The Pawn `Saving Throw…` and `Ability Check…` are offered for, if any. The same
        /// two Rolls the Pawn's row offers, reached from the token the DM is pointing at.
        var rollsFor: Pawn.ID?
        /// Pin, unpin, or neither.
        var pin: Pin?
        /// Whether the four Measurement Shapes are listed.
        var shapesOffered: Bool
        /// Why measuring is refused, when it is. Shown wherever the DM clicked — a menu that
        /// is merely missing its shapes teaches them nothing, and they are reading it in
        /// front of players.
        var refusal: MeasurementControl.UnavailableReason?
    }

    /// `pawnKind` is the kind of the Pawn `target` names, and nil when it names none.
    static func items(target: LiveHitTest?,
                      pawnKind: PawnKind?,
                      measurement: MeasurementUnderCursor?,
                      availability: MeasurementControl.Availability) -> Items {
        var items = Items(editsTarget: target != nil, rollsFor: nil, pin: nil,
                          shapesOffered: false, refusal: nil)

        if case .pawn(let id) = target, pawnKind?.makesRolls == true {
            items.rollsFor = id
        }

        // Independent of `target`: this is the fix. A Pawn standing inside a pinned circle
        // is both a Pawn and a place where that circle can be unpinned.
        switch measurement {
        case .pinned(let id): items.pin = .unpin(id)
        case .live: items.pin = .pin
        case nil: break
        }

        // The shapes are what pin replaces — start a new Measurement, or settle the one
        // already here. Both on one menu would be two answers to one question.
        if items.pin == nil {
            switch availability {
            case .available: items.shapesOffered = true
            case .disabled(let reason): items.refusal = reason
            }
        }

        return items
    }
}
