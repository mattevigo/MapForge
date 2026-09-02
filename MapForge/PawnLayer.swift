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
    let onMove: (Pawn.ID, MapPoint) -> Void
    /// Called when a drag ends, so the move reaches disk without waiting out the debounce.
    let onCommit: () -> Void

    @State private var dragStart: MapPoint?

    static let coordinateSpace = "pawnLayer"

    var body: some View {
        ZStack(alignment: .topLeading) {
            let side = PlayerPlacement.squareSidePoints(map: map, frame: frame)
            ForEach(pawns) { pawn in
                let p = PlayerPlacement.viewPoint(pawn.at, map: map, frame: frame)
                PawnToken(pawn: pawn, diameter: max(side, 12))
                    .position(x: p.x, y: p.y)
                    .gesture(drag(pawn))
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
                dragStart = nil
                onCommit()
            }
    }
}
