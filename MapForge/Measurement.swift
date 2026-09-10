import CoreGraphics
import Foundation

/// Which shape a Measurement projects.
///
/// Circle is a radius and Square is a *side length*, which is the one place this feature
/// departs from reading both as radii: a spell card says "a 20-foot cube", and reading
/// that as a radius quadruples the area the DM meant. The readout names which it is, so
/// the difference is read rather than assumed. See `CONTEXT.md`'s **Measurement Shape**.
enum MeasurementShape: CaseIterable, Hashable {
    case cone, square, circle, line

    var label: String {
        switch self {
        case .cone: "Cone"
        case .square: "Square"
        case .circle: "Circle"
        case .line: "Line"
        }
    }

    /// Whether the shape is aimed. The radius shapes ignore direction entirely, which is
    /// why a typed Measurement on one of them does not swing with the mouse.
    var isAimed: Bool {
        switch self {
        case .cone, .line: true
        case .square, .circle: false
        }
    }
}

/// Where a Measurement starts.
///
/// A sum type rather than a point plus an optional ID: the two cases resolve differently,
/// and only one of them can go stale. A Pawn-anchored Origin follows the Pawn as it is
/// dragged and ends when the Pawn does — the `resolved…` guard on `AppState` is what keeps
/// a stale ID inert, exactly as Solo Sight does.
enum MeasurementOrigin: Equatable {
    case point(MapPoint)
    case pawn(Pawn.ID)
}

/// A distance the DM asked about mid-play: an Origin, a shape, a length and an aim.
///
/// Never persisted. See `CONTEXT.md`'s **Measurement** and, for why the table sees it,
/// [ADR 0005](../docs/adr/0005-the-player-display-shows-the-measurement.md).
struct Measurement: Equatable {
    var origin: MeasurementOrigin
    var shape: MeasurementShape

    /// In **Grid squares**, like a Light's radii and a Pawn's sight. Metres exist only at
    /// the rendering edge.
    var distance: CGFloat

    /// Radians, screen convention (+x is 0, growing clockwise as y grows downward).
    /// Ignored by the radius shapes.
    var direction: CGFloat

    /// The 5e cone: as wide at its end as it is long, which makes the half-angle
    /// `atan(0.5)` and the total `2·atan(0.5)` ≈ 53.13°.
    ///
    /// Not 90°. A grid-aligned quadrant is easier to draw and silently mis-measures every
    /// fireball at the table, which is the one thing a measuring tool must not do.
    static let coneHalfAngle: CGFloat = atan(0.5)

    /// Rounds a dragged distance to a whole square. Every DnD distance is a multiple of
    /// one square, and nobody wants to read "8.7 m" off a screen.
    ///
    /// Typed distances deliberately bypass this: you typed it, you meant it.
    static func snap(squares: CGFloat) -> CGFloat { max(0, squares.rounded()) }

    /// The distance as the DM would say it.
    func readout(in unit: DistanceUnit) -> String {
        let measure = unit.format(squares: distance)
        switch shape {
        case .circle: return "\(measure) radius"
        case .square: return "\(measure) across"
        case .cone, .line: return measure
        }
    }

    /// The Origin in image pixels, given where an anchoring Pawn currently stands.
    ///
    /// `pawnAt` is passed in rather than looked up so this stays a pure function — the
    /// staleness question belongs to `AppState`, which already answers it for Solo Sight.
    func originPoint(pawnAt: (Pawn.ID) -> MapPoint?) -> MapPoint? {
        switch origin {
        case .point(let point): point
        case .pawn(let id): pawnAt(id)
        }
    }

    /// The two ends of a `.line`, in image pixels. A Line is stroked rather than filled,
    /// so it is the one shape that is not a polygon.
    func segment(pixelsPerSquare: CGFloat,
                 pawnAt: (Pawn.ID) -> MapPoint? = { _ in nil }) -> (MapPoint, MapPoint) {
        guard let start = originPoint(pawnAt: pawnAt) else {
            return (MapPoint(x: 0, y: 0), MapPoint(x: 0, y: 0))
        }
        let length = distance * pixelsPerSquare
        return (start, MapPoint(x: start.x + cos(direction) * length,
                                y: start.y + sin(direction) * length))
    }

    /// The shape as a polygon in image pixels, ready for the same `Polygon`-to-`Path`
    /// conversion the fog already uses.
    ///
    /// Walls are deliberately absent: a Measurement is not blocked by them. 5e range is
    /// measured through obstacles, and routing this through `Visibility.compute` would put
    /// a Measurement into `VisibilityCache.Inputs` and invalidate the lighting on every
    /// mouse move.
    func project(pixelsPerSquare: CGFloat,
                 pawnAt: (Pawn.ID) -> MapPoint? = { _ in nil }) -> Polygon {
        guard distance > 0, pixelsPerSquare > 0,
              let start = originPoint(pawnAt: pawnAt) else { return Polygon([]) }

        let length = distance * pixelsPerSquare

        switch shape {
        case .circle:
            return Polygon.circle(center: start, radius: length)

        case .square:
            // `length` is the side, not the half-side: the whole point of the decision.
            let half = length / 2
            return Polygon([
                MapPoint(x: start.x - half, y: start.y - half),
                MapPoint(x: start.x + half, y: start.y - half),
                MapPoint(x: start.x + half, y: start.y + half),
                MapPoint(x: start.x - half, y: start.y + half),
            ])

        case .cone:
            // A flat far edge, not an arc. 5e's cone is "as wide at its end as it is
            // long", and that width is the straight chord across the mouth: an arc whose
            // vertices all sit `length` from the apex is only 0.894 × length across, so
            // it under-measures every cone by a tenth.
            //
            // The apex plus two corners at ±`coneHalfAngle`, each far enough along its
            // own ray that its *axial* distance is `length`.
            let reach = length / cos(Self.coneHalfAngle)
            let left = direction - Self.coneHalfAngle
            let right = direction + Self.coneHalfAngle
            return Polygon([
                start,
                MapPoint(x: start.x + cos(left) * reach, y: start.y + sin(left) * reach),
                MapPoint(x: start.x + cos(right) * reach, y: start.y + sin(right) * reach),
            ])

        case .line:
            // A Line has no area. It is returned empty so a filling caller draws nothing,
            // and stroked from `segment(pixelsPerSquare:)` instead.
            return Polygon([])
        }
    }
}
