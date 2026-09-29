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
        case .cone: String(localized: "Cone")
        case .square: String(localized: "Square", comment: "A Measurement Shape, drawn around its Origin by side length")
        case .circle: String(localized: "Circle")
        case .line: String(localized: "Line", comment: "A Measurement Shape: a path of points")
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
struct Measurement: Equatable, Identifiable {
    /// Identity, so a pinned Measurement can be unpinned without being compared by value —
    /// two pins of the same shape and distance from the same Origin are a real thing to
    /// have on the Map, and would otherwise be indistinguishable.
    ///
    /// Deliberately **excluded from `==`** (see the explicit implementation below): the
    /// equality that matters here is "has this Measurement changed", which every
    /// `setMeasurement` guard and SwiftUI diff asks. Including the id would make every
    /// copy unequal to itself and defeat both.
    let id = UUID()

    var origin: MeasurementOrigin
    var shape: MeasurementShape

    /// In **Grid squares**, like a Light's radii and a Pawn's sight. Metres exist only at
    /// the rendering edge.
    var distance: CGFloat

    /// Radians, screen convention (+x is 0, growing clockwise as y grows downward).
    /// Ignored by the radius shapes.
    var direction: CGFloat

    /// Whether the Measurement has stopped following the cursor.
    ///
    /// Set by the left-click that commits it. Until then the shape rubber-bands, which is
    /// how the DM finds the distance in the first place; after it, the shape holds still
    /// long enough to be read and argued over. A Measurement that never settles is the
    /// failure ADR 0005 rejected under another name — evidence that vanishes the moment
    /// the table wants to discuss it.
    ///
    /// Settled freezes the **aim** as well as the distance. A shape that went on swinging
    /// could not be read: it moved out from under the DM as they took their hand off the
    /// mouse. Pointing is what the first click is for; the second is for stopping.
    var isDistanceSettled = false

    /// Whether the distance was typed, so the mouse may re-aim the shape but never resize
    /// it.
    ///
    /// The one case where aim and distance come apart, and the point of typing one: an
    /// exact range — 9 m, off the spell card — swung wherever the DM is asking about.
    /// A left-click settles it like any other, which is how it stops.
    var isDistanceTyped = false

    /// The vertices a `.line` runs through after its Origin, in image pixels.
    ///
    /// A Line is a **polygonal chain**, not a segment: the DM clicks a run of points and
    /// reads the length of the whole path. That is the movement question — can I get there
    /// this turn, going round the table rather than through it — where the other three
    /// shapes answer the straight-line range question. Empty for every other shape.
    var chain: [MapPoint] = []

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

    /// Whether this Measurement is drawn as a chain the DM is still adding points to.
    var isChaining: Bool { shape == .line && !isDistanceSettled }

    /// Where the live segment starts: the last vertex placed, or the Origin before any.
    ///
    /// The rubber-band runs from here rather than from the Origin, or a chain's second
    /// segment would be drawn from the wrong end.
    func chainAnchor(origin: MapPoint) -> MapPoint { chain.last ?? origin }

    /// The whole path's length in Grid squares: Origin to first vertex, then vertex to
    /// vertex.
    ///
    /// Not snapped, unlike a radius shape's distance. Rounding every vertex would compound
    /// the error along a long path, and the DM placed each point deliberately.
    func chainSquares(from origin: MapPoint, pixelsPerSquare: CGFloat) -> CGFloat {
        guard pixelsPerSquare > 0 else { return 0 }
        var total: CGFloat = 0
        var previous = origin
        for vertex in chain {
            total += hypot(vertex.x - previous.x, vertex.y - previous.y)
            previous = vertex
        }
        return total / pixelsPerSquare
    }

    /// A copy with one more vertex — what a left-click does to a Line being drawn.
    func extended(to point: MapPoint) -> Measurement {
        var next = self
        next.chain.append(point)
        return next
    }

    /// A copy that has stopped following the cursor — what right-click does to a chain.
    ///
    /// Deliberately adds no vertex: wherever the pointer happened to be when the DM
    /// finished is not a point they asked for.
    ///
    /// The direction is re-pointed along the chain's own last segment. It was left aiming
    /// at wherever the cursor was, and the readout offsets perpendicular to it — so a
    /// finished chain's number would sit at an angle unrelated to the path it labels.
    func finished(origin: MapPoint, pixelsPerSquare: CGFloat) -> Measurement {
        var next = self
        next.isDistanceSettled = true
        // Drop the live segment from the total: it was the rubber-band out to the cursor,
        // and the DM has just said the chain ends at its last placed vertex.
        next.distance = chainSquares(from: origin, pixelsPerSquare: pixelsPerSquare)
        if let last = chain.last {
            let previous = chain.count >= 2 ? chain[chain.count - 2] : origin
            next.direction = MeasurementControl.direction(from: previous, to: last)
        }
        return next
    }

    /// What a left-click on the Map does to this Measurement: settle it at the distance
    /// now shown, or — if it is already settled — dismiss it, which `nil` says.
    ///
    /// One button drives the whole life of a Measurement, because right-click opens the
    /// shape menu and can no longer double as the dismissal. Two clicks in the same place,
    /// so the DM never has to remember which button does which.
    ///
    /// Here rather than in the view so it can be tested, like `aimed(at:from:)`.
    func clicked() -> Measurement? {
        guard !isDistanceSettled else { return nil }
        var next = self
        next.isDistanceSettled = true
        return next
    }

