import Foundation

/// Whether the Live View is showing the Viewport rectangle, and what follows from it.
///
/// Moving what the players see used to be a **mode**: a button that took the preview over,
/// with Cancel and Done. It is a toggle now — one button to show the rectangle, the same
/// button to put it away. A DM pans the Viewport mid-sentence, between one thing a player
/// says and the next, and a mode with two exits is a thing to get wrong in front of them.
///
/// Losing Cancel is the deliberate cost. There is no "put it back where it was", for the
/// same reason dragging a Pawn has none: this is a live performance action, the table is
/// already watching the result, and an undo would be a second move rather than the erasure
/// of the first.
enum ViewportToggle {
    /// Whether the preview pulls back to show the whole Map.
    ///
    /// It has to. The Live View's preview is the mirror — exactly what the Player Display
    /// shows — so a Viewport rectangle drawn on it would fill the preview edge to edge, with
    /// nothing outside it to drag toward. Showing the rectangle means showing the Map around
    /// it, which is the view the old mode gave and the only one the drag makes sense in.
    static func showsWholeMap(isShowingViewport: Bool, mode: PreviewMode) -> Bool {
        mode == .normal && isShowingViewport
    }

    /// Whether showing the rectangle should put the Magnifier away.
    ///
    /// It should. The two act on the same preview and only one is on screen at a time: with
    /// the whole Map showing there is no mirror left to magnify, so a Magnifier left armed
    /// underneath would keep its "Zoomed" affordance up over a view it is not affecting —
    /// and the DM would come back from panning to a magnification they had forgotten about.
    static func endsMagnifier(isShowingViewport: Bool) -> Bool { isShowingViewport }

    /// Whether the control is offered at all.
    ///
    /// A Map that fits inside the Viewport has no hidden part: the rectangle would cover the
    /// whole thing and have nowhere to go. Without a Player Display there is no Viewport to
    /// move in the first place.
    static func isAvailable(mapOverflows: Bool, hasDisplay: Bool) -> Bool {
        mapOverflows && hasDisplay
    }

    /// Whether a rectangle already showing should stay showing.
    ///
    /// The same condition, asked as a self-invalidation: unplugging the display, or
    /// declaring a Grid that shrinks the Map below the Viewport, leaves the rectangle over a
    /// preview it no longer describes. It puts itself away instead, the way Solo Sight
    /// clears itself rather than waiting to be noticed.
    static func staysShowing(mapOverflows: Bool, hasDisplay: Bool) -> Bool {
        isAvailable(mapOverflows: mapOverflows, hasDisplay: hasDisplay)
    }
}
