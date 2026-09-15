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
