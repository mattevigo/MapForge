import XCTest
import SwiftUI
@testable import MapForge

/// Changing mode must not change the preview's zoom.
///
/// Reported from real use twice, two symptoms of one defect. First: place a Pawn, click to
/// select it, and the map visibly jumps scale — "like the zoom is changing during the
/// selection". Then: press "Edit Fog…" and the map resizes, because the Wall Editor's hint
/// added rows the Live View did not have.
///
/// The cause is not in `PreviewTransform`'s arithmetic but in what it is measured *against*.
/// `ControlView` renders its chrome above the preview in the same `VStack`; anything there
/// that appears or vanishes steals height from the `GeometryReader`, and every transform
/// derived from it recomputes against a smaller container.
///
/// These tests pin the rule the fix relies on: the container the preview measures itself
/// against must not depend on the mode, or on anything else that changes mid-session.
final class PreviewContainerStabilityTests: XCTestCase {
    private let image = CGSize(width: 3000, height: 2000)

    /// The preview area in a Control Window whose height is the constraining axis. A
    /// width-constrained preview is accidentally immune, which is why the glitch is
    /// window-size dependent and easy to miss.
    private let previewWhenTall = CGSize(width: 640, height: 400)

    /// The premise: losing the hint row's height really does move the zoom, so reserving it
    /// is not cargo cult.
    func testLosingTheHintRowWouldMoveTheZoom() {
        let full = PreviewTransform.fitted(imagePixelSize: image, container: previewWhenTall)
        let shrunk = PreviewTransform.fitted(
            imagePixelSize: image,
            container: CGSize(width: previewWhenTall.width,
                              height: previewWhenTall.height - ControlView.modeHintRowHeight))

        XCTAssertNotEqual(full.scale, shrunk.scale, accuracy: 1e-9,
                          "the premise is wrong: losing \(ControlView.modeHintRowHeight) pt did not move the zoom")
    }

    /// The guard. Every mode reserves the same chrome, so the container is one value.
    func testThePreviewContainerIsTheSameInEveryMode() {
        let containers = [PreviewMode.normal, .gridFit, .fog].map {
            ControlView.previewContainer(geometry: previewWhenTall, mode: $0)
        }
        XCTAssertEqual(Set(containers.map(\.height)).count, 1,
                       "the preview container changed with the mode: \(containers)")
    }

    func testTheFittedZoomIsTheSameInEveryMode() {
        let scales = [PreviewMode.normal, .gridFit, .fog].map { mode -> CGFloat in
            let container = ControlView.previewContainer(geometry: previewWhenTall, mode: mode)
            return PreviewTransform.fitted(imagePixelSize: image, container: container).scale
        }
        for scale in scales {
            XCTAssertEqual(scale, scales[0], accuracy: 1e-9,
                           "entering a mode changed the zoom")
        }
    }

    /// The zoomed-in case. `settled(in:)` re-clamps the origin against the container, so a
    /// changing container slides a zoomed preview sideways even where the scale is capped.
    func testEnteringAModeDoesNotPanAZoomedPreview() {
        let container = ControlView.previewContainer(geometry: previewWhenTall, mode: .normal)
        let zoomed = PreviewTransform.fitted(imagePixelSize: image, container: container)
            .zoomed(to: 0.5,
                    anchoringViewPoint: CGPoint(x: container.width / 2, y: container.height / 2),
                    container: container)

        let afterEnteringFog = ControlView.previewContainer(geometry: previewWhenTall, mode: .fog)
        let resettled = zoomed.panned(by: CGSize.zero, container: afterEnteringFog)

        XCTAssertEqual(resettled.scale, zoomed.scale, accuracy: 1e-9)
        XCTAssertEqual(resettled.origin.x, zoomed.origin.x, accuracy: 1e-9,
                       "entering a mode panned the zoomed preview horizontally")
        XCTAssertEqual(resettled.origin.y, zoomed.origin.y, accuracy: 1e-9,
                       "entering a mode panned the zoomed preview vertically")
    }

    /// The chrome is reserved above the preview, so the `GeometryReader`'s size already
    /// excludes it — the preview must not subtract it a second time.
    func testTheChromeIsNotSubtractedTwice() {
        XCTAssertEqual(ControlView.previewContainer(geometry: previewWhenTall, mode: .fog),
                       previewWhenTall,
                       "the preview lost height to a row already accounted for")
    }
}
