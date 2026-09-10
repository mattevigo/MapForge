import XCTest
@testable import MapForge

/// A Line is a polygonal chain: the DM clicks a run of points and reads how far the whole
/// path is, which is the movement question — "can I get there this turn" — rather than the
/// straight-line range question the other three shapes answer.
final class MeasurementChainTests: XCTestCase {
    private let pixelsPerSquare: CGFloat = 10

    private func line(_ vertices: [MapPoint], settled: Bool = false) -> MapForge.Measurement {
        var m = MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: .line,
                                     distance: 0, direction: 0)
        m.chain = vertices
        m.isDistanceSettled = settled
        return m
    }

    // MARK: Length

    func testAChainOfOneSegmentIsThatSegment() {
        let m = line([MapPoint(x: 30, y: 0)])
        XCTAssertEqual(m.chainSquares(from: MapPoint(x: 0, y: 0),
                                      pixelsPerSquare: pixelsPerSquare), 3, accuracy: 1e-9)
    }

    func testAChainSumsEverySegment() {
        // The whole point of a chain: a path around a corner is longer than the straight
        // line across it, and that difference is what the DM is asking about.
        let m = line([MapPoint(x: 30, y: 0), MapPoint(x: 30, y: 40)])
        XCTAssertEqual(m.chainSquares(from: MapPoint(x: 0, y: 0),
                                      pixelsPerSquare: pixelsPerSquare), 7, accuracy: 1e-9)
    }

    func testAnEmptyChainIsZero() {
        XCTAssertEqual(line([]).chainSquares(from: MapPoint(x: 0, y: 0),
                                             pixelsPerSquare: pixelsPerSquare), 0)
    }

    func testAChainIsNotSnapped() {
        // Unlike the radius shapes, a chain accumulates exact distances. Rounding every
        // vertex would compound the error along a long path, and the DM placed each point
        // deliberately.
        let m = line([MapPoint(x: 17, y: 0)])
        XCTAssertEqual(m.chainSquares(from: MapPoint(x: 0, y: 0),
                                      pixelsPerSquare: pixelsPerSquare), 1.7, accuracy: 1e-9)
    }

    func testTheReadoutIsTheRunningTotal() {
        // One number at the live end, answering "how far have I travelled".
        var m = line([MapPoint(x: 30, y: 0), MapPoint(x: 30, y: 40)])
        m.distance = m.chainSquares(from: MapPoint(x: 0, y: 0), pixelsPerSquare: pixelsPerSquare)
        XCTAssertEqual(m.readout(in: .metres), "10.5 m")
    }

    // MARK: Extending

    func testClickingExtendsTheChainRatherThanSettlingIt() {
        // The behaviour that separates a Line from the other three: a click adds a vertex
        // and the measurement carries on, where a Circle's click would settle it.
        let m = line([])
        let extended = m.extended(to: MapPoint(x: 30, y: 0))
        XCTAssertEqual(extended.chain, [MapPoint(x: 30, y: 0)])
        XCTAssertFalse(extended.isDistanceSettled)

        let twice = extended.extended(to: MapPoint(x: 30, y: 40))
        XCTAssertEqual(twice.chain.count, 2)
    }

    func testFinishingSettlesTheChainWithoutAddingAPoint() {
        // Right-click finishes: the cursor is freed and the chain stops following it, but
        // wherever the pointer happened to be is NOT a vertex the DM asked for.
        let m = line([MapPoint(x: 30, y: 0)])
        let finished = m.finished()
        XCTAssertEqual(finished.chain, [MapPoint(x: 30, y: 0)])
        XCTAssertTrue(finished.isDistanceSettled)
    }

    // MARK: Aiming

    func testTheLiveEndFollowsTheCursorFromTheLastVertex() {
        // The rubber-band runs from the last committed vertex, not from the Origin —
        // otherwise a chain's second segment would be drawn from the wrong place.
        let m = line([MapPoint(x: 30, y: 0)])
        XCTAssertEqual(m.chainAnchor(origin: MapPoint(x: 0, y: 0)), MapPoint(x: 30, y: 0))
    }

    func testAnEmptyChainAnchorsToTheOrigin() {
        XCTAssertEqual(line([]).chainAnchor(origin: MapPoint(x: 5, y: 5)), MapPoint(x: 5, y: 5))
    }

    func testAFinishedChainNoLongerFollowsTheCursor() {
        let m = line([MapPoint(x: 30, y: 0)], settled: true)
        let aimed = m.aimed(at: MapPoint(x: 500, y: 500), from: MapPoint(x: 0, y: 0),
                            pixelsPerSquare: pixelsPerSquare)
        XCTAssertEqual(aimed.distance, m.distance)
    }

    // MARK: The other shapes are unaffected

    func testARadiusShapeStillSettlesOnClickRatherThanExtending() {
        // Only a Line chains. A Circle's click still settles it, which is the behaviour
        // every other shape has had since the feature shipped.
        let circle = MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: .circle,
                                          distance: 4, direction: 0)
        XCTAssertEqual(circle.clicked()?.isDistanceSettled, true)
    }

    func testARadiusShapeStillSnaps() {
        let circle = MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)), shape: .circle,
                                          distance: 0, direction: 0)
        let aimed = circle.aimed(at: MapPoint(x: 43, y: 0), from: MapPoint(x: 0, y: 0),
                                 pixelsPerSquare: pixelsPerSquare)
        XCTAssertEqual(aimed.distance, 4, "radius shapes still round to whole squares")
    }
}
