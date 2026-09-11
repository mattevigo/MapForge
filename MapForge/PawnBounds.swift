import CoreGraphics

/// Keeping a Pawn on the Map: a token dragged past the image edge stops at the edge.
///
/// A Pawn outside the image is meaningless to Visibility, whose four implicit Walls sit at
/// exactly these bounds — the same reason `Stamp` refuses a drop that lands outside it. A
/// drag cannot be refused the way a drop can, so it is clamped instead: the token follows
/// the cursor to the edge and no further, like a figure with its back to the wall.
///
/// Clamped rather than merely warned about because an off-Map Pawn is not just wrong but
/// unreachable. The Control Window mirror clips to the Viewport, so a token pulled into the
/// clipped margin is drawn nowhere the DM can click — it cannot be dragged back, and it
/// cannot be selected in the fog mode to be deleted. The rule applies on load as well, so a
/// file that already holds such a Pawn gets it back the next time the Map opens.
enum PawnBounds {
    /// `point` brought inside the image, or left where it is when it already is. The edges
    /// themselves are on the Map — a character at the very border is the ordinary case.
    ///
    /// An image with no size clamps everything to the origin rather than to a negative
    /// range: `min(max(x, 0), size)` with a zero size is the origin, and that is the only
    /// point such an image has.
    static func clamp(_ point: MapPoint, toImage size: CGSize) -> MapPoint {
        MapPoint(x: min(max(point.x, 0), max(size.width, 0)),
                 y: min(max(point.y, 0), max(size.height, 0)))
    }

    /// Every Pawn in `pawns` brought inside the image. Identity and every other field are
    /// untouched: this moves a token, it does not replace it.
    static func clamped(_ pawns: [Pawn], toImage size: CGSize) -> [Pawn] {
        pawns.map { pawn in
            var moved = pawn
            moved.at = clamp(pawn.at, toImage: size)
            return moved
        }
    }
}
