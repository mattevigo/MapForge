import XCTest
@testable import MapForge

/// Zoom must be monotonic and must stop at its ceiling. Reported from real use: zooming
/// in kept going with no limit and then snapped back to zoomed-out.
final class PreviewZoomStabilityTests: XCTestCase {
    private let image = CGSize(width: 3000, height: 2000)
    private let container = CGSize(width: 450, height: 400)

    /// One scroll notch, as FogOverlay and GridFitOverlay compute it.
    private func zoomIn(_ transform: PreviewTransform, notches: CGFloat = 10) -> PreviewTransform {
        let sensitivity: CGFloat = 0.01
        return transform.zoomed(to: transform.scale * exp(notches * sensitivity),
                                anchoringViewPoint: CGPoint(x: 225, y: 200),
                                container: container)
    }

    func testRepeatedZoomInNeverShrinksThePreview() {
        // The reported symptom: keep scrolling in and the preview jumps back to
        // fit-to-window. Scale must never decrease across a zoom-in.
        var transform = PreviewTransform.fitted(imagePixelSize: image, container: container)
        for step in 1...200 {
            let next = zoomIn(transform)
            XCTAssertGreaterThanOrEqual(next.scale, transform.scale,
                                        "zoom \(step) shrank the preview: \(transform.scale) → \(next.scale)")
            transform = next
        }
    }

    func testZoomStopsAtItsCeilingRatherThanRunningOn() {
        var transform = PreviewTransform.fitted(imagePixelSize: image, container: container)
        for _ in 1...500 { transform = zoomIn(transform) }
        XCTAssertEqual(transform.scale, PreviewTransform.maxScale, accuracy: 1e-9,
                       "zoom ran past 1:1")
    }

    func testTheImageStillCoversThePreviewAtFullZoom() {
        // A transform that clamps its scale but not its origin leaves the image parked
        // off to one side, which reads as "it reset" just as much as a scale jump does.
        var transform = PreviewTransform.fitted(imagePixelSize: image, container: container)
        for _ in 1...500 { transform = zoomIn(transform) }

        let rect = transform.imageRect
        XCTAssertLessThanOrEqual(rect.minX, 0, "image left edge pulled inside the preview")
        XCTAssertGreaterThanOrEqual(rect.maxX, container.width, "gap at the right")
        XCTAssertLessThanOrEqual(rect.minY, 0, "image top edge pulled inside the preview")
        XCTAssertGreaterThanOrEqual(rect.maxY, container.height, "gap at the bottom")
    }

    func testZoomingInThenOutReturnsToTheFloorAndStops() {
        var transform = PreviewTransform.fitted(imagePixelSize: image, container: container)
        for _ in 1...50 { transform = zoomIn(transform) }
        for _ in 1...200 { transform = zoomIn(transform, notches: -10) }

        let floor = PreviewTransform.fitted(imagePixelSize: image, container: container).scale
        XCTAssertEqual(transform.scale, floor, accuracy: 1e-9, "zoom out overshot the floor")
    }

    /// A map already smaller than the preview: `fitted` pins it at 1:1, which is also the
    /// ceiling, so every zoom-in is a no-op — but it must be a *stable* no-op.
    func testASmallImageIsStableUnderRepeatedZoom() {
        let small = CGSize(width: 200, height: 150)
        var transform = PreviewTransform.fitted(imagePixelSize: small, container: container)
        let before = transform

        for _ in 1...20 { transform = zoomIn(transform) }
        XCTAssertEqual(transform.scale, before.scale, accuracy: 1e-9)
        XCTAssertEqual(transform.imageRect, before.imageRect, "a no-op zoom moved the image")
    }

    /// The zoom range is crossable in a sane number of scroll events.
    ///
    /// Not a restatement of the clamp: it is the arithmetic half of the reported symptom
    /// ("no zoom limit"). If a full sweep took hundreds of events the zoom would *feel*
    /// unbounded even with a correct ceiling, which is how the real defect presented.
    func testTheWholeZoomRangeIsCrossableInAReasonableNumberOfEvents() {
        var transform = PreviewTransform.fitted(imagePixelSize: image, container: container)
        var events = 0
        while transform.scale < PreviewTransform.maxScale - 1e-9, events < 1000 {
            transform = zoomIn(transform)
            events += 1
        }
        XCTAssertLessThan(events, 100, "a full zoom took \(events) scroll events")
        XCTAssertEqual(transform.scale, PreviewTransform.maxScale, accuracy: 1e-9)
    }
}

// NOTE ON COVERAGE — the actual defect has no unit-test seam.
//
// The report ("no zoom limit, then it resets") was not arithmetic: every test in this
// file passed against the broken build, and three separate hypotheses about
// PreviewTransform were wrong. The cause was in ControlView's layout — a GeometryReader
// wrapping an unconstrained ZStack that sized itself to the *zoomed* Image, so the
// reader measured the overflow and fed a growing container back into the next zoom.
//
// That is SwiftUI layout behaviour. It cannot be reproduced by calling PreviewTransform,
// which is why this file could not catch it, and it is not reachable from a unit test at
// all. The seam that would catch it is a UI test asserting the preview does not overflow
// its own frame — and MapForgeUITests does not run in the environment this was fixed in.
// Until it does, this fix is verified by reading the layout and by the loop in the
// scratchpad, not by a test.