    /// Re-aimed at the cursor and resized to reach it, until the Measurement settles —
    /// after which the mouse does nothing to it at all.
    ///
    /// **Settled means settled**, aim included. A Cone that went on swinging after its
    /// second click could not be read: the shape moved out from under the DM as they took
    /// their hand off the mouse, and its readout orbited the point it labels. The earlier
    /// rule kept the aim live so an exact range could be pointed wherever it was asked
    /// about, but that is what the *first* click is for — pointing — and the second is for
    /// stopping.
    ///
    /// The rule lives here rather than in the view so it can be tested: a settled
    /// Measurement silently moved by the next mouse move is the failure this feature would
    /// be most likely to ship with, since it only shows up between reading a number and
    /// moving the mouse.
    func aimed(at cursor: MapPoint, from origin: MapPoint,
               pixelsPerSquare: CGFloat) -> Measurement {
        guard !isDistanceSettled, pixelsPerSquare > 0 else { return self }

        var next = self
        let anchor = shape == .line ? chainAnchor(origin: origin) : origin
        next.direction = MeasurementControl.direction(from: anchor, to: cursor)

        // A typed distance is exact and the mouse must not resize it — only re-aim it.
        guard !isDistanceTyped else { return next }

        if shape == .line {
            // The running total: everything already placed, plus the live segment. Exact,
            // not snapped — see `chainSquares`.
            let live = hypot(cursor.x - anchor.x, cursor.y - anchor.y) / pixelsPerSquare
            next.distance = chainSquares(from: origin, pixelsPerSquare: pixelsPerSquare) + live
            return next
        }

        let squares = hypot(cursor.x - origin.x, cursor.y - origin.y) / pixelsPerSquare
        next.distance = Self.snap(squares: squares)
        return next
    }

    /// Value equality, identity excluded — see `id`. What every caller asks is "has this
    /// Measurement changed", not "is it the same object".
    static func == (lhs: Measurement, rhs: Measurement) -> Bool {
        lhs.origin == rhs.origin
            && lhs.shape == rhs.shape
            && lhs.distance == rhs.distance
            && lhs.direction == rhs.direction
            && lhs.isDistanceSettled == rhs.isDistanceSettled
            && lhs.isDistanceTyped == rhs.isDistanceTyped
            && lhs.chain == rhs.chain
    }

    /// Whether `point` lands on this Measurement — the hit-test behind pinning.
    ///
    /// Only a settled Measurement answers true: one still following the cursor is under
    /// the pointer by definition, so hit-testing it would offer to pin whatever the DM
    /// happens to be dragging.
    ///
    /// The area shapes use their own drawn outline. A Line has no area, so it gets a
    /// tolerance band along each segment — a DM cannot be asked to click a 2pt stroke
    /// exactly, and `FogOverlay` widens a Wall's hit area for the same reason.
    func contains(_ point: MapPoint, origin: MapPoint, pixelsPerSquare: CGFloat) -> Bool {
        guard isDistanceSettled, pixelsPerSquare > 0, distance > 0 || !chain.isEmpty else {
            return false
        }

        if shape == .line {
            let tolerance = Self.lineHitTolerance
            var previous = origin
            for vertex in chain {
                if Self.distance(from: point, toSegment: previous, vertex) <= tolerance {
                    return true
                }
                previous = vertex
            }
            return false
        }

        return project(pixelsPerSquare: pixelsPerSquare) { _ in origin }.contains(point)
    }

    /// How near a click has to land to count as on a Line, in image pixels.
    ///
    /// A constant in Map space rather than view points: it is compared against Map
    /// coordinates, and a zoom-dependent tolerance would need the transform passed in for
    /// a difference the DM would not notice.
    static let lineHitTolerance: CGFloat = 8

    /// Shortest distance from a point to a line segment, clamped to the segment's ends so
    /// the band does not extend past them into open Map.
    private static func distance(from point: MapPoint,
                                 toSegment a: MapPoint, _ b: MapPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// The distance as the DM would say it.
    func readout(in unit: DistanceUnit) -> String {
        let measure = unit.format(squares: distance)
        switch shape {
        case .circle: return String(localized: "\(measure) radius")
        case .square: return String(localized: "\(measure) across")
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

    /// Where the live end of a chain currently reaches, in image pixels.
    ///
    /// Measured from the chain's anchor and using only the *live* segment's length —
    /// `distance` is the running total of the whole path, so projecting that from the
    /// anchor would shoot the rubber-band far past the cursor once a chain has more than
    /// one segment.
    func liveEnd(origin: MapPoint, pixelsPerSquare: CGFloat) -> MapPoint {
        let anchor = chainAnchor(origin: origin)
        let placed = chainSquares(from: origin, pixelsPerSquare: pixelsPerSquare)
        let live = max(0, distance - placed) * pixelsPerSquare
        return MapPoint(x: anchor.x + cos(direction) * live,
                        y: anchor.y + sin(direction) * live)
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
