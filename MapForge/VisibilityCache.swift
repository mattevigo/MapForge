import CoreGraphics
import Foundation

/// Holds the computed Visibility for one Map, recomputing only when its inputs change.
///
/// The sweep is cheap for the tens of Walls a hand-authored Map carries, but panning the
/// Viewport happens at drag rate and issue 09 already cost a round of work on drag
/// smoothness. Panning does not change what is lit — only which part of it is on screen —
/// so it must never land here.
///
/// Separate from `Visibility` so the engine stays a pure function with no state to reason
/// about, and the invalidation rules live in one place that names them.
final class VisibilityCache {
    /// What the result depends on. A Viewport origin is deliberately absent — that is the
    /// whole point of the type.
    private struct Inputs: Equatable {
        let walls: [Wall]
        let lights: [Light]
        let pawnLights: [Light]
        let imagePixelSize: CGSize
        let pixelsPerSquare: CGFloat
    }

    private var inputs: Inputs?
    private var cached: [LitRegion] = []
    /// Test seam: counts actual computations, so a test can prove a pan does not trigger one.
    private let onCompute: () -> Void

    init(onCompute: @escaping () -> Void = {}) {
        self.onCompute = onCompute
    }

    /// The lit regions for a Map's fog, computed once per change.
    ///
    /// `pixelsPerSquare` converts Light radii, which are in Grid squares, into the image
    /// pixels Walls live in — so re-declaring the Grid changes every Light's reach and
    /// correctly invalidates.
    func regions(for document: FogDocument, imagePixelSize: CGSize,
                 pixelsPerSquare: CGFloat) -> [LitRegion] {
        let next = Inputs(walls: document.walls,
                          lights: document.lights,
                          // Creatures emit nothing, and neither does a Pawn the DM has
                          // hidden — its token is off the Player Display, and a torch
                          // still burning there would light a wall-shadowed region
                          // radiating from nothing, and could reveal the very Creature the
                          // hiding was setting up.
                          //
                          // Filtered here rather than inside `Visibility.compute`, which
                          // takes a bare `[Light]` and stays a pure geometry seam that
                          // knows nothing about Pawns — and because `Inputs` is the cache
                          // key, so flipping either flag correctly invalidates instead of
                          // serving a stale polygon.
                          pawnLights: document.pawns
                              .filter { !$0.isDiscovered && !$0.isHidden }
                              .map(\.light),
                          imagePixelSize: imagePixelSize,
                          pixelsPerSquare: pixelsPerSquare)
        if next == inputs { return cached }

        onCompute()
        inputs = next
        // The boundary Walls are derived here, never stored: they belong to the image, not
        // to anything the DM authored.
        cached = Visibility.compute(
            walls: next.walls + Visibility.boundaryWalls(imagePixelSize: imagePixelSize),
            lights: next.lights + next.pawnLights,
            pixelsPerSquare: pixelsPerSquare)
        return cached
    }
}
