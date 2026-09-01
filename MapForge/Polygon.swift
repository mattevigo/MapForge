import CoreGraphics
import Foundation

/// A closed polygon in image pixels — the shape a Light reaches.
///
/// Its own type rather than `[MapPoint]` so the closing edge (last vertex back to first)
/// is implied everywhere instead of being a rule each caller has to remember.
struct Polygon: Equatable {
    private(set) var vertices: [MapPoint]

    init(_ vertices: [MapPoint]) {
        self.vertices = vertices
    }

    var isEmpty: Bool { vertices.count < 3 }

    /// How finely a radius limit is approximated when a Light reaches nothing that blocks
    /// it. Fine enough that the straight edges read as a curve at any zoom the preview
    /// allows, coarse enough to stay cheap.
    static let circleSegments = 64

    static func circle(center: MapPoint, radius: CGFloat) -> Polygon {
        guard radius > 0 else { return Polygon([]) }
        let step = 2 * CGFloat.pi / CGFloat(circleSegments)
        return Polygon((0..<circleSegments).map { i in
            let angle = CGFloat(i) * step
            return MapPoint(x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius)
        })
    }

    /// Whether `point` lies inside, by the even-odd ray-crossing rule.
    ///
    /// A point exactly on an edge is deliberately unspecified: callers ask about interiors,
    /// and pinning boundary behaviour down would mean an epsilon that lies at some scale.
    func contains(_ point: MapPoint) -> Bool {
        guard !isEmpty else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let a = vertices[i], b = vertices[j]
            // Does the upward ray from `point` cross edge a→b?
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
