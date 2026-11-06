import XCTest
@testable import MapForge

/// Where a Pawn lands on the Player Display. Pawns live in image pixels; the Map is drawn
/// at True Scale in points — so a token that used the wrong mapping would sit somewhere
/// plausible but wrong, which is worse than obviously broken.
final class PlayerPlacementTests: XCTestCase {
    private let map = MapScale(imagePixelSize: CGSize(width: 3000, height: 2000),
                               physicalWidthInches: 30)

    func testAPointAtTheMapOriginLandsAtTheFrameOrigin() {
        let frame = CGRect(x: -100, y: -50, width: 900, height: 600)
        let placed = PlayerPlacement.viewPoint(MapPoint(x: 0, y: 0), map: map, frame: frame)
        XCTAssertEqual(placed.x, frame.minX, accuracy: 1e-9)
        XCTAssertEqual(placed.y, frame.minY, accuracy: 1e-9)
    }

    func testAPointAtTheMapCentreLandsAtTheFrameCentre() {
        let frame = CGRect(x: -100, y: -50, width: 900, height: 600)
        let placed = PlayerPlacement.viewPoint(MapPoint(x: 1500, y: 1000), map: map, frame: frame)
        XCTAssertEqual(placed.x, frame.midX, accuracy: 1e-9)
        XCTAssertEqual(placed.y, frame.midY, accuracy: 1e-9)
    }

    func testPlacementFollowsTheViewportAsItPans() {
        // Panning moves the Map's frame; a Pawn must travel with the artwork, not stay
        // put on the glass.
        let before = CGRect(x: 0, y: 0, width: 900, height: 600)
        let after = CGRect(x: -300, y: 0, width: 900, height: 600)
        let point = MapPoint(x: 1500, y: 1000)

        let a = PlayerPlacement.viewPoint(point, map: map, frame: before)
        let b = PlayerPlacement.viewPoint(point, map: map, frame: after)
        XCTAssertEqual(b.x - a.x, -300, accuracy: 1e-9, "the Pawn did not pan with the Map")
    }

    func testATokenIsSizedInGridSquares() {
        // "sized in Grid squares so a token reads as occupying its square": one square of
        // a 30-square-wide Map drawn 900 pt wide is 30 pt.
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        XCTAssertEqual(PlayerPlacement.squareSidePoints(map: map, frame: frame), 30,
                       accuracy: 1e-9)
    }

    func testTokenSizeShrinksWithTheMapWhenTheDisplayIsSmaller() {
        let frame = CGRect(x: 0, y: 0, width: 450, height: 300)
        XCTAssertEqual(PlayerPlacement.squareSidePoints(map: map, frame: frame), 15,
                       accuracy: 1e-9)
    }

    func testADegenerateMapDoesNotDivideByZero() {
        let empty = MapScale(imagePixelSize: .zero, physicalWidthInches: 0)
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        XCTAssertEqual(PlayerPlacement.viewPoint(MapPoint(x: 1, y: 1), map: empty, frame: frame),
                       CGPoint(x: frame.minX, y: frame.minY))
        XCTAssertEqual(PlayerPlacement.squareSidePoints(map: empty, frame: frame), 0)
        XCTAssertEqual(CGPoint(x: 1, y: 1).applying(PlayerPlacement.mapToView(map: empty, frame: frame)),
                       CGPoint(x: frame.minX, y: frame.minY))
    }

    // MARK: An uneven scale

    func testTheMapToViewTransformScalesEachAxisAsTheArtworkIs() {
        // A frame need not keep the Map's shape exactly: 3000×2000 px into
        // 1000×600 pt is a third across but three tenths down. A Light drawn through this
        // transform must reach as far as its polygon on both axes, so the transform has to
        // land a Light's rim exactly where `viewPoint` does — not where a single,
        // width-derived radius would.
        let frame = CGRect(x: 10, y: 20, width: 1000, height: 600)
        let transform = PlayerPlacement.mapToView(map: map, frame: frame)

        let centre = CGPoint(x: 1500, y: 1000).applying(transform)
        XCTAssertEqual(centre.x, 510, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 320, accuracy: 1e-9)

        // A 600 px reach: 200 pt across, 180 pt down.
        let rimAcross = CGPoint(x: 2100, y: 1000).applying(transform)
        let rimDown = CGPoint(x: 1500, y: 1600).applying(transform)
        XCTAssertEqual(rimAcross.x - centre.x, 200, accuracy: 1e-9)
        XCTAssertEqual(rimDown.y - centre.y, 180, accuracy: 1e-9)
    }

    // MARK: Drag round trip

    func testDraggingAPawnLandsItExactlyUnderTheCursor() {
        // PawnLayer converts a container-space translation back into image pixels. If that
        // inverse disagreed with `viewPoint` by even a little, a dragged token would drift
        // away from the cursor over a long drag — the class of bug issue 09 already cost a
        // round of work on.
        let frame = CGRect(x: -300, y: -100, width: 1800, height: 1200)
        let start = MapPoint(x: 500, y: 400)
        let translation = CGSize(width: 240, height: -90)

        // What PawnLayer computes.
        let moved = MapPoint(x: start.x + translation.width / frame.width * map.imagePixelSize.width,
                             y: start.y + translation.height / frame.height * map.imagePixelSize.height)

        // The token must now sit exactly where the cursor went.
        let before = PlayerPlacement.viewPoint(start, map: map, frame: frame)
        let after = PlayerPlacement.viewPoint(moved, map: map, frame: frame)
        XCTAssertEqual(after.x - before.x, translation.width, accuracy: 1e-9)
        XCTAssertEqual(after.y - before.y, translation.height, accuracy: 1e-9)
    }

    func testASequenceOfDragsDoesNotAccumulateDrift() {
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        var point = MapPoint(x: 100, y: 100)
        let origin = PlayerPlacement.viewPoint(point, map: map, frame: frame)

        // Twenty small drags, then back again: the token must return where it started.
        for _ in 0..<20 {
            point = MapPoint(x: point.x + 7 / frame.width * map.imagePixelSize.width,
                             y: point.y + 7 / frame.height * map.imagePixelSize.height)
        }
        for _ in 0..<20 {
            point = MapPoint(x: point.x - 7 / frame.width * map.imagePixelSize.width,
                             y: point.y - 7 / frame.height * map.imagePixelSize.height)
        }
        let ended = PlayerPlacement.viewPoint(point, map: map, frame: frame)
        XCTAssertEqual(ended.x, origin.x, accuracy: 1e-6)
        XCTAssertEqual(ended.y, origin.y, accuracy: 1e-6)
    }
}
