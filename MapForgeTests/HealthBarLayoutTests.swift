import CoreGraphics
import XCTest
@testable import MapForge

/// Where the Player Display draws a Pawn's Health Bar, and how big (ADR-0036).
///
/// Geometry only — the view that paints it is a thin shell over these numbers — so the
/// promises the table relies on are pinned here: the bar spans the token's footprint, it
/// stays legible when the squares get small, and it sits under the token rather than on it.
final class HealthBarLayoutTests: XCTestCase {
    private let centre = CGPoint(x: 200, y: 300)

    func testTheBarIsAsWideAsTheTokensFootprint() {
        let frame = HealthBar.frame(below: centre, squareSide: 50, squaresAcross: 1)
        XCTAssertEqual(frame.width, 50)
    }

    func testABigPawnsBarSpansItsTwoSquares() {
        let frame = HealthBar.frame(below: centre, squareSide: 50, squaresAcross: 2)
        XCTAssertEqual(frame.width, 100)
    }

    /// A sixteenth of a square at a comfortable size: thin enough to read as a strip under the
    /// figure, thick enough to see the colour across a table.
    func testTheBarIsASixteenthOfASquareTall() {
        let frame = HealthBar.frame(below: centre, squareSide: 96, squaresAcross: 1)
        XCTAssertEqual(frame.height, 6)
    }

    /// Thickness follows ONE square, as a token's label does — a Big Pawn's bar is longer,
    /// not fatter, so an ogre does not look more wounded than the goblin beside it.
    func testABigPawnsBarIsNoTallerThanAnyOthers() {
        let small = HealthBar.frame(below: centre, squareSide: 96, squaresAcross: 1)
        let big = HealthBar.frame(below: centre, squareSide: 96, squaresAcross: 2)
        XCTAssertEqual(big.height, small.height)
    }

    /// Map Fit on a large Map, or a low-resolution screen, shrinks the squares to a dozen
    /// points (the Player Display's own floor). A sixteenth of that is a hairline the table
    /// cannot read a colour from, so the bar stops shrinking first.
    func testTheBarKeepsALegibleHeightWhenSquaresAreSmall() {
        let frame = HealthBar.frame(below: centre, squareSide: 12, squaresAcross: 1)
        XCTAssertEqual(frame.height, 4)
    }

    /// Under the token, never over it: the token must look the same on both screens, and a
    /// strip across the disc would cover the Face the table knows the Pawn by. A token
    /// centred at y 300, one 96 pt square across, ends at 348; the bar starts just after.
    func testTheBarSitsJustBelowTheToken() {
        let frame = HealthBar.frame(below: centre, squareSide: 96, squaresAcross: 1)
        XCTAssertEqual(frame.minY, 350)
        XCTAssertEqual(frame.midX, centre.x)
    }

    /// A Big Pawn's disc reaches a whole square further down, so its bar does too.
    func testABigPawnsBarSitsBelowItsLargerToken() {
        let frame = HealthBar.frame(below: centre, squareSide: 96, squaresAcross: 2)
        XCTAssertEqual(frame.minY, 398)
        XCTAssertEqual(frame.midX, centre.x)
    }

    /// The table's black frame is a point wide, but at the 4 pt floor it gives way, so the
    /// colour inside — the whole message — still outweighs it.
    func testTheTablesFrameNeverOutweighsTheColour() {
        XCTAssertEqual(HealthBarStrip.frameWidth(forHeight: 6), 1)
        XCTAssertEqual(HealthBarStrip.frameWidth(forHeight: HealthBar.minimumHeight), 4.0 / 6, accuracy: 0.001)
    }
}
