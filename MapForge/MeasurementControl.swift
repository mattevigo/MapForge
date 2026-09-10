import CoreGraphics
import Foundation

/// Whether measuring is offered, and what a right-click on the Map means.
///
/// Pure, and separate from `ControlView`, for the reason `SoloSightControl` is: a rule the
/// DM meets mid-session should be provable without driving a window. Every unavailable
/// state carries a reason — a control that is merely inert teaches the DM nothing, and
/// they are reading it in front of players.
enum MeasurementControl {
    enum UnavailableReason: CaseIterable {
        /// Distances are in Grid squares, so without a Grid there is no metres conversion
        /// and the readout would be a confident wrong number (ADR 0003).
        case noGrid
        case noMap

        var explanation: String {
            switch self {
            case .noGrid:
                return "Declare the Grid first: distances are measured in squares."
            case .noMap:
                return "Open a Map to measure on."
            }
        }
    }

    enum Availability: Equatable {
        case available
        case disabled(UnavailableReason)
    }

    /// Both the right-click and the shape picker read this, rather than each testing
    /// `hasDeclaredGrid` for itself and drifting.
    static func availability(hasDeclaredGrid: Bool, hasMap: Bool) -> Availability {
        if !hasMap { return .disabled(.noMap) }
        if !hasDeclaredGrid { return .disabled(.noGrid) }
        return .available
    }

    /// Where a Measurement started by right-clicking at `point` is anchored.
    ///
    /// A click on a Pawn anchors to the Pawn — spec 5, so the DM does not have to find the
    /// exact pixel under a token they can already see, and so the Measurement follows it.
    /// Anything else anchors to the point itself.
    ///
    /// Hit-testing lives here rather than as a gesture on the token: `PawnLayer` already
    /// owns a drag, child gestures beat ancestor gestures, and this render layer has
    /// produced four defects from gesture composition (`ControlView`).
    static func origin(forClickAt point: MapPoint, pawns: [Pawn],
                       pixelsPerSquare: CGFloat) -> MeasurementOrigin {
        let hit = pawns
            .map { pawn -> (Pawn, CGFloat) in
                (pawn, hypot(pawn.at.x - point.x, pawn.at.y - point.y))
            }
            // Half the token's own footprint, so a Big Pawn is hit across its whole 2x2.
            .filter { $0.1 <= $0.0.squaresAcross * pixelsPerSquare / 2 }
            .min { $0.1 < $1.1 }

        if let hit { return .pawn(hit.0.id) }
        return .point(point)
    }

    /// Which way an aimed shape points: from the Origin towards the cursor.
    ///
    /// Falls back to zero when the cursor sits on the Origin, rather than letting the
    /// shape spin as the mouse crosses its own apex.
    static func direction(from origin: MapPoint, to cursor: MapPoint) -> CGFloat {
        let dx = cursor.x - origin.x, dy = cursor.y - origin.y
        guard hypot(dx, dy) > 1e-9 else { return 0 }
        return atan2(dy, dx)
    }
}
