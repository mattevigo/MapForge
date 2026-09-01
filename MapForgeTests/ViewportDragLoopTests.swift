import XCTest
@testable import MapForge

/// Feedback loop for "Viewport drag is glitchy: it jumps back and drifts off the cursor".
///
/// Replays a drag through the EXACT production geometry chain, with no UI:
///   ViewportOverlay's onChanged formula  ->  appState.viewportOrigin
///   -> ScaleMath.resolvedViewport (clamp) -> back into ViewportOverlay.originInches
///
/// The overlay draws its rectangle from the CLAMPED origin fed back to it, so the
/// round trip is the thing under test, not either half alone.
final class ViewportDragLoopTests: XCTestCase {

    // 2000x1200 px panel, 20x12 in -> 100 ppi, @2x -> 50 pt/in. Screen 1000x600 pt
    // => the Viewport shows 20 x 12 map inches.
    let display = DisplayMetrics(pixelSize: CGSize(width: 2000, height: 1200),
                                 physicalSizeMM: CGSize(width: 508, height: 304.8),
                                 backingScaleFactor: 2)
    let screenPoints = CGSize(width: 1000, height: 600)
    // 60 in x 40 in map: overflows the 20x12 in Viewport on both axes, so there is
    // room to pan. Preview container 600x400 pt.
    let map = MapScale.grid(squaresWide: 60, imagePixelSize: CGSize(width: 3000, height: 2000))
    let container = CGSize(width: 600, height: 400)

    private var fittedRect: CGRect {
        PreviewTransform.fitted(imagePixelSize: map.imagePixelSize, container: container).imageRect
    }
    private var previewPointsPerMapInch: CGFloat {
        fittedRect.width / map.physicalWidthInches
    }

    private func viewport(desired: CGPoint?) -> Viewport {
        ScaleMath.resolvedViewport(map: map, display: display,
                                   screenSizePoints: screenPoints, desiredOrigin: desired)
    }

    /// The overlay rectangle's top-left in preview points, as ViewportOverlay.body draws it.
    private func rectOrigin(for originInches: CGPoint) -> CGPoint {
        let s = previewPointsPerMapInch
        return CGPoint(x: fittedRect.minX + originInches.x * s,
                       y: fittedRect.minY + originInches.y * s)
    }

    /// One simulated drag. `dragStartOrigin` is ViewportOverlay's @State; the harness
    /// models SwiftUI's DragGesture, which reports translation cumulative from the
    /// gesture's start location.
    /// Returns the drawn rectangle origin (preview points) after each tick.
    private func replayDrag(totalTranslation: CGSize, ticks: Int) -> [CGPoint] {
        var appStateOrigin: CGPoint? = nil          // AppState.viewportOrigin
        var dragStartOrigin: CGPoint? = nil         // ViewportOverlay @State
        var drawn: [CGPoint] = []

        for i in 1...ticks {
            let t = CGFloat(i) / CGFloat(ticks)
            let translation = CGSize(width: totalTranslation.width * t,
                                     height: totalTranslation.height * t)

            // --- what the overlay is currently showing (clamped, fed back) ---
            let shownOrigin = viewport(desired: appStateOrigin).originInches

            // --- ViewportOverlay.dragGesture.onChanged ---
            if dragStartOrigin == nil { dragStartOrigin = shownOrigin }
            let start = dragStartOrigin!
            let desired = CGPoint(x: start.x + translation.width / previewPointsPerMapInch,
                                  y: start.y + translation.height / previewPointsPerMapInch)

            // --- ControlView's callback ---
            appStateOrigin = desired

            // --- what gets drawn next frame ---
            drawn.append(rectOrigin(for: viewport(desired: appStateOrigin).originInches))
        }
        return drawn
    }

