import XCTest
@testable import MapForge

final class ScaleMathTests: XCTestCase {

    /// 2000×1200 px panel measuring 508×304.8 mm (20×12 in) → exactly 100 ppi; @2x → 50 points per inch.
    let display = DisplayMetrics(
        pixelSize: CGSize(width: 2000, height: 1200),
        physicalSizeMM: CGSize(width: 508, height: 304.8),
        backingScaleFactor: 2
    )

    func testPixelsPerInch() {
        XCTAssertEqual(display.pixelsPerInch.width, 100, accuracy: 1e-9)
        XCTAssertEqual(display.pixelsPerInch.height, 100, accuracy: 1e-9)
    }

    func testPointsPerInch() {
        XCTAssertEqual(display.pointsPerInch.width, 50, accuracy: 1e-9)
        XCTAssertEqual(display.pointsPerInch.height, 50, accuracy: 1e-9)
    }

    func testGridMapPhysicalSize() {
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        XCTAssertEqual(map.physicalWidthInches, 30, accuracy: 1e-9)
        XCTAssertEqual(map.physicalHeightInches, 20, accuracy: 1e-9)
    }

    func testDirectPhysicalWidthForGridlessMap() {
        let map = MapScale(imagePixelSize: CGSize(width: 1200, height: 600), physicalWidthInches: 24)
        XCTAssertEqual(map.physicalHeightInches, 12, accuracy: 1e-9)
    }

    func testTrueScaleFrameLargerThanScreenIsCenteredOverflowing() {
        // 30×20 in map → 1500×1000 pt; screen 1000×600 pt → centered, overflowing both axes.
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        let frame = ScaleMath.trueScaleFrame(map: map, display: display, screenSizePoints: CGSize(width: 1000, height: 600))
        assertEqual(frame, CGRect(x: -250, y: -200, width: 1500, height: 1000))
    }

    func testTrueScaleFrameSmallerThanScreenIsCenteredLetterboxed() {
        // 10×5 in map → 500×250 pt on a 1000×600 pt screen.
        let map = MapScale.grid(squaresWide: 10, imagePixelSize: CGSize(width: 1000, height: 500))
        let frame = ScaleMath.trueScaleFrame(map: map, display: display, screenSizePoints: CGSize(width: 1000, height: 600))
        assertEqual(frame, CGRect(x: 250, y: 175, width: 500, height: 250))
    }

    func testMapFitFrameIsTheWholeScreen() {
        let frame = ScaleMath.mapFitFrame(screenSizePoints: CGSize(width: 1000, height: 600))
        assertEqual(frame, CGRect(x: 0, y: 0, width: 1000, height: 600))
    }

    func testUnderMapFitAMapOfAnotherShapeStillGetsTheScreensExactSize() {
        // A tall 10×40 in Map on a wide 1000×600 pt screen: no letterbox and no crop. It is
        // stretched to the screen's exact size — distorted, as the DM accepted.
        let map = MapScale.grid(squaresWide: 10, imagePixelSize: CGSize(width: 500, height: 2000))
        let frame = ScaleMath.playerFrame(map: map, display: display,
                                          screenSizePoints: CGSize(width: 1000, height: 600),
                                          desiredViewportOrigin: CGPoint(x: 0, y: 7), isMapFitOn: true)
        assertEqual(frame, CGRect(x: 0, y: 0, width: 1000, height: 600))
    }

    func testWithMapFitOffThePlayerFrameIsTrueScaleAtTheViewport() {
        // The 30×20 in Map from the overflow case (1500×1000 pt), its Viewport moved to
        // 4 in right and 2 in down: the frame shifts 200 pt left and 100 pt up.
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        let frame = ScaleMath.playerFrame(map: map, display: display,
                                          screenSizePoints: CGSize(width: 1000, height: 600),
                                          desiredViewportOrigin: CGPoint(x: 4, y: 2), isMapFitOn: false)
        assertEqual(frame, CGRect(x: -200, y: -100, width: 1500, height: 1000))
    }

    func testCalibrationCorrectionScalesPointsPerInch() {
        // The display claims 508 mm but a ruler measured the 200 mm calibration bar as 190 mm on glass:
        // the display is smaller than claimed → more pixels per real inch.
        var corrected = display
        corrected.calibrationFactor = 190.0 / 200.0
        XCTAssertEqual(corrected.pixelsPerInch.width, 100 / 0.95, accuracy: 1e-9)
        XCTAssertEqual(corrected.pointsPerInch.width, 50 / 0.95, accuracy: 1e-9)
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, accuracy: CGFloat = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.origin.x, b.origin.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.origin.y, b.origin.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: accuracy, file: file, line: line)
    }
}
