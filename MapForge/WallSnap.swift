import CoreGraphics
import Foundation

/// Pure geometry for Wall drawing: where a vertex lands, and which direction a span runs.
///
/// Separate from the gesture handling so it can be tested without a window — the same
/// split `ScaleMath` and `ViewportMath` already make. Snapping decides whether a traced
/// room is watertight, and a hairline gap at a corner leaks Light in a way that is
/// invisible until a player asks why they can see through a wall.
enum WallSnap {
    /// What a vertex snapped to, so the UI can show it. Snapping is visible, never silent.
    enum Target: Equatable {
        case none, endpoint, grid
    }

    struct Result: Equatable {
        let point: MapPoint
        let target: Target
    }

    /// The nearest snap target to `point`, or `point` itself if nothing is in range.
    ///
    /// Existing endpoints win over Grid intersections: a vertex that lands on the Grid
    /// instead of on the Wall beside it still leaves the gap endpoint snapping exists to
    /// close. `gridPixels` is nil when no Grid has been declared — snapping to a Grid that
    /// does not exist would scatter vertices.
    static func snap(_ point: MapPoint, to candidates: [MapPoint], gridPixels: CGFloat?,
                     tolerance: CGFloat) -> Result {
        if let endpoint = nearest(to: point, among: candidates, within: tolerance) {
            return Result(point: endpoint, target: .endpoint)
        }
        if let grid = gridPixels, grid > 0 {
            let candidate = MapPoint(x: (point.x / grid).rounded() * grid,
                                     y: (point.y / grid).rounded() * grid)
            if distance(point, candidate) <= tolerance {
                return Result(point: candidate, target: .grid)
            }
        }
        return Result(point: point, target: .none)
    }

    /// Every Wall endpoint, as snap candidates.
    static func endpoints(of walls: [Wall]) -> [MapPoint] {
        walls.flatMap { [$0.from, $0.to] }
    }

    private static func nearest(to point: MapPoint, among candidates: [MapPoint],
                                within tolerance: CGFloat) -> MapPoint? {
        var best: MapPoint?
        var bestDistance = tolerance
        for candidate in candidates {
            let d = distance(point, candidate)
            if d <= bestDistance {
                bestDistance = d
                best = candidate
            }
        }
        return best
    }

    /// `to`, rotated onto the nearest eighth-turn from `from` — 0°, 45°, 90°, 135° and
    /// their opposites. Held by default while dragging a span, because most Walls on a
    /// battle map are axis-aligned.
    ///
    /// Rotates rather than projects: projecting onto the axis shortens the span as the
    /// cursor drifts off it, so the Wall would visibly lag behind the pointer. This keeps
    /// the length the DM dragged and corrects only the direction.
    static func constrainAngle(from: MapPoint, to: MapPoint) -> MapPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        // A span with no length has no direction to constrain — atan2(0, 0) again.
        guard length > 0 else { return to }

        let step = CGFloat.pi / 4
        let snapped = (atan2(dy, dx) / step).rounded() * step
        return MapPoint(x: from.x + cos(snapped) * length,
                        y: from.y + sin(snapped) * length)
    }

    private static func distance(_ a: MapPoint, _ b: MapPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
