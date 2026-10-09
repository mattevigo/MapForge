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
    /// The Distance Unit the readout speaks — the same on both screens, so the table and the
    /// DM never read one distance two ways.
    let unit: DistanceUnit

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
            // A polygonal chain: Origin, every placed vertex, and — while still being
            // drawn — the live segment out to the cursor.
            let points = chainPoints
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // A cap at every vertex. A bare stroke fades into the artwork and simply stops
            // somewhere, so the DM cannot see where the measurement ends — the one thing a
            // Line has to communicate. The other three shapes are closed and carry their
            // own boundary; a Line has to be given one. Every corner gets one too, so a
            // path around an obstacle reads as the points the DM actually chose.
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                endCap.position(point)
            }
        } else {
            let polygon = measurement.project(pixelsPerSquare: pixelsPerSquare) { _ in origin }
            path(polygon)
                .fill(fill)
                .overlay { path(polygon).stroke(stroke, lineWidth: 2) }
        }
    }

    /// Every point the chain runs through, in view coordinates: the Origin, each placed
    /// vertex, and the live end at the cursor while the chain is still being drawn.
    ///
    /// A finished chain stops at its last placed vertex — the pointer's position when the
    /// DM right-clicked is not a point they asked for.
    private var chainPoints: [CGPoint] {
        var points = [viewPoint(origin)]
        points += measurement.chain.map(viewPoint)
        if measurement.isChaining {
            points.append(viewPoint(measurement.liveEnd(origin: origin,
                                                        pixelsPerSquare: pixelsPerSquare)))
        }
        return points
    }

    /// The dot terminating each end of a Line.
    ///
    /// Fixed size, like the readout capsule: it marks a point rather than covering an area,
    /// so it must stay legible at any zoom and on the Player Display's True Scale alike.
    /// White-ringed because a green dot on green terrain — or on the party's own tokens —
    /// disappears, and this is the thing being pointed at.
    private var endCap: some View {
        Circle()
            .fill(stroke)
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 1)
    }

    /// Fixed-size chrome, following `GridFitOverlay`'s readout rather than `PawnToken`'s
    /// map-scaled label: a distance is a fact about the world, not an object in it, and
    /// map-scaled text on a True Scale display is illegible on a large Map and enormous on
    /// a small one.
    private var readout: some View {
        Text(measurement.readout(in: unit))
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
        case .line:
            // The far end of the chain, which is the live end while it is being drawn and
            // the last placed vertex once it is finished — never a projection from the
            // Origin, since a chain has corners.
            return measurement.isChaining
                ? measurement.liveEnd(origin: origin, pixelsPerSquare: pixelsPerSquare)
                : (measurement.chain.last ?? origin)
        case .cone:
            return MapPoint(x: origin.x + cos(measurement.direction) * reach,
                            y: origin.y + sin(measurement.direction) * reach)
        case .circle:
            return MapPoint(x: origin.x, y: origin.y - reach)
        case .square:
            // Half the side, because a Square's distance is its width and not its radius.
            return MapPoint(x: origin.x, y: origin.y - reach / 2)
        }
    }

    /// How far off the edge the capsule sits, in view points. Enough to clear the stroke
    /// and the end cap without drifting away from what it labels.
    ///
    /// Pushed *sideways* for an aimed shape, not along the aim. Continuing along the
    /// direction reads as the measurement carrying on past its end — the capsule floats
    /// out in open space with nothing connecting it to the line — whereas offsetting
    /// perpendicular keeps it beside the end it names. Always to the upper side, so the
    /// number sits above a horizontal measurement rather than under the DM's cursor.
    private var nudge: CGVector {
        // 22, not less: at 14 the capsule's own half-height overlapped the end cap and
        // partly hid the marker it exists to point at. Checked by rendering the layer at
        // four angles rather than by eye.
        let gap: CGFloat = 22
        switch measurement.shape {
        case .cone, .line:
            let normal = CGVector(dx: -sin(measurement.direction),
                                  dy: cos(measurement.direction))
            let side: CGFloat = normal.dy > 0 ? -1 : 1
            return CGVector(dx: normal.dx * gap * side, dy: normal.dy * gap * side)
        case .circle, .square:
            // Straight up off the top edge: a radius shape has no direction to sit beside.
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
