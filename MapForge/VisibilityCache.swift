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
                 pixelsPerSquare: CGFloat,
                 soloSightPawnID: Pawn.ID? = nil) -> [LitRegion] {
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
                          //
                          // Solo Sight narrows the same filter to one Pawn: the DM is
                          // asking what the Map looks like lit by that character alone, so
                          // every other carried light goes out. `document.lights` — the
                          // Map's own braziers and sconces — are deliberately untouched: a
                          // wall sconce is the room, not another character's influence
                          // (ADR 0004). A stale ID matches nothing and would black out the
                          // Map on the table, so it falls back to lighting everything.
                          pawnLights: Self.pawnLights(of: document,
                                                      isolating: soloSightPawnID),
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

    /// Which Pawns light the Map: everything that emits, narrowed to one under Solo Sight.
    ///
    /// The isolated Pawn goes through the same `!isDiscovered && !isHidden` gate as any
    /// other — a Creature emits nothing however it is selected, and the eye still beats
    /// lighting.
    private static func pawnLights(of document: FogDocument,
                                   isolating soloSightPawnID: Pawn.ID?) -> [Light] {
        let emitting = document.pawns.filter { !$0.isDiscovered && !$0.isHidden }
        guard let id = soloSightPawnID,
              emitting.contains(where: { $0.id == id }) else { return emitting.map(\.light) }
        return emitting.filter { $0.id == id }.map(\.light)
    }
}
