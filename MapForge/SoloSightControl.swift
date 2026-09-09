import Foundation

/// Whether the Solo Sight control is offered for a Pawn, and why not when it is not.
///
/// Pure, and separate from `ControlView`, for the reason `ControlView.fogInspectorRowHeight`
/// is: a rule the DM meets mid-session should be provable without driving a window. Every unavailable
/// state carries a reason — a control that is merely inert teaches the DM nothing, and they
/// are reading it in front of players.
enum SoloSightControl {
    enum UnavailableReason: CaseIterable {
        /// The eye beats lighting, and Solo Sight does not silently override it (ADR 0004).
        case pawnIsHidden
        /// The mode\'s whole effect is the fog shrinking. With no fog, nothing shrinks.
        case fogOverlayOff
        /// Sight radii are in Grid squares, so without a Grid there is no Visibility at all.
        case noGrid

        var explanation: String {
            switch self {
            case .pawnIsHidden:
                return "Hidden from players. Show it to see the Map through its eyes."
            case .fogOverlayOff:
                return "Solo Sight needs the Fog Overlay on — there is no darkness to shrink."
            case .noGrid:
                return "Declare the Grid first: sight is measured in squares."
            }
        }
    }

    enum Availability: Equatable {
        case available
        case disabled(UnavailableReason)
        /// Not drawn at all — this Pawn could never be isolated.
        case absent
    }

    /// A Creature or a Treasure emits no Light, so isolating one would show a black Map.
    /// That is a missing control rather than a disabled one: there is nothing the DM could
    /// change about *this* Pawn to make it meaningful, unlike the three disabled states.
    static func availability(for pawn: Pawn, isFogOverlayOn: Bool,
                             hasDeclaredGrid: Bool) -> Availability {
        if pawn.isDiscovered { return .absent }
        // Ordered by what the DM can act on: the reason belonging to the row they clicked
        // comes before the two that are about the Map as a whole.
        if pawn.isHidden { return .disabled(.pawnIsHidden) }
        if !isFogOverlayOn { return .disabled(.fogOverlayOff) }
        if !hasDeclaredGrid { return .disabled(.noGrid) }
        return .available
    }
}
