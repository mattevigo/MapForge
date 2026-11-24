import CoreGraphics

/// Where a Health Bar sits on the Player Display, and how big it is (ADR-0036).
///
/// Kept apart from `HealthBar`, which is the arithmetic of hit points and nothing else, and
/// from the view that paints it, so the promises the table relies on are numbers a test can
/// reach rather than modifiers in a view body.
extension HealthBar {
    /// The bar's rectangle for a token centred at `tokenCentre`, in the drawing surface's
    /// own points.
    ///
    /// `squareSide` is ONE Grid square, as `PawnToken` takes it, and `squaresAcross` the
    /// Pawn's footprint: the bar is as wide as the token, so a Big Pawn's spans its two
    /// squares and the table reads the strip as belonging to the figure above it.
    ///
    /// Its thickness is a fraction of ONE square, never of the footprint: a Big Pawn's bar is
    /// longer, not fatter, for the reason a Big Pawn's label is not bigger (`PawnToken`).
    static func frame(below tokenCentre: CGPoint, squareSide: CGFloat,
                      squaresAcross: CGFloat) -> CGRect {
        let width = squareSide * squaresAcross
        let height = max(squareSide * heightPerSquare, minimumHeight)
        // The token's footprint is `width` tall as well as wide — a disc or a square.
        let top = tokenCentre.y + width / 2 + gap
        return CGRect(x: tokenCentre.x - width / 2, y: top, width: width, height: height)
    }

    /// The space between the token's lower edge and the bar, in points. Enough that the
    /// strip reads as its own thing rather than a smudge on the disc's outline; fixed rather
    /// than scaled, because it is a seam between two shapes, not part of either.
    static let gap: CGFloat = 2

    /// The bar's thickness as a share of one square: a strip under the figure, not a second
    /// token beside it.
    static let heightPerSquare: CGFloat = 1.0 / 8

    /// The thinnest the bar is ever drawn, in points. Map Fit on a large Map shrinks a
    /// square to the Player Display's 12 pt floor, where an eighth is a hairline whose
    /// colour nobody across the table can name — and the colour is the whole message.
    static let minimumHeight: CGFloat = 4
}
