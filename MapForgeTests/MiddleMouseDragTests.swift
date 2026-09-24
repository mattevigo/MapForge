import XCTest
@testable import MapForge

/// The middle-button pan reads its translation from `NSEvent` locations, which are
/// y-up, and hands it to `PreviewTransform.panned`, which is y-down. The flip is the
/// one piece of arithmetic between the mouse and the Map.
final class MiddleMouseDragTests: XCTestCase {

    func testDraggingDownTheScreenIsAPositiveHeight() {
        // Window coordinates: y falls as the cursor moves down.
        let translation = MiddleMouseDragModifier.translation(from: CGPoint(x: 100, y: 300),
                                                              to: CGPoint(x: 130, y: 260))
        XCTAssertEqual(translation, CGSize(width: 30, height: 40))
    }

    func testTheMapFollowsTheHandAndStopsAtItsEdge() {
        let image = CGSize(width: 2000, height: 2000)
        let container = CGSize(width: 500, height: 500)
        let zoomed = PreviewTransform.fitted(imagePixelSize: image, container: container)
            .zoomed(to: 1, anchoringViewPoint: CGPoint(x: 250, y: 250), container: container)
        XCTAssertEqual(zoomed.origin, CGPoint(x: -750, y: -750))

        let nudged = zoomed.panned(
            by: MiddleMouseDragModifier.translation(from: CGPoint(x: 100, y: 300),
                                                    to: CGPoint(x: 130, y: 260)),
            container: container)
        XCTAssertEqual(nudged.origin, CGPoint(x: -720, y: -710))

        // Far past the top-left corner: the artwork's edge meets the preview's and stays.
        let hauled = zoomed.panned(
            by: MiddleMouseDragModifier.translation(from: .zero, to: CGPoint(x: 5000, y: -5000)),
            container: container)
        XCTAssertEqual(hauled.origin, .zero)
    }

    func testAtTheZoomFloorThereIsNothingToPan() {
        let container = CGSize(width: 500, height: 400)
        let fitted = PreviewTransform.fitted(imagePixelSize: CGSize(width: 2000, height: 2000),
                                             container: container)
        XCTAssertEqual(fitted.panned(by: CGSize(width: 80, height: -60), container: container),
                       fitted)
    }
}
