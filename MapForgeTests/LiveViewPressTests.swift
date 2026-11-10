import XCTest
@testable import MapForge

/// One press of the primary button on the Live View, as the Selection's rules need it: is a
/// token's own drag under way, and is the release a click or the end of a drag?
///
/// The Map's tap and the drags under it all end on the same mouse-up, in an order SwiftUI
/// does not promise. These pin the rule that makes the order not matter: a drag's release
/// stays a drag's for the rest of that event, whichever handler hears it first.
@MainActor
final class LiveViewPressTests: XCTestCase {
    func testAPressThatHasNotMovedIsAClick() {
        let press = LiveViewPress()

        XCTAssertFalse(press.isTokenDragging)
        XCTAssertFalse(press.takeDragEnd())
    }

    /// The tap heard before the drag's end: the drag is still under way, so it is no click.
    func testATapHeardWhileTheDragIsUnderWayEndsTheDrag() {
        let press = LiveViewPress()
        press.dragged()

        XCTAssertTrue(press.takeDragEnd())
    }

    /// The tap heard after the drag's end, on the same mouse-up: still no click. Here the
    /// Selection carried by a member's drag, which went far enough to be a drag.
    func testATapHeardJustAfterTheDragEndedEndsTheDrag() {
        let press = LiveViewPress()
        press.tokenDragged()
        press.dragged()
        press.ended()

        XCTAssertFalse(press.isTokenDragging, "the token's drag is over")
        XCTAssertTrue(press.takeDragEnd())
    }

    /// A token's drag picks it up from its first point, but a point or two of wobble under a
    /// ⇧-click is still the ⇧-click: until the press goes as far as any drag must, its
    /// release is a click.
    func testATokenNudgedLessThanADragIsStillClicked() {
        let press = LiveViewPress()
        press.tokenDragged()
        press.ended()

        XCTAssertFalse(press.takeDragEnd())
    }

    /// Once the mouse-up has been handled, the next press starts clean: the click after a
    /// drag is a click.
    func testTheNextPressAfterADragIsAClickAgain() {
        let press = LiveViewPress()
        press.dragged()
        press.ended()

        spin()

        XCTAssertFalse(press.takeDragEnd())
    }

    /// A drag SwiftUI cancels never ends; the one click it can then swallow is the one that
    /// takes it, and the click after that is a click — and a rectangle may be drawn again.
    func testADragThatNeverEndedSwallowsOneClickAtMost() {
        let press = LiveViewPress()
        press.tokenDragged()
        press.dragged()

        XCTAssertTrue(press.takeDragEnd())
        XCTAssertFalse(press.takeDragEnd())
        XCTAssertFalse(press.isTokenDragging)
    }

    /// A token's own drag — a Pawn's, a Light Marker's, the Selection's — is reported for as
    /// long as it lasts, which the selection rectangle asks before drawing beside it.
    func testATokenDragIsUnderWayUntilItEnds() {
        let press = LiveViewPress()
        press.tokenDragged()

        XCTAssertTrue(press.isTokenDragging)
        press.ended()
        XCTAssertFalse(press.isTokenDragging)
    }

    /// Lets the run loop turn, running what `ended()` left for after this event.
    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
