import SwiftUI

/// The Fog Overlay: darkness over the Map, with the lit regions punched out of it.
///
/// The app's first compositing — everything before this was a plain `Image` in a `ZStack`.
/// Fill the whole surface with darkness, then subtract each Light's polygons with
/// `.destinationOut`, brightest last so bright wins where two Lights meet. That is the
/// blend-mode half of ADR 0002; the exact polygons come from `Visibility` on the CPU.
///
/// Shared by both surfaces. The Player Display passes the players' opacities and the
/// Control Window the DM's weaker tint, so the two can never tell different stories about
/// what is hidden — only about how hard it is to see.
struct FogCanvas: View {
    let regions: [LitRegion]
    let map: MapScale
    /// Where the Map image sits on this surface; carries the Viewport pan.
    let frame: CGRect
    /// `FogShading.player` or `.control`.
    let opacity: (VisibilityLevel) -> CGFloat

    var body: some View {
        Canvas { context, size in
            let unlit = opacity(.unlit)
            guard unlit > 0 else { return }

            // Everything starts hidden; the Lights take pieces back out.
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.black.opacity(unlit)))

            // Dim first, then bright over it: bright anywhere beats dim anywhere, matching
            // `Visibility.level`. Drawing them the other way round would leave a dim patch
            // where two torches overlap.
            subtract(regions.map(\.dim), from: &context, to: opacity(.dim), of: unlit)
            subtract(regions.map(\.bright), from: &context, to: opacity(.bright), of: unlit)
        }
        .allowsHitTesting(false)
    }

    /// Lift the darkness over `polygons` from `unlit` down to `target`.
    ///
    /// `.destinationOut` removes rather than paints, so an alpha of 1 clears completely and
    /// a partial alpha thins the darkness to exactly the level wanted — no second pass and
    /// no double-darkening where polygons overlap.
    private func subtract(_ polygons: [Polygon], from context: inout GraphicsContext,
                          to target: CGFloat, of unlit: CGFloat) {
        guard unlit > 0, target < unlit else { return }
        let removal = (unlit - target) / unlit
        context.drawLayer { layer in
            layer.blendMode = .destinationOut
            for polygon in polygons where !polygon.isEmpty {
                layer.fill(path(polygon), with: .color(.black.opacity(removal)))
            }
        }
    }

    /// One polygon, in image pixels, mapped onto this surface.
    private func path(_ polygon: Polygon) -> Path {
        var path = Path()
        let points = polygon.vertices.map {
            PlayerPlacement.viewPoint($0, map: map, frame: frame)
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}
