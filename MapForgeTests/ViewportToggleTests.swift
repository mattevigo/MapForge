import XCTest
@testable import MapForge

/// Showing the Viewport is a toggle on the Live View, not a mode.
///
/// The DM presses one button to see the rectangle and presses it again to put it away.
/// There is no Cancel and no Done, so there is no "in between" state to be stuck in — which
/// is the point: moving what the table sees is something a DM does mid-sentence, and a mode
/// with two exits is a thing to get wrong in front of players.
final class ViewportToggleTests: XCTestCase {

    /// The rectangle is **always** drawn on the Live View, toggle or no toggle: it is how
    /// the DM knows what the table is being shown, and that is not a question they should
    /// have to press a button to answer.
    func testTheRectangleIsAlwaysDrawnOnTheLiveView() {
        XCTAssertTrue(ViewportToggle.drawsRectangle(mode: .normal, hasViewport: true))
        XCTAssertFalse(ViewportToggle.drawsRectangle(mode: .normal, hasViewport: false),
                       "no Player Display means no Viewport to draw")
    }

    /// The authoring modes draw their own overlays and are not about the table's view.
    func testTheRectangleIsNotDrawnInTheAuthoringModes() {
        XCTAssertFalse(ViewportToggle.drawsRectangle(mode: .fog, hasViewport: true))
        XCTAssertFalse(ViewportToggle.drawsRectangle(mode: .gridFit, hasViewport: true))
    }

    /// The toggle decides **draggable**, not visible. Idle it is a readout; armed it is a
    /// control — and until it is armed it must not eat the clicks that drag a Pawn or open
    /// the right-click menu underneath it.
    func testTheToggleDecidesWhetherTheRectangleCanBeDragged() {
        XCTAssertFalse(ViewportToggle.isDraggable(isShowingViewport: false))
        XCTAssertTrue(ViewportToggle.isDraggable(isShowingViewport: true))
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
