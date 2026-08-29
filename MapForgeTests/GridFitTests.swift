import XCTest
@testable import MapForge

final class GridFitTests: XCTestCase {

    func testFittedImageRectLetterboxesWideImageVertically() {
        // 3000×2000 px image aspect-fit in a 450×400 pt container → 450×300, centered vertically.
        let rect = GridFit.fittedImageRect(imagePixelSize: CGSize(width: 3000, height: 2000),
                                           container: CGSize(width: 450, height: 400))
        XCTAssertEqual(rect, CGRect(x: 0, y: 50, width: 450, height: 300))
    }

    func testSquaresWideDerivedFromDrawnSquare() {
        // Image 450 wide; drawn square spans 15 (same coordinate space) → 30 squares wide.
        XCTAssertEqual(GridFit.squaresWide(imageWidth: 450, squareSide: 15)!, 30, accuracy: 1e-9)
    }

    func testSnapSuggestionNearIntegerSuggestsIt() {
        XCTAssertEqual(GridFit.snapSuggestion(for: 29.9), 30)
    }

    func testSnapSuggestionFarFromIntegerSuggestsNothing() {
        // 7.6 is 5.3% away from 8 — outside the 5% tolerance.
        XCTAssertNil(GridFit.snapSuggestion(for: 7.6))
    }

    func testSnapSuggestionForExactIntegerSuggestsNothing() {
        // Already on the integer — a "Snap to 30?" affordance would be noise.
        XCTAssertNil(GridFit.snapSuggestion(for: 30))
    }

    func testSnapSuggestionThresholdIsAbsoluteNotRelative() {
        // 30.4 is only 1.3% from 30 relative to the value, but 0.4 squares off —
        // a relative threshold would keep the affordance permanently visible on large maps.
        XCTAssertNil(GridFit.snapSuggestion(for: 30.4))
    }

    func testSquaresWideFromDegenerateSquareIsNil() {
        XCTAssertNil(GridFit.squaresWide(imageWidth: 450, squareSide: 0))
    }

    func testSquareSideIsInverseOfSquaresWide() {
        // 3000 px wide map declared 30 squares wide → one square spans 100 px.
        XCTAssertEqual(GridFit.squareSide(imageWidth: 3000, squaresWide: 30)!, 100, accuracy: 1e-9)
        XCTAssertNil(GridFit.squareSide(imageWidth: 3000, squaresWide: 0))
    }
}
