import XCTest
@testable import MapForge

/// Showing the Viewport is a toggle on the Live View, not a mode.
///
/// The DM presses one button to see the rectangle and presses it again to put it away.
/// There is no Cancel and no Done, so there is no "in between" state to be stuck in — which
/// is the point: moving what the table sees is something a DM does mid-sentence, and a mode
/// with two exits is a thing to get wrong in front of players.
final class ViewportToggleTests: XCTestCase {

    /// While the rectangle is showing, the preview pulls back to the whole Map — the DM has
    /// to see where they are dragging *to*, and on the mirror there is nothing outside the
    /// rectangle to drag toward.
    func testShowingTheViewportPullsBackToTheWholeMap() {
        XCTAssertFalse(ViewportToggle.showsWholeMap(isShowingViewport: false, mode: .normal))
        XCTAssertTrue(ViewportToggle.showsWholeMap(isShowingViewport: true, mode: .normal))
    }

    /// The authoring modes own the preview outright; the toggle does not reach into them.
    /// `.viewport` is not in this list because it no longer exists — panning became this
    /// toggle, which is the change that deleted the case.
    func testTheAuthoringModesAreUnaffected() {
        for mode in [PreviewMode.gridFit, .fog] {
            XCTAssertFalse(ViewportToggle.showsWholeMap(isShowingViewport: true, mode: mode),
                           "\(mode) is not the Live View's to change")
        }
    }

    /// The Magnifier and the rectangle both act on the Live View's preview, and only one of
    /// them is on screen at a time: showing the rectangle switches to the whole Map, where
    /// there is no mirror left to magnify. Leaving the Magnifier armed underneath would keep
    /// its "Zoomed" affordance up over a view it is not affecting.
    func testShowingTheViewportEndsTheMagnifier() {
        XCTAssertTrue(ViewportToggle.endsMagnifier(isShowingViewport: true))
        XCTAssertFalse(ViewportToggle.endsMagnifier(isShowingViewport: false))
    }

    /// Offered only when there is something to pan: a Map that fits inside the Viewport has
    /// no hidden part, so the rectangle would cover everything and move nowhere.
    func testItIsOfferedOnlyWhenTheMapOverflows() {
        XCTAssertTrue(ViewportToggle.isAvailable(mapOverflows: true, hasDisplay: true))
        XCTAssertFalse(ViewportToggle.isAvailable(mapOverflows: false, hasDisplay: true))
    }

    /// And only with a Player Display: without one there is no Viewport to move.
    func testItNeedsAPlayerDisplay() {
        XCTAssertFalse(ViewportToggle.isAvailable(mapOverflows: true, hasDisplay: false))
    }

    /// Unplugging mid-drag puts the rectangle away rather than leaving it over a preview
    /// that no longer mirrors anything — the same self-invalidation Solo Sight performs.
    func testUnpluggingTheDisplayPutsItAway() {
        XCTAssertFalse(ViewportToggle.staysShowing(mapOverflows: true, hasDisplay: false))
        XCTAssertTrue(ViewportToggle.staysShowing(mapOverflows: true, hasDisplay: true))
    }

    /// Declaring a Grid can shrink the Map below the Viewport while the rectangle is up.
    func testAMapThatStopsOverflowingPutsItAway() {
        XCTAssertFalse(ViewportToggle.staysShowing(mapOverflows: false, hasDisplay: true))
    }
}
