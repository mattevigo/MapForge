import XCTest
@testable import MapForge

final class ViewportMathTests: XCTestCase {

    /// Same fixture as ScaleMathTests: 100 ppi @2x → 50 points per inch.
    let display = DisplayMetrics(
        pixelSize: CGSize(width: 2000, height: 1200),
        physicalSizeMM: CGSize(width: 508, height: 304.8),
        backingScaleFactor: 2
    )

    func testVisibleMapInchesFromScreenSize() {
        // 1000×600 pt screen at 50 pt/inch shows 20×12 map inches at True Scale.
        let size = ScaleMath.visibleMapInches(display: display,
                                              screenSizePoints: CGSize(width: 1000, height: 600))
        XCTAssertEqual(size.width, 20, accuracy: 1e-9)
        XCTAssertEqual(size.height, 12, accuracy: 1e-9)
    }

    func testClampedViewportOriginStaysInsideMapBounds() {
        // 30×20 in map, 20×12 in viewport: origin range is [0,10]×[0,8].
        let vp = CGSize(width: 20, height: 12)
        let map = CGSize(width: 30, height: 20)
        let inside = ScaleMath.clampedViewportOrigin(desired: CGPoint(x: 5, y: 3), viewportSize: vp, mapSize: map)
        XCTAssertEqual(inside, CGPoint(x: 5, y: 3))
        let outside = ScaleMath.clampedViewportOrigin(desired: CGPoint(x: -2, y: 25), viewportSize: vp, mapSize: map)
        XCTAssertEqual(outside, CGPoint(x: 0, y: 8))
    }

    func testClampedViewportOriginCentersAxesWhereMapFits() {
        // 10×5 in map inside a 20×12 in viewport: both axes center (negative origin = letterbox).
        let origin = ScaleMath.clampedViewportOrigin(desired: CGPoint(x: 3, y: 3),
                                                     viewportSize: CGSize(width: 20, height: 12),
                                                     mapSize: CGSize(width: 10, height: 5))
        XCTAssertEqual(origin.x, -5, accuracy: 1e-9)
        XCTAssertEqual(origin.y, -3.5, accuracy: 1e-9)
    }

    func testTrueScaleFrameWithViewportOriginShiftsTheMap() {
        // 30×20 in map at 50 pt/inch, viewport origin (5,3) in → frame at (-250,-150), size unchanged.
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        let frame = ScaleMath.trueScaleFrame(map: map, display: display,
                                             screenSizePoints: CGSize(width: 1000, height: 600),
                                             viewportOriginInches: CGPoint(x: 5, y: 3))
        XCTAssertEqual(frame.origin.x, -250, accuracy: 1e-9)
        XCTAssertEqual(frame.origin.y, -150, accuracy: 1e-9)
        XCTAssertEqual(frame.width, 1500, accuracy: 1e-9)
        XCTAssertEqual(frame.height, 1000, accuracy: 1e-9)
    }

    func testResolvedViewportCombinesSizeAndClampedOrigin() {
        // 30×20 in map on the 20×12 in display, desired origin (50,-5) → clamped (10,0).
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        let viewport = ScaleMath.resolvedViewport(map: map, display: display,
                                                  screenSizePoints: CGSize(width: 1000, height: 600),
                                                  desiredOrigin: CGPoint(x: 50, y: -5))
        XCTAssertEqual(viewport.sizeInches.width, 20, accuracy: 1e-9)
        XCTAssertEqual(viewport.sizeInches.height, 12, accuracy: 1e-9)
        XCTAssertEqual(viewport.originInches.x, 10, accuracy: 1e-9)
        XCTAssertEqual(viewport.originInches.y, 0, accuracy: 1e-9)
    }

    func testViewportOriginDefaultsToCenteredWhenNoDesiredOrigin() {
        // 30×20 in map, 20×12 in viewport, no stored origin → centered at (5,4).
        let origin = ScaleMath.viewportOrigin(desired: nil,
                                              viewportSize: CGSize(width: 20, height: 12),
                                              mapSize: CGSize(width: 30, height: 20))
        XCTAssertEqual(origin.x, 5, accuracy: 1e-9)
        XCTAssertEqual(origin.y, 4, accuracy: 1e-9)
    }

    func testViewportRectInImagePixels() {
        // 3000 px / 30 in map → 100 px per map inch: origin (5,3) size 20×12 in → (500,300,2000,1200) px.
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        let rect = ViewportMath.viewportRectInImagePixels(originInches: CGPoint(x: 5, y: 3),
                                                          sizeInches: CGSize(width: 20, height: 12),
                                                          map: map)
        XCTAssertEqual(rect, CGRect(x: 500, y: 300, width: 2000, height: 1200))
    }

    func testMirrorViewportRectLetterboxesMismatchedContainer() {
        // 5:3 viewport region in a 500×400 container: scale 0.25 → 500×300, centered
        // vertically. Content outside this rect must be masked — players can't see it.
        let visible = ViewportMath.mirrorViewportRect(viewportRect: CGRect(x: 500, y: 300, width: 2000, height: 1200),
                                                      container: CGSize(width: 500, height: 400))
        XCTAssertEqual(visible, CGRect(x: 0, y: 50, width: 500, height: 300))
    }

    func testMirrorImageFramePositionsFullImageSoViewportFillsContainer() {
        // Viewport region (500,300,2000,1200) px shown in a 500×300 pt container:
        // scale 0.25, region fills the container exactly, so the 3000×2000 image
        // sits at (-125,-75) scaled to 750×500.
        let frame = ViewportMath.mirrorImageFrame(imagePixelSize: CGSize(width: 3000, height: 2000),
                                                  viewportRect: CGRect(x: 500, y: 300, width: 2000, height: 1200),
                                                  container: CGSize(width: 500, height: 300))
        XCTAssertEqual(frame, CGRect(x: -125, y: -75, width: 750, height: 500))
    }
}
