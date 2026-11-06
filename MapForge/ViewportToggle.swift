import Foundation

/// Whether the Live View is showing the Viewport rectangle, and what follows from it.
///
/// Moving what the players see used to be a **mode**: a button that took the preview over,
/// with Cancel and Done. It is a toggle now, and the toggle decides whether the rectangle
/// can be *dragged* rather than whether it is *drawn* — the rectangle is always on the Live
/// View. A DM pans the Viewport mid-sentence, between one thing a player says and the next,
/// and a mode with two exits is a thing to get wrong in front of them.
///
/// Losing Cancel is the deliberate cost. There is no "put it back where it was", for the
/// same reason dragging a Pawn has none: this is a live performance action, the table is
/// already watching the result, and an undo would be a second move rather than the erasure
/// of the first.
enum ViewportToggle {
    /// Whether the Viewport rectangle is drawn at all.
    ///
    /// Always, on the Live View, with or without the toggle. The rectangle is how the DM
    /// knows what their players are being shown, and that is not a question they should have
    /// to press a button to answer — it is the question the whole Control Window exists to
    /// answer. The Live View shows the **whole Map**, so there is always somewhere for the
    /// rectangle to sit and always map outside it to see.
    ///
    /// This replaced a cropped mirror that showed only what was inside the Viewport. That
    /// mirror was exact, but it meant the DM could never see what was about to walk into the
    /// room — and a DM who cannot see the rest of their own Map is worse off than one
    /// reading a rectangle.
    static func drawsRectangle(mode: PreviewMode, hasViewport: Bool) -> Bool {
        mode == .normal && hasViewport
    }

    /// Whether the rectangle can be dragged.
    ///
    /// This is what the toggle decides — not whether the rectangle is visible. Idle it is a
    /// **readout**: drawn as an outline, hit-testing off, so the clicks that drag a Pawn or
    /// open the right-click menu pass straight through it. Armed it becomes a **control**.
    ///
    /// Splitting the two is what lets the rectangle be permanent. A permanently draggable
    /// rectangle would sit over the middle of the Map swallowing every gesture aimed at the
    /// Pawns beneath it, which is why it used to be confined to a mode.
    static func isDraggable(isShowingViewport: Bool) -> Bool { isShowingViewport }

    /// Whether a drag that starts on the armed rectangle moves it.
    ///
    /// Not when ⌥ is held: ⌥-drag pans the Magnifier everywhere on the preview, and the
    /// rectangle sits on the preview. Both gestures would otherwise fire at once, and the
    /// DM sliding their own view would slide the table's with it — the one thing panning
    /// the Magnifier must never do. Arming the rectangle used to zoom out to the whole Map,
    /// where there was nothing to pan, which is all that kept the two apart.
    static func dragMovesViewport(isOptionHeld: Bool) -> Bool { !isOptionHeld }

    /// Whether the control is offered at all.
    ///
    /// A Map that fits inside the Viewport has no hidden part: the rectangle would cover the
    /// whole thing and have nowhere to go. Without a Player Display there is no Viewport to
    /// move in the first place.
    ///
    /// Nor under **Map Fit**, however far the Map overflows at True Scale: the players see
    /// the whole Map, so the rectangle covers all of it and there is nothing to pan. The
    /// Viewport's origin is kept, not cleared, so turning Map Fit off offers the toggle again
    /// over the same region the table had.
    static func isAvailable(mapOverflows: Bool, hasDisplay: Bool, isMapFitOn: Bool) -> Bool {
        mapOverflows && hasDisplay && !isMapFitOn
    }

    /// Whether a rectangle already showing should stay showing.
    ///
    /// The same condition, asked as a self-invalidation: unplugging the display, or
    /// declaring a Grid that shrinks the Map below the Viewport, leaves the rectangle over a
    /// preview it no longer describes. It puts itself away instead, the way Solo Sight
    /// clears itself rather than waiting to be noticed.
    static func staysShowing(mapOverflows: Bool, hasDisplay: Bool, isMapFitOn: Bool) -> Bool {
        isAvailable(mapOverflows: mapOverflows, hasDisplay: hasDisplay, isMapFitOn: isMapFitOn)
    }

    /// What the toggle's help says.
    enum Explanation: Equatable {
        /// What the toggle does: show the rectangle, drag it to pan.
        case dragToMoveTheirView
        /// Why it is unavailable: Map Fit shows the whole Map, so there is nothing to pan.
        case nothingToMoveUnderMapFit

        var text: String {
            switch self {
            case .dragToMoveTheirView:
                String(localized: "Show the rectangle the players see, and drag it to move their view.")
            case .nothingToMoveUnderMapFit:
                String(localized: "Map Fit shows the players the whole Map, so there is nothing to move. Turn it off first.")
            }
        }
    }

    /// The help for the toggle: what it does, or — while Map Fit makes it unavailable — why,
    /// rather than leaving the DM to guess at a greyed-out button. Only Map Fit gets its own
    /// sentence: a Map that fits the screen, or no Player Display, are visible from the
    /// Live View itself, and Map Fit is a switch the DM may have forgotten is on.
    static func explanation(isMapFitOn: Bool) -> Explanation {
        isMapFitOn ? .nothingToMoveUnderMapFit : .dragToMoveTheirView
    }
}
