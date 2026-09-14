import SwiftUI

/// Pawns on the Control Window's normal preview, draggable.
///
/// Separate from `FogOverlay` because this is the *live* half of issue 04: the party moves
/// during play, not during prep, so a DM must be able to slide a token without entering an
/// editing mode first. Fog authoring stays behind the mode; moving tokens does not.
struct PawnLayer: View {
    let map: MapScale
    /// Where the Map image sits in this container — the mirror's frame, which already
    /// carries the Viewport pan.
    let frame: CGRect
    let pawns: [Pawn]
    /// The Map's own Lights, drawn as markers beneath the tokens. Not a Pawn's light: a
    /// Pawn already draws a token at exactly that point.
    let lights: [Light]
    /// Whether each Pawn is currently invisible to players, so the DM can see at a glance
    /// what the table can and cannot. Never used to hide one here: the Control Window
    /// exists so the DM sees everything.
    let isDimmed: (Pawn) -> Bool
    /// The same question for a Light Marker, and the same answer: faded, never absent.
    let isLightDimmed: (Light) -> Bool
    let onMove: (Pawn.ID, MapPoint) -> Void
    /// Called when a drag ends, so the move reaches disk without waiting out the debounce.
    ///
    /// Carries where the drag *began*, which only this view knows: `onMove` has already
    /// overwritten the Pawn's position many times by now, so the Combat Log's "from" has
    /// to come from the gesture rather than the document. A drag that ends where it
    /// started passes the same point twice and records nothing.
    let onCommit: (Pawn.ID, MapPoint) -> Void

    @State private var dragStart: MapPoint?

    static let coordinateSpace = "pawnLayer"

    var body: some View {
        ZStack(alignment: .topLeading) {
            let side = PlayerPlacement.squareSidePoints(map: map, frame: frame)
            // Under the tokens: a Pawn standing on a brazier must not be hidden by it.
            ForEach(lights) { light in
                let p = PlayerPlacement.viewPoint(light.at, map: map, frame: frame)
                LightMarker(squareSide: max(side, 12))
                    // The same 0.4 a Pawn the players cannot see gets, because it is the
                    // same statement: the table cannot see this.
                    .opacity(isLightDimmed(light) ? 0.4 : 1)
                    .position(x: p.x, y: p.y)
            }
            ForEach(pawns) { pawn in
                let p = PlayerPlacement.viewPoint(pawn.at, map: map, frame: frame)
                PawnToken(pawn: pawn, squareSide: max(side, 12))
                    .opacity(isDimmed(pawn) ? 0.4 : 1)
                    .position(x: p.x, y: p.y)
                    .gesture(drag(pawn))
                    // A test hook, and the only way to ask "is this Pawn on the preview":
                    // the token is a ZStack that publishes as one element, so its label
                    // Text is not separately queryable. Without this, the preview drawing
                    // nothing at all is indistinguishable from it drawing everything —
                    // which is how `.scratch/pawns-not-drawn/` survived a whole feature.
                    .accessibilityIdentifier("pawn-token-\(pawn.label)")
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
    }

    /// Measured in this layer's own named space, never the token's — a token placed with
    /// `.position()` moves as it is dragged, and measuring against it makes the gesture a
    /// feedback loop. That is the bug issue 09 cost a round of work on.
    private func drag(_ pawn: Pawn) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if dragStart == nil { dragStart = pawn.at }
                guard let start = dragStart, frame.width > 0, frame.height > 0 else { return }
                // Container points back into image pixels: the inverse of PlayerPlacement.
                let dx = value.translation.width / frame.width * map.imagePixelSize.width
                let dy = value.translation.height / frame.height * map.imagePixelSize.height
                onMove(pawn.id, MapPoint(x: start.x + dx, y: start.y + dy))
            }
            .onEnded { _ in
                // `dragStart` is where the Pawn stood before any of this drag's updates,
                // which is the only place that value still exists.
                let origin = dragStart ?? pawn.at
                dragStart = nil
                onCommit(pawn.id, origin)
            }
    }
}
