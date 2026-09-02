import XCTest
@testable import MapForge

final class WallSnapTests: XCTestCase {
    /// A tolerance of 10 image pixels stands in for "a few preview points" at 1:1.
    private let tolerance: CGFloat = 10

    // MARK: Endpoint snapping

    func testSnapsToANearbyWallEndpoint() {
        // The reason endpoint snapping exists: a chain that starts a hair off another
        // Wall's end leaves a hairline gap, and Light pours through it.
        let existing = [Wall(from: MapPoint(x: 100, y: 100), to: MapPoint(x: 200, y: 100))]
        let snapped = WallSnap.snap(MapPoint(x: 203, y: 104), to: WallSnap.endpoints(of: existing),
                                    tolerance: tolerance)
        XCTAssertEqual(snapped.point, MapPoint(x: 200, y: 100))
        XCTAssertEqual(snapped.target, .endpoint)
    }

    func testAnEndpointNearALatticeIntersectionStillWins() {
        // What used to be a priority question is now the only rule there is: a vertex
        // beside a lattice intersection AND beside a Wall end welds to the Wall end,
        // because that is the gap Light would pour through.
        let existing = [Wall(from: MapPoint(x: 103, y: 103), to: MapPoint(x: 200, y: 103))]
        let snapped = WallSnap.snap(MapPoint(x: 101, y: 101), to: WallSnap.endpoints(of: existing),
                                    tolerance: tolerance)
        XCTAssertEqual(snapped.point, MapPoint(x: 103, y: 103))
        XCTAssertEqual(snapped.target, .endpoint)
    }

    func testSnapsToTheNearestOfSeveralEndpoints() {
        let existing = [Wall(from: MapPoint(x: 100, y: 100), to: MapPoint(x: 108, y: 100))]
        let snapped = WallSnap.snap(MapPoint(x: 107, y: 101), to: WallSnap.endpoints(of: existing),
                                    tolerance: tolerance)
        XCTAssertEqual(snapped.point, MapPoint(x: 108, y: 100))
    }

    func testAFarEndpointDoesNotPull() {
        // Snapping must not reach across the map — a vertex the DM placed deliberately
        // in open space has to stay where they put it.
        let existing = [Wall(from: MapPoint(x: 100, y: 100), to: MapPoint(x: 200, y: 100))]
        let snapped = WallSnap.snap(MapPoint(x: 400, y: 400), to: WallSnap.endpoints(of: existing),
                                    tolerance: tolerance)
        XCTAssertEqual(snapped.point, MapPoint(x: 400, y: 400))
        XCTAssertEqual(snapped.target, .none)
    }

    // MARK: No Grid snapping

    func testAVertexIsNotPulledOntoTheGrid() {
        // The DM said "never". A vertex a hair off a lattice intersection stays where it
        // was clicked — geometry is welded to the artwork, not to a lattice.
        let snapped = WallSnap.snap(MapPoint(x: 148, y: 103), to: [], tolerance: tolerance)
        XCTAssertEqual(snapped.point, MapPoint(x: 148, y: 103))
        XCTAssertEqual(snapped.target, .none)
    }

    func testALightIsPlacedExactlyWhereItWasClicked() {
        // Lights went through the snap primitive with an empty candidate list, so the grid
        // branch was the only one that could fire on them. With that gone a Light is
        // placed raw — and this asserts the property rather than the absence of a call.
        let clicked = MapPoint(x: 148, y: 103)
        XCTAssertEqual(Light(at: clicked, brightSquares: 4).at, clicked)
    }

    func testAPawnIsPlacedExactlyWhereItWasClicked() {
        // Pawns never snapped, by an explicit decision — unasserted until now, which is
        // how a regression would have reached the table silently.
        let clicked = MapPoint(x: 148, y: 103)
        XCTAssertEqual(Pawn(at: clicked, label: "1", colorHex: Pawn.defaultColorHex,
                            brightSquares: 6).at, clicked)
    }

    // MARK: Angle constraint

    func testConstrainsToTheNearestEighthTurn() {
        // Most Walls on a battle map are axis-aligned, so the constraint is held by
        // default. 0/45/90/135 and their opposites.
        // Asserted as direction, not as a fixed point: the constraint preserves the
        // dragged length (see below), so a near-horizontal drag of length L lands at
        // x = 100 + L, slightly past the cursor's own x. That is intended.
        let from = MapPoint(x: 100, y: 100)
        let horizontal = WallSnap.constrainAngle(from: from, to: MapPoint(x: 200, y: 108))
        XCTAssertEqual(horizontal.y, 100, accuracy: 1e-6, "not horizontal")
        XCTAssertGreaterThan(horizontal.x, from.x, "horizontal but pointing the wrong way")

        let vertical = WallSnap.constrainAngle(from: from, to: MapPoint(x: 108, y: 200))
        XCTAssertEqual(vertical.x, 100, accuracy: 1e-6, "not vertical")
        XCTAssertGreaterThan(vertical.y, from.y, "vertical but pointing the wrong way")
    }

    func testConstrainsToADiagonal() {
        let constrained = WallSnap.constrainAngle(from: MapPoint(x: 0, y: 0),
                                                  to: MapPoint(x: 100, y: 96))
        XCTAssertEqual(constrained.x, constrained.y, accuracy: 1e-6, "not a 45° diagonal")
    }

    func testConstraintPreservesTheDraggedLength() {
        // Projecting onto the axis would shorten the span as the cursor drifts off it,
        // so the Wall would lag behind the pointer. Rotating keeps the length the DM
        // dragged and only corrects the direction.
        let from = MapPoint(x: 0, y: 0)
        let to = MapPoint(x: 100, y: 20)
        let constrained = WallSnap.constrainAngle(from: from, to: to)
        XCTAssertEqual(hypot(constrained.x, constrained.y),
                       hypot(to.x, to.y), accuracy: 1e-6)
    }

    func testAZeroLengthSpanIsLeftAlone() {
        // The instant a chain starts, before the cursor has moved: atan2(0,0) again.
        let point = MapPoint(x: 50, y: 50)
        XCTAssertEqual(WallSnap.constrainAngle(from: point, to: point), point)
    }
}
