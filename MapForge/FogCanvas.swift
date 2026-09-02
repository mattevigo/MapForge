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
            subtract(regions, band: \.dim, from: &context, to: opacity(.dim), of: unlit)
            subtract(regions, band: \.bright, from: &context, to: opacity(.bright), of: unlit)
        }
        .allowsHitTesting(false)
    }

    /// Lift the darkness over `polygons` from `unlit` down to `target`.
    ///
    /// The layer's polygons are filled at FULL strength and the removal alpha applied once,
    /// to the layer as a whole. Filling each polygon at the alpha instead would subtract
    /// twice wherever two overlapped — `.destinationOut` multiplies — leaving the overlap
    /// *brighter* than either region alone. That is a visible seam exactly where two
    /// torches meet, which is the case issue 05's list called out.
    private func subtract(_ regions: [LitRegion], band: KeyPath<LitRegion, Polygon>,
                          from context: inout GraphicsContext,
                          to target: CGFloat, of unlit: CGFloat) {
        let removal = FogShading.removalAlpha(from: unlit, to: target)
        guard removal > 0 else { return }
        // `.destinationOut` must be the mode the LAYER composites back with, so it is set
        // on the parent context before `drawLayer`. Setting it *inside* the layer applies
        // it to the layer's own empty contents — erasing nothing from transparency — and
        // the layer then lands on the darkness with the default `.normal`, leaving the fog
        // untouched. That is the bug this whole file existed to avoid and still had.
        let previousBlendMode = context.blendMode
        context.blendMode = .destinationOut
        defer { context.blendMode = previousBlendMode }
        context.drawLayer { layer in
            layer.opacity = removal
            for region in regions {
                let polygon = region[keyPath: band]
                guard !polygon.isEmpty else { continue }
                // A radial gradient across the polygon, opaque through the middle and
                // fading to nothing at the rim, so a torch fades out instead of ending in
                // a suspicious circle. The polygon's own edges stay hard — those are Wall
                // shadows, and blurring them makes "can I see round that corner" ambiguous.
                layer.fill(path(polygon), with: falloffShading(for: region, band: band))
            }
        }
    }

    /// Full strength through the middle of a Light, fading to clear exactly at its rim.
    private func falloffShading(for region: LitRegion,
                                band: KeyPath<LitRegion, Polygon>) -> GraphicsContext.Shading {
        let centre = PlayerPlacement.viewPoint(region.origin, map: map, frame: frame)
        let rim = region[keyPath: band].radiusFrom(region.origin)
        let radius = rim / max(map.imagePixelSize.width, 1) * frame.width
        guard radius > 0 else { return .color(.black) }

        let stops = stride(from: 0.0, through: 1.0, by: 0.05).map { fraction in
            Gradient.Stop(color: .black.opacity(FogShading.falloffOpacity(atFractionOfRadius: fraction)),
                          location: fraction)
        }
        return .radialGradient(Gradient(stops: stops), center: centre,
                               startRadius: 0, endRadius: radius)
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
