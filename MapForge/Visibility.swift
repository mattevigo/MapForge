import CoreGraphics
import Foundation

/// The lit region of one Light: two polygons in image pixels, bright inside dim.
///
/// Polygons rather than a sampled grid because a shadow edge must land exactly on the
/// Wall that casts it — a grid would step it at the cell size — and because issue 06
/// fills these straight into a Canvas path.
struct LitRegion: Equatable {
    let lightID: UUID
    let bright: Polygon
    let dim: Polygon
}

/// How lit one point of the Map is. Three-valued, not boolean, because a Light has a
/// bright and a dim radius — the 5e convention every stat block is written in.
enum VisibilityLevel: Equatable {
    case bright, dim, unlit
}

/// Computes Visibility: which parts of the Map each Light reaches, given the Walls.
///
/// Pure geometry, no rendering and no GPU — see ADR 0002. "Can the players see round
/// that corner" must be right and is miserable to verify by eye, so every case in
/// issue 05's list is a unit test.
enum Visibility {
    /// The lit regions of every Light that is on. Walls block; radii clip.
    ///
    /// `pixelsPerSquare` converts a Light's radii — which are in Grid squares, because a
    /// torch is a physical thing — into the image pixels Walls live in.
    static func compute(walls: [Wall], lights: [Light], pixelsPerSquare: CGFloat) -> [LitRegion] {
        lights.filter(\.isOn).map { light in
            LitRegion(lightID: light.id,
                      bright: litPolygon(from: light.at, radius: light.brightSquares * pixelsPerSquare,
                                         walls: walls),
                      dim: litPolygon(from: light.at, radius: light.dimSquares * pixelsPerSquare,
                                      walls: walls))
        }
    }

    /// The four implicit Walls at the image bounds.
    ///
    /// Always present and never editable: they close every visibility polygon, which the
    /// sweep wants anyway, and they stop Light spilling into the letterbox around a Map.
    /// Derived from the image, never stored in the fog file.
    static func boundaryWalls(imagePixelSize size: CGSize) -> [Wall] {
        let corners = [MapPoint(x: 0, y: 0), MapPoint(x: size.width, y: 0),
                       MapPoint(x: size.width, y: size.height), MapPoint(x: 0, y: size.height)]
        return (0..<4).map { Wall(from: corners[$0], to: corners[($0 + 1) % 4]) }
    }

    /// How lit a point is across every Light: bright anywhere wins over dim anywhere, and
    /// dim wins over unlit. Two torches meeting must not leave a dim patch between them.
    static func level(at point: MapPoint, in regions: [LitRegion]) -> VisibilityLevel {
        var result = VisibilityLevel.unlit
        for region in regions {
            if region.bright.contains(point) { return .bright }
            if region.dim.contains(point) { result = .dim }
        }
        return result
    }

    /// The region visible from `origin` within `radius`, as a polygon.
    ///
    /// The standard segment-shadowcasting sweep: cast a ray at every Wall endpoint, keep
    /// the nearest hit, and join the hits in angle order. Each endpoint gets three rays —
    /// one at it and one a hair either side — because the ray *through* a vertex is
    /// exactly where a polygon must continue past the corner rather than stop on it. That
    /// is the classic source of one-pixel light leaks, so it is a tested case, not a
    /// tuning knob.
    private static func litPolygon(from origin: MapPoint, radius: CGFloat, walls: [Wall]) -> Polygon {
        guard radius > 0 else { return Polygon([]) }
        let blocking = walls.filter { intersectsCircle($0, center: origin, radius: radius) }
        guard !blocking.isEmpty else { return Polygon.circle(center: origin, radius: radius) }

        var angles: [CGFloat] = []
        for wall in blocking {
            for endpoint in [wall.from, wall.to] {
                let angle = atan2(endpoint.y - origin.y, endpoint.x - origin.x)
                angles.append(contentsOf: [angle - vertexNudge, angle, angle + vertexNudge])
            }
        }
        // The radius limit still has to read as a curve wherever no Wall defines the
        // boundary, so the circle's own angles join the sweep.
        let step = 2 * CGFloat.pi / CGFloat(Polygon.circleSegments)
        angles.append(contentsOf: (0..<Polygon.circleSegments).map { CGFloat($0) * step - .pi })
        angles.sort()

        let hits = angles.map { angle in
            castRay(from: origin, angle: angle, radius: radius, walls: blocking)
        }
        return Polygon(deduplicated(hits))
    }