    /// THE SYMPTOM: the rectangle must stay glued to the cursor. Over a drag of
    /// `d` preview points, the rectangle must move exactly `d` preview points, and
    /// each tick must advance monotonically - no jumping back.
    func testRectangleTracksCursorOverAPlainDrag() {
        let startShown = rectOrigin(for: viewport(desired: nil).originInches)
        let drag = CGSize(width: 60, height: 40)   // preview points, well inside bounds
        let drawn = replayDrag(totalTranslation: drag, ticks: 20)

        // Total travel must equal the cursor's travel.
        let last = drawn.last!
        XCTAssertEqual(last.x - startShown.x, drag.width, accuracy: 0.01,
                       "rectangle drifted off the cursor horizontally")
        XCTAssertEqual(last.y - startShown.y, drag.height, accuracy: 0.01,
                       "rectangle drifted off the cursor vertically")

        // And it must never jump backwards mid-drag.
        for i in 1..<drawn.count {
            XCTAssertGreaterThanOrEqual(drawn[i].x, drawn[i-1].x - 0.001,
                                        "rectangle jumped back at tick \(i)")
        }
    }

    /// THE BUG, and the regression guard. Recorded from the running app via a
    /// trace of the live drag: the overlay rectangle is placed with `.position()` and
    /// carries the drag gesture itself, so with the DEFAULT coordinate space
    /// DragGesture measured translation in the *moving rectangle's* own space. Each
    /// point the rectangle moved was subtracted from the next event's translation:
    ///
    ///   reported tx: 18.75 → 4.92 → 18.96 → 10.17 → 24.38 → 12.47 → 27.59 → …
    ///
    /// for a cursor that only ever moved right. The rectangle visibly jumped back and
    /// drifted off the cursor. Naming a container-anchored space fixes it.
    ///
    /// The invariant: for a monotonic cursor path the drawn rectangle must never move
    /// backwards, and must land exactly under the cursor.
    func testMonotonicCursorPathNeverMovesTheRectangleBackwards() {
        let cursorPath: [CGFloat] = [4, 9, 15, 22, 30, 39, 49, 60, 72, 85]
        let startShown = rectOrigin(for: viewport(desired: nil).originInches).x

        var appStateOrigin: CGPoint? = nil
        var dragStartOrigin: CGPoint? = nil
        var drawnX: [CGFloat] = []

        for tx in cursorPath {
            let shown = viewport(desired: appStateOrigin).originInches
            if dragStartOrigin == nil { dragStartOrigin = shown }
            let start = dragStartOrigin!
            appStateOrigin = CGPoint(x: start.x + tx / previewPointsPerMapInch, y: start.y)
            drawnX.append(rectOrigin(for: viewport(desired: appStateOrigin).originInches).x)
        }

        for i in 1..<drawnX.count {
            XCTAssertGreaterThanOrEqual(
                drawnX[i], drawnX[i-1] - 0.001,
                "rectangle jumped BACK at tick \(i): \(drawnX[i-1]) -> \(drawnX[i])")
        }
        XCTAssertEqual(drawnX.last! - startShown, cursorPath.last!, accuracy: 0.01,
                       "rectangle did not land under the cursor")
    }

    /// Dragging into the clamp and back out must return the rectangle to where the
    /// cursor is - not leave it stuck or offset by the clamped amount.
    func testDragIntoClampAndBackReturnsToCursor() {
        var appStateOrigin: CGPoint? = nil
        var dragStartOrigin: CGPoint? = nil

        let startShown = rectOrigin(for: viewport(desired: nil).originInches)

        // Push hard left (past the clamp at 0), then come back to a net +40 pt right.
        let path: [CGSize] = [CGSize(width: -400, height: 0), CGSize(width: 40, height: 0)]
        var drawnLast = startShown
        for translation in path {
            let shown = viewport(desired: appStateOrigin).originInches
            if dragStartOrigin == nil { dragStartOrigin = shown }
            let start = dragStartOrigin!
            appStateOrigin = CGPoint(x: start.x + translation.width / previewPointsPerMapInch,
                                     y: start.y + translation.height / previewPointsPerMapInch)
            drawnLast = rectOrigin(for: viewport(desired: appStateOrigin).originInches)
        }

        XCTAssertEqual(drawnLast.x - startShown.x, 40, accuracy: 0.01,
                       "after overshooting the clamp and returning, rectangle is offset from the cursor")
    }
}
