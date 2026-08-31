import XCTest
@testable import MapForge

final class PreviewTransformTests: XCTestCase {

    private let image = CGSize(width: 3000, height: 2000)
    private let container = CGSize(width: 450, height: 400)

    /// The fitted transform is the zoomed-out floor: 3000×2000 in 450×400 → scale 0.15.
    private func fitted() -> PreviewTransform {
        PreviewTransform.fitted(imagePixelSize: image, container: container)
    }

    // MARK: Fitted baseline

    func testFittedMatchesTheAspectFitRect() {
        // Same geometry Grid Fit used before zoom existed — the fitted transform is
        // the new initial state, so it must agree with GridFit.fittedImageRect exactly.
        let t = fitted()
        XCTAssertEqual(t.imageRect, GridFit.fittedImageRect(imagePixelSize: image, container: container))
        XCTAssertEqual(t.scale, 0.15, accuracy: 1e-9)
    }

    func testFittedCentersTheImageInTheContainer() {
        XCTAssertEqual(fitted().imageRect, CGRect(x: 0, y: 50, width: 450, height: 300))
    }

    // MARK: Round-tripping

    func testViewPointAndImagePointAreInverses() {
        let t = fitted().zoomed(to: 0.6, anchoringViewPoint: CGPoint(x: 200, y: 180), container: container)
        let imagePoint = CGPoint(x: 1234, y: 567)
        let round = t.imagePoint(from: t.viewPoint(from: imagePoint))
        XCTAssertEqual(round.x, imagePoint.x, accuracy: 1e-6)
        XCTAssertEqual(round.y, imagePoint.y, accuracy: 1e-6)
    }

    func testViewRectOfSquareScalesAndOffsets() {
        // A 100 px square centered at (150, 150) at scale 0.15 → 15 pt at view (15, 65).
        let r = fitted().viewRect(ofSquareCenteredAt: CGPoint(x: 150, y: 150), side: 100)
        XCTAssertEqual(r, CGRect(x: 15, y: 65, width: 15, height: 15))
    }

    // MARK: Cursor-anchored zoom

    func testZoomKeepsTheImagePointUnderTheCursorFixed() {
        // The whole promise of cursor-anchored zoom: whatever artwork was under the
        // pointer is still under the pointer afterwards.
        let cursor = CGPoint(x: 310, y: 220)
        let before = fitted()
        let imageUnderCursor = before.imagePoint(from: cursor)
        let after = before.zoomed(to: 0.75, anchoringViewPoint: cursor, container: container)
        let moved = after.viewPoint(from: imageUnderCursor)
        XCTAssertEqual(moved.x, cursor.x, accuracy: 1e-6)
        XCTAssertEqual(moved.y, cursor.y, accuracy: 1e-6)
    }

    func testZoomingInThenBackOutReturnsToTheFittedTransform() {
        let cursor = CGPoint(x: 120, y: 240)
        let t = fitted()
            .zoomed(to: 0.9, anchoringViewPoint: cursor, container: container)
            .zoomed(to: 0.15, anchoringViewPoint: cursor, container: container)
        XCTAssertEqual(t.scale, fitted().scale, accuracy: 1e-9)
        XCTAssertEqual(t.imageRect.minX, fitted().imageRect.minX, accuracy: 1e-6)
        XCTAssertEqual(t.imageRect.minY, fitted().imageRect.minY, accuracy: 1e-6)
    }

    // MARK: Zoom limits

    func testZoomCannotGoBelowFitToWindow() {
        // The floor is the whole map: zooming out past it would letterbox pointlessly.
        let t = fitted().zoomed(to: 0.01, anchoringViewPoint: CGPoint(x: 225, y: 200), container: container)
        XCTAssertEqual(t.scale, fitted().scale, accuracy: 1e-9)
    }