    /// How far either side of a vertex the extra rays go, in radians. Small enough that
    /// the pair straddles only the vertex it belongs to, large enough to survive the
    /// floating-point error in `atan2` at map scale.
    private static let vertexNudge: CGFloat = 1e-5

    /// The first thing a ray from `origin` meets: the nearest Wall, or the radius limit.
    private static func castRay(from origin: MapPoint, angle: CGFloat, radius: CGFloat,
                                walls: [Wall]) -> MapPoint {
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        var nearest = radius
        for wall in walls {
            if let distance = rayHit(origin: origin, direction: direction, wall: wall),
               distance < nearest {
                nearest = distance
            }
        }
        return MapPoint(x: origin.x + direction.x * nearest, y: origin.y + direction.y * nearest)
    }

    /// Distance from `origin` along `direction` to `wall`, or nil if the ray misses.
    ///
    /// Solves origin + t·direction = wall.from + u·(wall.to − wall.from) for t ≥ 0 and
    /// u ∈ [0, 1]. A ray parallel to the Wall has no single crossing and returns nil —
    /// the Wall then contributes nothing at that angle, which is correct: a Wall seen
    /// exactly edge-on blocks a line of zero width.
    private static func rayHit(origin: MapPoint, direction: CGPoint, wall: Wall) -> CGFloat? {
        let sx = wall.to.x - wall.from.x, sy = wall.to.y - wall.from.y
        let denominator = direction.x * sy - direction.y * sx
        guard abs(denominator) > 1e-12 else { return nil }

        // A Wall touching the Light casts a shadow of zero width, but the ray aimed at
        // the touching endpoint has an undefined direction (atan2(0,0)) and the sweep
        // loses the far side entirely. Treat it as non-blocking: geometrically it blocks
        // a line, and a DM who drops a Light on a Wall corner wants light, not a dead map.
        if hypot(wall.from.x - origin.x, wall.from.y - origin.y) < 1e-9 { return nil }
        if hypot(wall.to.x - origin.x, wall.to.y - origin.y) < 1e-9 { return nil }

        let dx = wall.from.x - origin.x, dy = wall.from.y - origin.y
        let t = (dx * sy - dy * sx) / denominator
        let u = (dx * direction.y - dy * direction.x) / denominator
        guard t >= 0, u >= 0, u <= 1 else { return nil }
        return t
    }

    /// Whether a Wall comes within `radius` of `center` — Walls further off cannot cast
    /// into this Light's region, and dropping them early keeps the sweep small.
    private static func intersectsCircle(_ wall: Wall, center: MapPoint, radius: CGFloat) -> Bool {
        let ax = wall.from.x - center.x, ay = wall.from.y - center.y
        let bx = wall.to.x - center.x, by = wall.to.y - center.y
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        // A degenerate Wall (both endpoints equal) is a point: test it directly.
        guard lengthSquared > 0 else { return ax * ax + ay * ay <= radius * radius }
        let t = min(max(-(ax * dx + ay * dy) / lengthSquared, 0), 1)
        let cx = ax + t * dx, cy = ay + t * dy
        return cx * cx + cy * cy <= radius * radius
    }

    /// Drops consecutive duplicate vertices. The nudged ray pairs collapse onto one point
    /// wherever nothing was there to straddle, and a polygon carrying them would be full
    /// of zero-length edges.
    private static func deduplicated(_ points: [MapPoint]) -> [MapPoint] {
        var result: [MapPoint] = []
        for point in points {
            if let last = result.last,
               abs(last.x - point.x) < 1e-9, abs(last.y - point.y) < 1e-9 { continue }
            result.append(point)
        }
        return result
    }
}
