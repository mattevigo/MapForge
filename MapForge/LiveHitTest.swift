import CoreGraphics

/// What sits under a point on the Map in the Live View: a Pawn, a Light, or nothing.
///
/// Pure policy beside `SoloSightControl` and `MeasurementControl`, for the same reason: the
/// question "what did the DM just click on" decides which menu they are shown mid-session,
/// and a rule that answers it should be provable without driving a window. The right-click
/// menu, and anything else that needs to act on what is under the cursor, asks here.
///
/// The **order** is the load-bearing part. A Pawn *is* a Light (`Pawn.light`), so a Pawn's
/// token and a Light Marker can occupy the same pixel; the DM means the Pawn, which carries
/// the label, the colour and the Kind. Measurements come after both — they are drawn under
/// the tokens, and a Measurement anchored to a Pawn starts at that Pawn's centre, so a
/// cursor there is over the anchor rather than over the shape. `ControlView` asks this
/// first and falls back to `measurementUnderCursor`.
enum LiveHitTest: Equatable {
    case pawn(Pawn.ID)
    case light(Light.ID)

    /// What is under `point`, in image pixels.
    ///
    /// `gridPixels` is the Grid square's side in image pixels, or nil when no Grid has been
    /// declared — a Map can hold Pawns without one, because `Add` deliberately does not
    /// require a Grid (a Light without one is inert, not wrong, so refusing would be
    /// stricter than the mode this replaces). Tokens are then drawn at a fixed size and the
    /// hit area follows them rather than disappearing.
    static func hit(at point: MapPoint, pawns: [Pawn], lights: [Light],
                    gridPixels: CGFloat?) -> LiveHitTest? {
        let square = gridPixels ?? fallbackSquarePixels

        // Reversed: the last Pawn drawn is the one on top, and the one the DM can see is
        // the one they mean.
        for pawn in pawns.reversed() {
            // `squaresAcross` is 2 for a Big Pawn, so an ogre is hit across its whole 2×2
            // footprint rather than only the square at its centre.
            let reach = square * pawn.squaresAcross / 2
            if abs(point.x - pawn.at.x) <= reach && abs(point.y - pawn.at.y) <= reach {
                return .pawn(pawn.id)
            }
        }

        for light in lights.reversed() {
            let reach = square * lightMarkerSquares / 2
            if abs(point.x - light.at.x) <= reach && abs(point.y - light.at.y) <= reach {
                return .light(light.id)
            }
        }

        return nil
    }

    /// A Light Marker is drawn smaller than a token — it marks a point rather than occupying
    /// a square — but not so small that it cannot be clicked. Half a square is the
    /// compromise: comfortably bigger than the dot, and small enough that a Light beside a
    /// Pawn is still reachable.
    private static let lightMarkerSquares: CGFloat = 0.5

    /// What a square is worth when no Grid has been declared. Matches the floor `PawnLayer`
    /// and `FogOverlay` draw tokens at, so the hit area is the size of the thing on screen.
    private static let fallbackSquarePixels: CGFloat = 12
}