    func testZoomCannotExceedOneToOne() {
        // 1 image px = 1 preview pt is the ceiling; past it there is no more
        // precision to extract, since the fit square is stored in image pixels.
        let t = fitted().zoomed(to: 8, anchoringViewPoint: CGPoint(x: 225, y: 200), container: container)
        XCTAssertEqual(t.scale, 1, accuracy: 1e-9)
    }

    func testATallImageInAWideContainerStillFloorsAtFitToWindow() {
        // Floor is min(...) on the constraining axis — here height, not width.
        let tall = CGSize(width: 1000, height: 4000)
        let t = PreviewTransform.fitted(imagePixelSize: tall, container: container)
        XCTAssertEqual(t.scale, 0.1, accuracy: 1e-9)
        XCTAssertEqual(t.zoomed(to: 0.02, anchoringViewPoint: .zero, container: container).scale,
                       0.1, accuracy: 1e-9)
    }

    func testAnImageSmallerThanTheContainerNeverZoomsOutBelowOneToOne() {
        // Fit scale would be >1 here; clamping the ceiling to 1 must not invert the
        // range and strand the transform with min > max.
        let small = CGSize(width: 100, height: 80)
        let t = PreviewTransform.fitted(imagePixelSize: small, container: container)
        XCTAssertEqual(t.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(t.zoomed(to: 4, anchoringViewPoint: .zero, container: container).scale,
                       1, accuracy: 1e-9)
        XCTAssertEqual(t.zoomed(to: 0.1, anchoringViewPoint: .zero, container: container).scale,
                       1, accuracy: 1e-9)
    }

    // MARK: Panning

    func testPanningOffsetsTheImageRect() {
        let t = fitted()
            .zoomed(to: 0.5, anchoringViewPoint: CGPoint(x: 225, y: 200), container: container)
        let panned = t.panned(by: CGSize(width: 30, height: -20), container: container)
        XCTAssertEqual(panned.imageRect.minX, t.imageRect.minX + 30, accuracy: 1e-6)
        XCTAssertEqual(panned.imageRect.minY, t.imageRect.minY - 20, accuracy: 1e-6)
        XCTAssertEqual(panned.scale, t.scale, accuracy: 1e-9)
    }

    func testPanningCannotPullTheImageEdgeInsideTheContainer() {
        // Zoomed in, the image covers the container on both axes; dragging must never
        // expose dead space at an edge.
        let t = fitted()
            .zoomed(to: 1, anchoringViewPoint: CGPoint(x: 225, y: 200), container: container)
            .panned(by: CGSize(width: 10_000, height: 10_000), container: container)
        XCTAssertLessThanOrEqual(t.imageRect.minX, 0)
        XCTAssertLessThanOrEqual(t.imageRect.minY, 0)
        XCTAssertGreaterThanOrEqual(t.imageRect.maxX, container.width)
        XCTAssertGreaterThanOrEqual(t.imageRect.maxY, container.height)
    }

    func testAnAxisSmallerThanTheContainerStaysCentered() {
        // At fit scale the 3000×2000 map letterboxes vertically (300 pt in 400 pt).
        // That axis is not pannable — it stays centered, as it did before zoom.
        let t = fitted().panned(by: CGSize(width: 0, height: 120), container: container)
        XCTAssertEqual(t.imageRect.minY, 50, accuracy: 1e-6)
    }

    // MARK: Nudge step

    func testNudgeStepIsOnePreviewPointInImagePixels() {
        // Zoomed out at 0.15, one preview point is ~6.7 image px — the old behavior.
        XCTAssertEqual(fitted().nudgeStepImagePixels, 1 / 0.15, accuracy: 1e-6)
    }

    func testNudgeStepIsFlooredAtOneImagePixel() {
        // At 1:1 the raw step is exactly 1. It must never fall below that, or a
        // keypress would move the square by a sub-pixel amount and appear dead.
        let t = fitted().zoomed(to: 1, anchoringViewPoint: CGPoint(x: 225, y: 200), container: container)
        XCTAssertEqual(t.nudgeStepImagePixels, 1, accuracy: 1e-9)
    }
}
