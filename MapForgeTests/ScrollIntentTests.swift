import XCTest
@testable import MapForge

/// What a scroll event asks of the Magnifier. A trackpad swipe and a mouse wheel arrive as
/// the same event, and they mean different things: fingers on glass expect the artwork to
/// follow them, a wheel expects to zoom. See `CONTEXT.md`, **Magnifier**.
final class ScrollIntentTests: XCTestCase {

    /// Two fingers on a trackpad — or a finger on a Magic Mouse — slide the artwork, on
    /// both axes, by exactly the distance the fingers travelled.
    func testATrackpadSwipePansOnBothAxes() {
        let intent = ScrollIntent(dx: 12, dy: -7, isPrecise: true, isCommandHeld: false)
        XCTAssertEqual(intent, ScrollIntent(zoom: 0, pan: CGSize(width: 12, height: -7)))
    }

    /// A mouse wheel zooms. Its deltas count lines, not points, so a notch is scaled up to
    /// the ten points a trackpad would travel for the same intent — one notch, one step.
    func testAWheelNotchZooms() {
        let intent = ScrollIntent(dx: 0, dy: 3, isPrecise: false, isCommandHeld: false)
        XCTAssertEqual(intent, ScrollIntent(zoom: 30, pan: .zero))
    }

    /// A wheel tilted sideways — or ⇧ + wheel, which macOS turns into one — pans, so a
    /// wheel can do both jobs without a modifier.
    func testAWheelTiltedSidewaysPans() {
        let intent = ScrollIntent(dx: -2, dy: 0, isPrecise: false, isCommandHeld: false)
        XCTAssertEqual(intent, ScrollIntent(zoom: 0, pan: CGSize(width: -20, height: 0)))
    }

    /// ⌘ turns any scroll into a zoom. It is the only way a Magic Mouse zooms at all — its
    /// surface scrolls like a trackpad, and it cannot pinch.
    func testCommandScrollZoomsOnAPreciseDevice() {
        let intent = ScrollIntent(dx: 4, dy: 9, isPrecise: true, isCommandHeld: true)
        XCTAssertEqual(intent, ScrollIntent(zoom: 9, pan: .zero))
    }

    /// And on a wheel, where it zooms exactly as the wheel alone would — the sideways
    /// component is dropped rather than panning under a zoom the DM asked for.
    func testCommandScrollOnAWheelOnlyZooms() {
        let intent = ScrollIntent(dx: 1, dy: 2, isPrecise: false, isCommandHeld: true)
        XCTAssertEqual(intent, ScrollIntent(zoom: 20, pan: .zero))
    }

    /// A wheel moved on both axes at once — a free-spinning or tilting wheel caught mid-
    /// tilt — does both jobs in the one event rather than dropping either.
    func testAWheelMovedOnBothAxesZoomsAndPans() {
        let intent = ScrollIntent(dx: 1, dy: -1, isPrecise: false, isCommandHeld: false)
        XCTAssertEqual(intent, ScrollIntent(zoom: -10, pan: CGSize(width: 10, height: 0)))
    }
}
