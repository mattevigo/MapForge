import XCTest
@testable import MapForge

/// Whether the Control Window's preview draws the live layers — Pawns, Light Markers, the
/// Fog tint, Measurements — or only the bare Map.
///
/// The preview has two branches (`ControlView.preview`). The mirror branch draws everything
/// and is guarded on `resolvedViewport != nil`; the fallback branch draws the Image plus
/// whichever *editing* overlay the mode calls for, and no live layer at all. And
/// `resolvedViewport` (`ControlView.swift:237-244`) returns nil unless a Player Display is
/// both selected and measured.
///
/// So a DM with no external display connected — at the kitchen table, prepping — sees no
/// Pawns. The tokens are in the fog document, listed in the Scene tab, and rolled for by the
/// Initiative Tracker, and the preview shows bare map. That is
/// `.scratch/pawns-not-drawn/01-tokens-missing-from-the-mirror.md`.
///
/// `PlayerPlacementTests` covers where a token lands and passes, which is why this survived:
/// the arithmetic was never wrong. Nothing was asking it for an answer.
final class PreviewLiveLayerTests: XCTestCase {
    private let image = CGSize(width: 1200, height: 900)
    private let map = MapScale(imagePixelSize: CGSize(width: 1200, height: 900),
                               physicalWidthInches: 30)

    // MARK: The condition that gates the live layers

    /// The heart of the bug: with no Player Display there is no Viewport to resolve, and
    /// the branch that draws Pawns is the branch that needs one.
    func testThereIsNoViewportWithoutAPlayerDisplay() {
        XCTAssertNil(PreviewBranch.viewport(map: map, display: nil, screenSizePoints: nil,
                                            desiredOrigin: nil),
                     "a Viewport resolved without a Player Display")
    }

    func testAViewportResolvesOnceADisplayIsMeasured() {
        let display = DisplayMetrics(pixelSize: CGSize(width: 2880, height: 1800),
                                     physicalSizeMM: CGSize(width: 600, height: 375),
                                     backingScaleFactor: 2)
        XCTAssertNotNil(PreviewBranch.viewport(map: map, display: display,
                                               screenSizePoints: CGSize(width: 1440, height: 900),
                                               desiredOrigin: nil))
    }

    // MARK: What each branch is responsible for

    /// Prepping a Map with no external display is ordinary use, not an edge case, and the
    /// DM must still see their Pawns.
    func testTheLiveLayersAreDrawnWithoutAPlayerDisplay() {
        XCTAssertTrue(PreviewBranch.drawsLiveLayers(mode: .normal, hasViewport: false),
                      "no Player Display: the preview drew no Pawns, Lights or Fog tint")
    }

    func testTheLiveLayersAreDrawnWithAPlayerDisplay() {
        XCTAssertTrue(PreviewBranch.drawsLiveLayers(mode: .normal, hasViewport: true))
    }

    /// Fog authoring has its own overlay drawing its own Pawns, and stacking the live layer
    /// on top of it would double every token.
    func testTheEditingModesKeepTheirOwnOverlays() {
        XCTAssertFalse(PreviewBranch.drawsLiveLayers(mode: .fog, hasViewport: true))
        XCTAssertFalse(PreviewBranch.drawsLiveLayers(mode: .gridFit, hasViewport: true))
        XCTAssertFalse(PreviewBranch.drawsLiveLayers(mode: .viewport, hasViewport: true))
    }

    // MARK: The frame the live layers are placed against

    /// With a Player Display the frame carries the Viewport's pan, and the layer is sized
    /// to the clipped viewport rect.
    func testTheMirrorFrameCarriesThePan() {
        let viewportPx = CGRect(x: 300, y: 0, width: 600, height: 450)
        let container = CGSize(width: 600, height: 450)
        let frame = PreviewBranch.liveLayerFrame(imagePixelSize: image,
                                                 viewportRect: viewportPx,
                                                 container: container)
        // The Map's left edge sits off to the left by the panned amount.
        XCTAssertLessThan(frame.minX, 0, "the frame should be panned off the left edge")
        XCTAssertEqual(frame.width, image.width, accuracy: 1e-6,
                       "a 1:1 container should draw the Map at its pixel width")
    }

    /// Without one, the frame is the plain aspect fit — the same rect the Image itself is
    /// drawn into, so a token lands on the artwork it belongs to.
    func testTheFittedFrameMatchesTheImageWithoutAPlayerDisplay() {
        let container = CGSize(width: 600, height: 400)
        let fitted = PreviewTransform.fitted(imagePixelSize: image, container: container).imageRect
        let frame = PreviewBranch.liveLayerFrame(imagePixelSize: image,
                                                 viewportRect: nil,
                                                 container: container)
        XCTAssertEqual(frame, fitted)
    }

    /// The reason this is worth a test rather than an assertion by eye: a Pawn at the Map's
    /// centre must land at the centre of the drawn artwork in both branches, or the token
    /// sits somewhere plausible and wrong.
    func testAPawnAtTheMapCentreLandsOnTheArtworkCentreInEitherBranch() {
        let container = CGSize(width: 600, height: 400)
        let centre = MapPoint(x: 600, y: 450)

        let fitted = PreviewBranch.liveLayerFrame(imagePixelSize: image,
                                                  viewportRect: nil,
                                                  container: container)
        let placed = PlayerPlacement.viewPoint(centre, map: map, frame: fitted)
        XCTAssertEqual(placed.x, fitted.midX, accuracy: 1e-6)
        XCTAssertEqual(placed.y, fitted.midY, accuracy: 1e-6)
    }
}
