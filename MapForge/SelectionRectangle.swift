import CoreGraphics

/// The selection rectangle: with nothing armed, a primary drag on the bare Map picks the
/// Pawns it covers (`CONTEXT.md`, **Selection**).
///
/// Pure rules, kept apart from `ControlView` so they can be tested without a gesture. The
/// rectangle itself lives in **Map space** — image pixels, where `Pawn.at` is — rather than
/// in the Control Window's points. A rectangle in points would have to be re-read against
/// whatever the Magnifier was doing at release; one in pixels means the same Pawns whether
/// the DM drew it zoomed in on one room or across the whole Map.
enum SelectionRectangle {
    /// The Pawns whose **centre** lies inside `rect`, edge included, in document order.
    ///
    /// The centre and not the token: a Big Pawn whose footprint reaches into the rectangle
    /// but who stands outside it is not picked. "Where it stands" is one point, the same for
    /// every Kind and every size, so the DM never has to judge how much of an ogre is enough.
    ///
    /// Pawns only — the signature takes no Lights, so none can come back. A Light joins the
    /// Selection by its own ⇧-click and nothing else; a torch on the floor of the room the
    /// DM sweeps the players' Pawns out of is not something they meant to carry along.
    static func pawnIDs(centredIn rect: CGRect, among pawns: [Pawn]) -> [Pawn.ID] {
        // Not `CGRect.contains`, which leaves out the max edges: a Pawn whose centre the
        // DM drew the edge through is, as far as anyone can see, inside.
        let rect = rect.standardized
        return pawns.filter { pawn in
            (rect.minX...rect.maxX).contains(pawn.at.x)
                && (rect.minY...rect.maxY).contains(pawn.at.y)
        }.map(\.id)
    }

    /// The rectangle between where the drag began and where the pointer is now, both in
    /// Map space, whichever way the DM dragged.
    ///
    /// Both corners are kept as Map points rather than view points, so a wheel-zoom in the
    /// middle of the drag leaves the corner it began at under the Map spot it was pressed on,
    /// rather than sliding across the artwork with the Magnifier.
    static func mapRect(from start: MapPoint, to end: MapPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Whether a primary drag on the Live View draws a rectangle, decided once, as it starts.
    ///
    /// Only with nothing armed (`ArmedTool.State.isArmed`: Add, a Measurement, the Viewport) —
    /// with any of them the drag is what it was before there was a rectangle. Never with ⌥,
    /// which pans the Magnifier. And never from a token: a drag that starts on a Pawn or a
    /// Light Marker is that token's own, and moves it. The middle button needs no rule
    /// here — SwiftUI's `DragGesture` never sees it (`MiddleMouseDragModifier`).
    ///
    /// Decided at the start and not re-asked: a drag that began on a token and crossed onto
    /// the bare Map is still dragging that token.
    static func begins(isArmed: Bool, isOptionDown: Bool, startsOn token: LiveHitTest?) -> Bool {
        !isArmed && !isOptionDown && token == nil
    }

    /// One primary drag on the Live View, as far as the rectangle is concerned. Held by
    /// `ControlView` for the length of the drag, then dropped.
    enum Drag: Equatable {
        /// The drag was not the rectangle's (`begins` said no), and stays not its own to its
        /// end — however far it wanders onto the bare Map.
        case declined
        /// Between the Map point the drag began on and the one under the pointer now.
        /// `adding` is ⇧ as the drag began; ⇧ at release adds as well, so the DM need not
        /// have pressed it first.
        case drawing(from: MapPoint, to: MapPoint, adding: Bool)

        /// The rectangle in Map space while one is being drawn, nil otherwise.
        var mapRect: CGRect? {
            guard case .drawing(let from, let to, _) = self else { return nil }
            return SelectionRectangle.mapRect(from: from, to: to)
        }
    }
}
