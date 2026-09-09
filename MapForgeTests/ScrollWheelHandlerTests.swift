import XCTest
import SwiftUI
@testable import MapForge

/// The scroll monitor installs its event closure once and never re-installs it. If that
/// closure captures the handler by value, it is frozen at the first render's state — and
/// for zoom that meant every scroll recomputing the scale from fit-to-window instead of
/// from the current zoom. Reported as "no zoom limit, and it resets when reached": a large
/// scroll delta clamped at 1:1, and the next small one dropped straight back near the floor.
final class ScrollWheelHandlerTests: XCTestCase {

    /// Stands in for the modifier's storage: what the monitor holds across renders.
    private final class Handler {
        var onScroll: (CGFloat) -> Void = { _ in }
    }

    func testTheMonitorSeesHandlersInstalledAfterItWasCreated() {
        let handler = Handler()
        // Installed once, as `start()` does, and never replaced.
        let monitor: (CGFloat) -> Void = { [handler] delta in handler.onScroll(delta) }

        var seen: [CGFloat] = []
        handler.onScroll = { seen.append($0 * 1) }
        monitor(1)

        // A later render replaces the closure. The monitor must pick it up.
        handler.onScroll = { seen.append($0 * 100) }
        monitor(1)

        XCTAssertEqual(seen, [1, 100], "the monitor kept calling the first render's closure")
    }

    /// The bug as the DM experienced it, at the arithmetic that produced the symptom:
    /// a handler frozen at the first transform recomputes from the floor every time.
    func testZoomingFromAStaleTransformProducesTheReportedSymptom() {
        let image = CGSize(width: 1802, height: 1336)
        let container = CGSize(width: 1196, height: 600)
        let fitted = PreviewTransform.fitted(imagePixelSize: image, container: container)

        func zoom(from base: PreviewTransform, delta: CGFloat) -> PreviewTransform {
            base.zoomed(to: base.scale * exp(delta * 0.01),
                        anchoringViewPoint: CGPoint(x: 826, y: 129), container: container)
        }

        // Stale: every event starts from `fitted`, exactly as the captured log showed
        // ("from=0.4491" on every line, whatever had just been stored).
        let staleBig = zoom(from: fitted, delta: 103)
        let staleSmall = zoom(from: fitted, delta: 13)
        XCTAssertEqual(staleBig.scale, PreviewTransform.maxScale, accuracy: 1e-4)
        XCTAssertLessThan(staleSmall.scale, staleBig.scale * 0.6,
                          "precondition: the stale path is what collapses the zoom")

        // Live: the same two events applied in sequence must never go backwards.
        var live = fitted
        live = zoom(from: live, delta: 103)
        let afterBig = live.scale
        live = zoom(from: live, delta: 13)
        XCTAssertGreaterThanOrEqual(live.scale, afterBig,
                                    "a zoom-in shrank the preview — the reported reset")
    }
}
