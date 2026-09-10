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
    /// Shown beside the shape. Off for the fog authoring preview, which has no readout.
    var showsReadout = true

    /// Green, per the feature's spec. Translucent fill, solid border — the pairing
    /// `GridFitOverlay` and `ViewportOverlay` already use for "a region under discussion".
    private var stroke: Color { .green }
    private var fill: Color { .green.opacity(0.25) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape
            if showsReadout { readout }
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

    /// Beside the shape's far edge for an aimed shape, above a radius shape — and always
    /// pulled back inside the frame, because a cone aimed off the edge of the Player
    /// Display would otherwise take its number with it.
    private var readoutPoint: CGPoint {
        let anchor = viewPoint(labelAnchor)
        let inset: CGFloat = 28
        return CGPoint(x: min(max(anchor.x, inset), max(inset, frame.width - inset)),
                       y: min(max(anchor.y, inset), max(inset, frame.height - inset)))
    }

    private var labelAnchor: MapPoint {
        let reach = measurement.distance * pixelsPerSquare
        switch measurement.shape {
        case .cone, .line:
            return MapPoint(x: origin.x + cos(measurement.direction) * reach,
                            y: origin.y + sin(measurement.direction) * reach)
        case .circle:
            return MapPoint(x: origin.x, y: origin.y - reach)
        case .square:
            return MapPoint(x: origin.x, y: origin.y - reach / 2)
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
