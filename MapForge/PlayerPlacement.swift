import CoreGraphics

/// Placing Map-space things — Pawns, and later the Fog Overlay — onto a surface that is
/// already drawing the Map at some frame.
///
/// Pawns are stored in image pixels while the Map is drawn in points, so everything that
/// sits *on* the Map needs this one conversion. Pure geometry beside `ScaleMath` and
/// `ViewportMath`, because a token that used the wrong mapping would land somewhere
/// plausible but wrong — worse than obviously broken.
enum PlayerPlacement {
    /// Where a Map point lands, given the frame the Map image occupies.
    ///
    /// Works for the Player Display and the Control Window mirror alike: both draw the
    /// whole Map into a frame and let it overflow, so the frame carries the pan.
    static func viewPoint(_ point: MapPoint, map: MapScale, frame: CGRect) -> CGPoint {
        guard map.imagePixelSize.width > 0, map.imagePixelSize.height > 0 else {
            return CGPoint(x: frame.minX, y: frame.minY)
        }
        return CGPoint(x: frame.minX + point.x / map.imagePixelSize.width * frame.width,
                       y: frame.minY + point.y / map.imagePixelSize.height * frame.height)
    }

    /// One Grid square in points on that surface — the unit a Pawn token is sized in, so
    /// it reads as occupying its square rather than as a dot of arbitrary size.
    static func squareSidePoints(map: MapScale, frame: CGRect) -> CGFloat {
        guard map.physicalWidthInches > 0 else { return 0 }
        // One square is one inch physical, so squares-wide is the physical width.
        return frame.width / map.physicalWidthInches
    }
}
