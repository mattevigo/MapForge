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

    /// `viewPoint` as a transform: image pixels to that surface's points, each axis scaled
    /// on its own. For drawing that has to scale exactly as the artwork does — a Light's
    /// falloff on a frame scaled unevenly (non-square pixels at True Scale) must stay on its
    /// polygon, where a radius scaled by one axis would not.
    ///
    /// A Map with no pixels has no Map space: everything collapses onto the frame's origin,
    /// as `viewPoint` does, so a caller draws nothing rather than dividing by zero. This is
    /// the one place that case is handled; callers need not guard it again.
    static func mapToView(map: MapScale, frame: CGRect) -> CGAffineTransform {
        guard map.imagePixelSize.width > 0, map.imagePixelSize.height > 0 else {
            return CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: frame.minX, ty: frame.minY)
        }
        return CGAffineTransform(a: frame.width / map.imagePixelSize.width, b: 0,
                                 c: 0, d: frame.height / map.imagePixelSize.height,
                                 tx: frame.minX, ty: frame.minY)
    }

    /// The inverse: which Map point a click on that surface landed on.
    ///
    /// The mirror had no absolute inverse until measuring needed one — `PawnLayer` only
    /// ever open-coded a *delta* conversion inside its drag, which cannot answer "where
    /// did this click land". Kept beside the forward direction so the pair stays honest.
    ///
    /// **`frame` and the click must be in the same coordinate space**, and that is the one
    /// thing this function cannot check. In the Control mirror the frame is rebased into
    /// the *clipped* container, so an input modifier attached after `.position()` — which
    /// re-parents the view into the outer GeometryReader — reports clicks in the wrong
    /// space and every result comes back offset by the letterbox margin. The arithmetic
    /// stays correct while the answer is wrong, which is why no test caught it: attach
    /// input above `.position()`, alongside the overlays that draw with the same frame.
    static func mapPoint(_ viewPoint: CGPoint, map: MapScale, frame: CGRect) -> MapPoint {
        guard frame.width > 0, frame.height > 0 else { return MapPoint(x: 0, y: 0) }
        return MapPoint(x: (viewPoint.x - frame.minX) / frame.width * map.imagePixelSize.width,
                        y: (viewPoint.y - frame.minY) / frame.height * map.imagePixelSize.height)
    }

    /// One Grid square in points on that surface — the unit a Pawn token is sized in, so
    /// it reads as occupying its square rather than as a dot of arbitrary size.
    static func squareSidePoints(map: MapScale, frame: CGRect) -> CGFloat {
        guard map.physicalWidthInches > 0 else { return 0 }
        // One square is one inch physical, so squares-wide is the physical width.
        return frame.width / map.physicalWidthInches
    }
}
