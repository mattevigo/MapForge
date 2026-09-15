import XCTest
@testable import MapForge

/// What the DM clicked on, in Map space.
///
/// The ordering is the whole point and is asserted rather than assumed: a Pawn *is* a Light,
/// so a Pawn's marker and its Light Marker sit on the same pixel, and the DM means the Pawn.
final class LiveHitTestTests: XCTestCase {
    private let gridPixels: CGFloat = 50

    private func pawn(at point: MapPoint, isBig: Bool = false) -> Pawn {
        Pawn(at: point, label: "1", colorHex: Pawn.defaultColorHex,
             brightSquares: 6, isBig: isBig)
    }

    // MARK: Nothing there

    func testAnEmptyMapHitsNothing() {
        XCTAssertNil(LiveHitTest.hit(at: MapPoint(x: 10, y: 10), pawns: [], lights: [],
                                     gridPixels: gridPixels))
    }

    func testAClickAwayFromEverythingHitsNothing() {
        let vex = pawn(at: MapPoint(x: 100, y: 100))
        XCTAssertNil(LiveHitTest.hit(at: MapPoint(x: 400, y: 400), pawns: [vex], lights: [],
                                     gridPixels: gridPixels))
    }

    // MARK: Pawns

    func testAClickOnAPawnHitsIt() {
        let vex = pawn(at: MapPoint(x: 100, y: 100))
        XCTAssertEqual(LiveHitTest.hit(at: MapPoint(x: 100, y: 100), pawns: [vex], lights: [],
                                       gridPixels: gridPixels), .pawn(vex.id))
    }

    /// A 1×1 Pawn occupies one Grid square, so its hit area is half a square from centre.
    func testAPawnIsHitAcrossItsSquareAndNotBeyond() {
        let vex = pawn(at: MapPoint(x: 100, y: 100))
        let inside = MapPoint(x: 100 + gridPixels / 2 - 2, y: 100)
        let outside = MapPoint(x: 100 + gridPixels / 2 + 2, y: 100)

        XCTAssertEqual(LiveHitTest.hit(at: inside, pawns: [vex], lights: [],
                                       gridPixels: gridPixels), .pawn(vex.id))
        XCTAssertNil(LiveHitTest.hit(at: outside, pawns: [vex], lights: [],
                                     gridPixels: gridPixels))
    }

    /// A Big Pawn occupies 2×2, so its hit area is a whole square from centre. Missing this
    /// would make the right-click menu unreachable over most of an ogre.
    func testABigPawnIsHitAcrossItsFullFootprint() {
        let ogre = pawn(at: MapPoint(x: 100, y: 100), isBig: true)
        let atTheEdge = MapPoint(x: 100 + gridPixels - 2, y: 100)

        XCTAssertEqual(LiveHitTest.hit(at: atTheEdge, pawns: [ogre], lights: [],
                                       gridPixels: gridPixels), .pawn(ogre.id))
    }

    /// The topmost Pawn wins, matching the draw order — the one the DM can see is the one
    /// they mean.
    func testTheLastPawnDrawnWinsAnOverlap() {
        let under = pawn(at: MapPoint(x: 100, y: 100))
        let over = pawn(at: MapPoint(x: 105, y: 100))

        XCTAssertEqual(LiveHitTest.hit(at: MapPoint(x: 102, y: 100),
                                       pawns: [under, over], lights: [],
                                       gridPixels: gridPixels), .pawn(over.id))
    }

    // MARK: Lights

    func testAClickOnALightMarkerHitsIt() {
        let torch = Light(at: MapPoint(x: 200, y: 200), brightSquares: 4, name: "Light 1")
        XCTAssertEqual(LiveHitTest.hit(at: MapPoint(x: 200, y: 200), pawns: [], lights: [torch],
                                       gridPixels: gridPixels), .light(torch.id))
    }

    /// The overlap that matters: a Pawn is also a Light, so a Pawn standing on a torch has
    /// both under the cursor. The Pawn is what the DM means.
    func testAPawnBeatsALightUnderTheSamePoint() {
        let vex = pawn(at: MapPoint(x: 100, y: 100))
        let torch = Light(at: MapPoint(x: 100, y: 100), brightSquares: 4, name: "Light 1")

        XCTAssertEqual(LiveHitTest.hit(at: MapPoint(x: 100, y: 100),
                                       pawns: [vex], lights: [torch],
                                       gridPixels: gridPixels), .pawn(vex.id))
    }

    // MARK: No declared Grid

    /// Without a Grid a token is drawn at a fixed size rather than a square's, so the hit
    /// area has to fall back too — not vanish. `Add` does not require a Grid (see the spec),
    /// so a Map can hold Pawns while `gridPixels` is nil, and they must stay clickable.
    func testPawnsAreStillHittableWithNoDeclaredGrid() {
        let vex = pawn(at: MapPoint(x: 100, y: 100))
        XCTAssertEqual(LiveHitTest.hit(at: MapPoint(x: 100, y: 100), pawns: [vex], lights: [],
                                       gridPixels: nil), .pawn(vex.id))
    }
}
