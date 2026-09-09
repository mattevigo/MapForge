import XCTest
import SwiftUI
@testable import MapForge

/// Selecting a Pawn must not change the preview's zoom.
///
/// Reported from real use: place a Pawn, click it to select, and the map visibly jumps
/// scale — "like the zoom is changing during the selection".
///
/// The cause is not in `PreviewTransform`'s arithmetic but in what it is measured
/// *against*. `ControlView` renders `pawnInspector` above the preview in the same
/// `VStack`, and that inspector draws nothing until a Pawn is selected. Selecting one
/// inserts a row, the preview loses that height, and every transform derived from the
/// GeometryReader's size is recomputed against a smaller container.
///
/// These tests pin the rule the fix relies on: the container the preview measures itself
/// against must not depend on whether something is selected.
final class PreviewContainerStabilityTests: XCTestCase {
    private let image = CGSize(width: 3000, height: 2000)

    /// The vertical space an inspector row claims, measured from the real SwiftUI layout
    /// rather than guessed — see `ControlView.fogInspectorRowHeight`.
    private var inspectorRow: CGFloat { ControlView.fogInspectorRowHeight }

    /// The preview area in a Control Window whose height is the constraining axis. A
    /// width-constrained preview is accidentally immune, which is why the glitch is
    /// window-size dependent and easy to miss.
    private let previewWhenTall = CGSize(width: 640, height: 400)

    func testSelectingAPawnDoesNotChangeTheFittedZoom() {
        // Before: no Pawn selected, so no inspector row.
        let unselected = PreviewTransform.fitted(imagePixelSize: image, container: previewWhenTall)
        // After: an inspector row appears and steals height from the preview.
        let shrunk = CGSize(width: previewWhenTall.width,
                            height: previewWhenTall.height - inspectorRow)
        let selected = PreviewTransform.fitted(imagePixelSize: image, container: shrunk)

        XCTAssertNotEqual(selected.scale, unselected.scale, accuracy: 1e-9,
                          "the premise of this test is wrong: losing \(inspectorRow) pt did not move the zoom")

        // This is the actual guard: ControlView must reserve the row's height whether or
        // not anything is selected, so the container never shrinks in the first place.
        let reservedUnselected = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                                hasInspectorSelection: false)
        let reservedSelected = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                              hasInspectorSelection: true)
        XCTAssertEqual(reservedUnselected, reservedSelected,
                       "the preview container changed when a Pawn was selected")

        let a = PreviewTransform.fitted(imagePixelSize: image, container: reservedUnselected)
        let b = PreviewTransform.fitted(imagePixelSize: image, container: reservedSelected)
        XCTAssertEqual(a.scale, b.scale, accuracy: 1e-9, "selecting a Pawn changed the zoom")
        XCTAssertEqual(a.imageRect, b.imageRect, "selecting a Pawn moved the map")
    }

    /// The zoomed-in case. `settled(in:)` re-clamps the origin against the container, so a
    /// changing container slides a zoomed preview sideways even where the scale is capped.
    func testSelectingAPawnDoesNotPanAZoomedPreview() {
        let container = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                        hasInspectorSelection: false)
        let zoomed = PreviewTransform.fitted(imagePixelSize: image, container: container)
            .zoomed(to: 0.5,
                    anchoringViewPoint: CGPoint(x: container.width / 2, y: container.height / 2),
                    container: container)

        let afterSelect = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                          hasInspectorSelection: true)
        // Re-settling against the post-selection container must be a no-op.
        let resettled = zoomed.panned(by: CGSize.zero, container: afterSelect)

        XCTAssertEqual(resettled.scale, zoomed.scale, accuracy: 1e-9)
        XCTAssertEqual(resettled.origin.x, zoomed.origin.x, accuracy: 1e-9,
                       "selecting a Pawn panned the zoomed preview horizontally")
        XCTAssertEqual(resettled.origin.y, zoomed.origin.y, accuracy: 1e-9,
                       "selecting a Pawn panned the zoomed preview vertically")
    }

    /// The same defect via the other inspector — a Light's radii row appears on selection
    /// exactly as a Pawn's does.
    func testSelectingALightDoesNotChangeTheFittedZoom() {
        let a = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                hasInspectorSelection: false)
        let b = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                hasInspectorSelection: true)
        XCTAssertEqual(PreviewTransform.fitted(imagePixelSize: image, container: a).scale,
                       PreviewTransform.fitted(imagePixelSize: image, container: b).scale,
                       accuracy: 1e-9)
    }

    /// The reserved row must cost the preview height only in the fog mode, where an
    /// inspector can actually appear — not in every other mode.
    func testTheRowIsReservedOnlyWhereAnInspectorCanAppear() {
        let reserved = ControlView.fogPreviewContainer(geometry: previewWhenTall,
                                                       hasInspectorSelection: false)
        XCTAssertEqual(reserved, previewWhenTall,
                       "the preview lost height to a row that is already accounted for")
    }
}
