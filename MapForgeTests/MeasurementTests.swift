import XCTest
@testable import MapForge

/// The geometry and unit conversion behind a Measurement.
///
/// These are the tests that matter most in the feature: a measuring tool that is subtly
/// wrong is worse than none, because the table trusts it. Each one states the *property*
/// being relied on rather than a vertex list, so a change of approximation does not
/// require rewriting the expectations.
final class MeasurementTests: XCTestCase {
    /// A convenient Grid: 10 pixels to a square keeps the arithmetic readable.
    private let pixelsPerSquare: CGFloat = 10

    private func project(_ shape: MeasurementShape, metres: CGFloat,
                         from origin: MapPoint = MapPoint(x: 100, y: 100),
                         towards direction: CGFloat = 0) -> MapForge.Polygon {
        let measurement = MapForge.Measurement(
            origin: .point(origin), shape: shape,
            distance: DistanceUnit.metres.squares(fromDisplay: metres),
            direction: direction)
        return measurement.project(pixelsPerSquare: pixelsPerSquare)
    }

    private func span(_ polygon: MapForge.Polygon) -> CGSize {
        let xs = polygon.vertices.map(\.x), ys = polygon.vertices.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGSize(width: maxX - minX, height: maxY - minY)
    }

    // MARK: Units

    func testOneSquareIsOneAndAHalfMetres() {
        // The metric DnD convention, and the only place the 1.5 is allowed to live.
        XCTAssertEqual(DistanceUnit.metres.display(fromSquares: 1), 1.5, accuracy: 1e-9)
        XCTAssertEqual(DistanceUnit.metres.display(fromSquares: 4), 6, accuracy: 1e-9)
    }

    func testDisplayAndSquaresRoundTrip() {
        // The guard against a hardcoded 1.5 appearing somewhere else: if any caller
        // converts by hand, one direction eventually stops matching the other.
        for metres in [1.5, 6, 9, 18, 22.5] as [CGFloat] {
            let squares = DistanceUnit.metres.squares(fromDisplay: metres)
            XCTAssertEqual(DistanceUnit.metres.display(fromSquares: squares), metres,
                           accuracy: 1e-9)
        }
    }

    // MARK: Circle — a radius

    func testCircleSpansTwiceItsDistance() {
        // 6 m radius is 12 m across: the radius reading this feature keeps.
        let polygon = project(.circle, metres: 6)
        let expected = 12 / 1.5 * pixelsPerSquare
        XCTAssertEqual(span(polygon).width, expected, accuracy: 0.5)
        XCTAssertEqual(span(polygon).height, expected, accuracy: 0.5)
    }

    func testCircleIsCentredOnItsOrigin() {
        let origin = MapPoint(x: 100, y: 100)
        let polygon = project(.circle, metres: 6, from: origin)
        for vertex in polygon.vertices {
            XCTAssertEqual(hypot(vertex.x - origin.x, vertex.y - origin.y),
                           6 / 1.5 * pixelsPerSquare, accuracy: 0.5)
        }
    }

    // MARK: Square — a side length

    func testSquareSpansItsDistanceNotTwiceIt() {
        // The regression this decision exists to prevent. A spell card says "a 20-foot
        // cube", so 6 m must give a 6 m box — reading it as a radius quadruples the area
        // the DM meant. See the spec and CONTEXT.md's Measurement Shape entry.
        let polygon = project(.square, metres: 6)
        let expected = 6 / 1.5 * pixelsPerSquare
        XCTAssertEqual(span(polygon).width, expected, accuracy: 1e-6)
        XCTAssertEqual(span(polygon).height, expected, accuracy: 1e-6)
    }

    func testSquareIsCentredOnItsOrigin() {
        let origin = MapPoint(x: 100, y: 100)
        let polygon = project(.square, metres: 6, from: origin)
        let half = 6 / 1.5 * pixelsPerSquare / 2
        XCTAssertEqual(span(polygon).width, half * 2, accuracy: 1e-6)
        for vertex in polygon.vertices {
            XCTAssertEqual(abs(vertex.x - origin.x), half, accuracy: 1e-6)
            XCTAssertEqual(abs(vertex.y - origin.y), half, accuracy: 1e-6)
        }
    }

    func testASquareAndACircleOfTheSameNumberDiffer() {
        // The pair that would silently agree if Square were read as a radius.
        XCTAssertNotEqual(span(project(.square, metres: 6)).width,
                          span(project(.circle, metres: 6)).width)
    }

    // MARK: Cone — the 5e rule

    func testAConeIsAsWideAtItsEndAsItIsLong() {
        // The defining 5e property, stated as the invariant rather than as an angle, so
        // the test still means something if the implementation changes how it sweeps.
        // A 90-degree grid-aligned cone would fail this, which is the point.
        let origin = MapPoint(x: 100, y: 100)
        let polygon = project(.cone, metres: 9, from: origin, towards: 0)
        let length = 9 / 1.5 * pixelsPerSquare

        // Aimed along +x, so the mouth is the vertices at the far end of the axis. An arc
        // far edge would fail this by about a tenth, which is what it is here to catch.
        let mouth = polygon.vertices.filter { $0.x - origin.x > length * 0.9 }
        XCTAssertEqual(mouth.count, 2, "a cone has two corners at its mouth")

        for corner in mouth {
            XCTAssertEqual(corner.x - origin.x, length, accuracy: 1e-6,
                           "the mouth sits one length along the axis")
        }
        let ys = mouth.map(\.y)
        XCTAssertEqual(ys.max()! - ys.min()!, length, accuracy: 1e-6)
    }

