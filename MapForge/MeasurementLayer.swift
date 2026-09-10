import SwiftUI

/// A **Measurement** drawn over the Map: a translucent green shape, a solid green border,
/// and the distance beside it.
///
/// One view for both screens, differing only in the frame handed to it — the Player
/// Display's True Scale frame or the Control mirror's rebased one. Two drawing paths is how
/// the screens drift, which is the divergence `PawnToken` and
/// `PlayerVisibility.showsToPlayers` both exist to prevent.
///
/// The table sees this, readout included. That is a deliberate breach of the rule that the
/// Player Display draws only the world — see
/// [ADR 0005](../docs/adr/0005-the-player-display-shows-the-measurement.md).
struct MeasurementLayer: View {
    let measurement: Measurement
    /// Where the Measurement starts, already resolved against an anchoring Pawn.
    let origin: MapPoint
    let map: MapScale
    let frame: CGRect
    let pixelsPerSquare: CGFloat

    /// Green, per the feature's spec. Translucent fill, solid border — the pairing
    /// `GridFitOverlay` and `ViewportOverlay` already use for "a region under discussion".
    private var stroke: Color { .green }
    private var fill: Color { .green.opacity(0.25) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape
            readout
        }
        // A Measurement is drawn over the Map but is not part of it: it must never eat the
        // right-click that dismisses it, nor the Pawn drag underneath.
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var shape: some View {
        if measurement.shape == .line {
            // The one shape with no area: stroked end to end rather than filled.
            let (from, to) = measurement.segment(pixelsPerSquare: pixelsPerSquare) { _ in origin }
            Path { path in
                path.move(to: viewPoint(from))
                path.addLine(to: viewPoint(to))
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        } else {
            let polygon = measurement.project(pixelsPerSquare: pixelsPerSquare) { _ in origin }
            path(polygon)
                .fill(fill)
                .overlay { path(polygon).stroke(stroke, lineWidth: 2) }
        }
    }

    /// Fixed-size chrome, following `GridFitOverlay`'s readout rather than `PawnToken`'s
    /// map-scaled label: a distance is a fact about the world, not an object in it, and
    /// map-scaled text on a True Scale display is illegible on a large Map and enormous on
    /// a small one.
    private var readout: some View {
        Text(measurement.readout(in: DistanceUnit.current))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .position(readoutPoint)
    }

    /// Just past the shape's far edge, so the number *marks* where the measurement ends
    /// rather than sitting on top of it.
    ///
    /// Centred exactly on the edge, the capsule straddles it and hides the boundary the DM
    /// is trying to read — which is the one part of the shape that answers the question.
    /// The nudge is in view points, not Map pixels: it keeps the capsule clear of the
    /// stroke by a constant amount at any zoom, the way the capsule itself is a constant
    /// size.
    ///
    /// Always pulled back inside the frame, because a cone aimed off the edge of the
    /// Player Display would otherwise take its number with it.
    private var readoutPoint: CGPoint {
        let anchor = viewPoint(labelAnchor)
        let nudged = CGPoint(x: anchor.x + nudge.dx, y: anchor.y + nudge.dy)
        let inset: CGFloat = 28
        return CGPoint(x: min(max(nudged.x, inset), max(inset, frame.width - inset)),
                       y: min(max(nudged.y, inset), max(inset, frame.height - inset)))
    }

    /// The point on the shape the readout labels: the far end of an aimed shape, the top
    /// of a radius one.
    private var labelAnchor: MapPoint {
        let reach = measurement.distance * pixelsPerSquare
        switch measurement.shape {
        case .cone, .line:
            return MapPoint(x: origin.x + cos(measurement.direction) * reach,
                            y: origin.y + sin(measurement.direction) * reach)
        case .circle:
            return MapPoint(x: origin.x, y: origin.y - reach)
        case .square:
            // Half the side, because a Square's distance is its width and not its radius.
            return MapPoint(x: origin.x, y: origin.y - reach / 2)
        }
    }

    /// How far past the edge the capsule sits, in view points. Enough to clear the 2pt
    /// stroke and the capsule's own half-height without drifting far from what it labels.
    private var nudge: CGVector {
        let gap: CGFloat = 16
        switch measurement.shape {
        case .cone, .line:
            // Along the aim, so the number trails the far end wherever it is pointed.
            return CGVector(dx: cos(measurement.direction) * gap,
                            dy: sin(measurement.direction) * gap)
        case .circle, .square:
            // Straight up off the top edge: a radius shape has no direction to trail.
            return CGVector(dx: 0, dy: -gap)
        }
    }

    private func viewPoint(_ point: MapPoint) -> CGPoint {
        PlayerPlacement.viewPoint(point, map: map, frame: frame)
    }

    private func path(_ polygon: Polygon) -> Path {
        var path = Path()
        guard let first = polygon.vertices.first else { return path }
        path.move(to: viewPoint(first))
        for vertex in polygon.vertices.dropFirst() { path.addLine(to: viewPoint(vertex)) }
        path.closeSubpath()
        return path
    }
}
