import SwiftUI

/// A Light as players and the DM both see it: a small warm dot where the source stands.
///
/// One view shared by every surface that draws one, for the reason `PawnToken` is shared —
/// the DM points at the flame on their screen and the players must be looking at the same
/// flame. It is deliberately *not* the fog editing mode's marker: that one is a draggable
/// authoring handle with a selection ring, sized for hitting with a mouse, and unifying the
/// two is how an editing control ends up on the table's screen.
struct LightMarker: View {
    /// The side of ONE Grid square on whichever surface is drawing it, so the marker scales
    /// with the Map rather than with the window — the same contract `PawnToken` takes, and
    /// for the same reason.
    let squareSide: CGFloat

    /// Half a square, floored at 9pt. Smaller than a token on purpose — a Light is
    /// scenery, and a marker that matched a Pawn for size would be read as a game piece —
    /// but a third of a square, tried first, was a speck beside a token and easy to miss
    /// when scanning a Map for the source of a lit region, which is the whole job.
    ///
    /// Floored like `PawnToken`'s side is, and for the same reason: a Map with no declared
    /// physical size yields a zero-width square, and an invisible marker is worse than an
    /// approximately-sized one.
    private var diameter: CGFloat { Self.diameter(squareSide: squareSide) }

    /// The dot's width on a surface whose square is `squareSide` — for whatever is drawn
    /// around it, as the Control Window's Selection ring is.
    static func diameter(squareSide: CGFloat) -> CGFloat { max(squareSide / 2, 9) }

    var body: some View {
        Circle()
            .fill(
                // Warm and centre-bright, so it reads as a source rather than as another
                // token. The gradient does the work a flame icon would, at a size where an
                // icon would be unreadable anyway.
                RadialGradient(colors: [Color(white: 1, opacity: 0.95),
                                        Color.yellow.opacity(0.85),
                                        Color.orange.opacity(0.5)],
                               center: .center, startRadius: 0, endRadius: diameter / 2)
            )
            .overlay(
                // A hairline so the dot survives on pale artwork, where a yellow glow on a
                // sandstone floor would otherwise vanish.
                Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5)
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }
}