    func testAConeStartsAtItsOrigin() {
        let origin = MapPoint(x: 100, y: 100)
        let polygon = project(.cone, metres: 9, from: origin)
        XCTAssertTrue(polygon.vertices.contains { hypot($0.x - origin.x, $0.y - origin.y) < 1e-6 },
                      "the apex belongs on the Origin")
    }

    func testAConePointsWhereItIsAimed() {
        let origin = MapPoint(x: 100, y: 100)
        let east = project(.cone, metres: 9, from: origin, towards: 0)
        let south = project(.cone, metres: 9, from: origin, towards: .pi / 2)

        XCTAssertTrue(east.vertices.allSatisfy { $0.x >= origin.x - 1e-6 })
        XCTAssertTrue(south.vertices.allSatisfy { $0.y >= origin.y - 1e-6 })
    }

    // MARK: Line

    func testALineRunsFromTheOriginToItsDistance() {
        // With no vertices placed yet, a Line's live end is its whole length from the
        // Origin — the first segment of a chain that has not been extended.
        let origin = MapPoint(x: 100, y: 100)
        let measurement = MapForge.Measurement(origin: .point(origin), shape: .line,
                                      distance: DistanceUnit.metres.squares(fromDisplay: 9),
                                      direction: 0)
        let to = measurement.liveEnd(origin: origin, pixelsPerSquare: pixelsPerSquare)
        XCTAssertEqual(hypot(to.x - origin.x, to.y - origin.y),
                       9 / 1.5 * pixelsPerSquare, accuracy: 1e-6)
    }

    func testTheLiveEndOfAChainMeasuresOnlyItsOwnSegment() {
        // The trap `liveEnd` exists to avoid: `distance` is the running total, so
        // projecting it from the last vertex would shoot the rubber-band past the cursor
        // by everything already placed.
        let origin = MapPoint(x: 0, y: 0)
        var measurement = MapForge.Measurement(origin: .point(origin), shape: .line,
                                               distance: 0, direction: 0)
        measurement.chain = [MapPoint(x: 30, y: 0)]   // 3 squares placed
        measurement.distance = 5                      // plus a 2-square live segment
        let to = measurement.liveEnd(origin: origin, pixelsPerSquare: pixelsPerSquare)
        XCTAssertEqual(to.x, 50, accuracy: 1e-6)
        XCTAssertEqual(to.y, 0, accuracy: 1e-6)
    }

    // MARK: Readout

    func testTheReadoutNamesWhichKindOfDistanceItIs() {
        // "6 m radius" against "6 m across" is what makes Square-as-a-side-length safe:
        // the difference is read rather than assumed.
        let distance = DistanceUnit.metres.squares(fromDisplay: 6)
        func readout(_ shape: MeasurementShape) -> String {
            MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: shape,
                        distance: distance, direction: 0).readout(in: .metres)
        }
        XCTAssertEqual(readout(.circle), "6 m radius")
        XCTAssertEqual(readout(.square), "6 m across")
        XCTAssertEqual(readout(.cone), "6 m")
        XCTAssertEqual(readout(.line), "6 m")
    }

    func testTheReadoutSpeaksFeetAtATableThatDoes() {
        // Four squares: the book's 20 ft, never the tape measure's 19.7.
        func readout(_ shape: MeasurementShape) -> String {
            MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: shape,
                                 distance: 4, direction: 0).readout(in: .feet)
        }
        XCTAssertEqual(readout(.circle), "20 ft radius")
        XCTAssertEqual(readout(.square), "20 ft across")
        XCTAssertEqual(readout(.cone), "20 ft")
    }

    func testTheReadoutDropsATrailingZero() {
        // A DM reads "9 m", not "9.0 m"; but 7.5 m has to keep its half.
        let whole = MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: .line,
                                distance: DistanceUnit.metres.squares(fromDisplay: 9),
                                direction: 0)
        let half = MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: .line,
                               distance: DistanceUnit.metres.squares(fromDisplay: 7.5),
                               direction: 0)
        XCTAssertEqual(whole.readout(in: .metres), "9 m")
        XCTAssertEqual(half.readout(in: .metres), "7.5 m")
    }

    // MARK: Snapping

    func testSnappingLandsOnWholeSquares() {
        // Every DnD distance is a multiple of one square; nobody wants "8.7 m".
        XCTAssertEqual(MapForge.Measurement.snap(squares: 4.2), 4, accuracy: 1e-9)
        XCTAssertEqual(MapForge.Measurement.snap(squares: 4.6), 5, accuracy: 1e-9)
        XCTAssertEqual(MapForge.Measurement.snap(squares: 0.3), 0, accuracy: 1e-9)
    }

    func testSnappingNeverGoesNegative() {
        XCTAssertEqual(MapForge.Measurement.snap(squares: -3), 0, accuracy: 1e-9)
    }

    // MARK: Degenerate input

    func testAZeroDistanceProjectsNothing() {
        // The state between arming a Measurement and moving the mouse. It must draw
        // nothing rather than a degenerate sliver.
        for shape in MeasurementShape.allCases {
            XCTAssertTrue(project(shape, metres: 0).isEmpty,
                          "\(shape) should project nothing at zero")
        }
    }
}
