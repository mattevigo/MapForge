import XCTest
@testable import MapForge

/// Which Pawn the DM's pointer rests on in the Live View: the one whose token, as drawn, is
/// under it. That is what shows a Face's label, so the area that answers has to be the
/// token the DM sees — not a square of image pixels that, with no Grid declared, shrinks to
/// a speck at the centre of a large Map's token.
final class PawnHoverTests: XCTestCase {
    /// A 3000 × 2000 Map, 30 squares wide, drawn 600 points wide: one square is 20 points.
    private let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
    private let frame = CGRect(x: 0, y: 0, width: 600, height: 400)

    /// Drawn at (300, 200) in `frame`.
    private func pawn(kind: PawnKind = .creature, isBig: Bool = false,
                      at point: MapPoint = MapPoint(x: 1500, y: 1000)) -> Pawn {
        Pawn(at: point, label: "GG1", colorHex: "#FF0000", brightSquares: 6,
             kind: kind, isBig: isBig)
    }

    private func hovered(_ x: CGFloat, _ y: CGFloat, _ pawns: [Pawn],
                         frame: CGRect? = nil) -> Pawn.ID? {
        PawnLayer.pawnID(under: CGPoint(x: x, y: y), pawns: pawns, map: map,
                         frame: frame ?? self.frame)
    }

    func testThePointerOnATokensCentreRestsOnIt() {
        let goblin = pawn()

        XCTAssertEqual(hovered(300, 200, [goblin]), goblin.id)
    }

    func testTheWholeDrawnDiscAnswersNotOnlyItsCentre() {
        // 9 points out on a 20-point disc: well inside what the DM sees.
        let goblin = pawn()

        XCTAssertEqual(hovered(309, 200, [goblin]), goblin.id)
    }

    func testThePointerOffTheTokenRestsOnNothing() {
        XCTAssertNil(hovered(320, 200, [pawn()]))
    }

    func testADiscsCornerIsNotTheToken() {
        // Inside the 20-point square the disc sits in, but outside the disc itself.
        XCTAssertNil(hovered(308, 208, [pawn(kind: .creature)]))
    }

    func testATreasuresCornerIsTheToken() {
        // A Treasure is drawn as a square, so its corner is part of it.
        let chest = pawn(kind: .treasure)

        XCTAssertEqual(hovered(308, 208, [chest]), chest.id)
    }

    func testABigPawnAnswersAcrossItsWholeFootprint() {
        // 15 points out: beyond one square's disc, inside a Big Pawn's two.
        let ogre = pawn(isBig: true)

        XCTAssertEqual(hovered(315, 200, [ogre]), ogre.id)
    }

    func testATokenDrawnAtTheFloorAnswersAtTheFloor() {
        // 150 points wide makes a square 5 points, and the token is drawn at 12 instead.
        let small = CGRect(x: 0, y: 0, width: 150, height: 100)
        let goblin = pawn()

        XCTAssertEqual(hovered(80, 50, [goblin], frame: small), goblin.id)
    }

    func testOfTwoOverlappingTokensTheOneOnTopAnswers() {
        let under = pawn()
        let over = pawn(at: MapPoint(x: 1520, y: 1000))

        XCTAssertEqual(hovered(302, 200, [under, over]), over.id)
    }

    func testTheTokenIsFoundWhereverTheFrameSits() {
        // The layer's frame may not start at the origin; the token moves with it.
        let goblin = pawn()
        let shifted = CGRect(x: 100, y: 50, width: 600, height: 400)

        XCTAssertEqual(hovered(400, 250, [goblin], frame: shifted), goblin.id)
    }
}
