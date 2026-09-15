import XCTest
@testable import MapForge

/// What the right-click menu offers for a given cursor.
///
/// Extracted after a defect the DM found: a Pawn standing inside a pinned Measurement made
/// "Unpin Measurement" unreachable, because the Pawn section suppressed the pin section
/// entirely. The two are independent — the menu is about everything under the cursor, not
/// the topmost thing only — and this is where that is now stated.
final class LiveMenuTests: XCTestCase {

    func testAPawnOffersEditAndDelete() {
        let menu = LiveMenu.items(target: .pawn(UUID()), measurement: nil,
                                  availability: .available)
        XCTAssertTrue(menu.editsTarget)
        XCTAssertEqual(menu.shapesOffered, true)
    }

    func testBareMapOffersOnlyTheShapes() {
        let menu = LiveMenu.items(target: nil, measurement: nil, availability: .available)
        XCTAssertFalse(menu.editsTarget)
        XCTAssertNil(menu.pin)
        XCTAssertTrue(menu.shapesOffered)
    }

    func testAMeasurementUnderTheCursorOffersPinInsteadOfTheShapes() {
        let menu = LiveMenu.items(target: nil, measurement: .live, availability: .available)
        XCTAssertEqual(menu.pin, .pin)
        XCTAssertFalse(menu.shapesOffered, "pin replaces the shape list")
    }

    /// The defect. A Pawn inside a pinned circle must offer **both** — the Pawn's own items
    /// and the unpin — or the Measurement can never be unpinned while anything stands on it.
    func testAPawnInsideAPinnedMeasurementOffersBoth() {
        let id = UUID()
        let menu = LiveMenu.items(target: .pawn(UUID()), measurement: .pinned(id),
                                  availability: .available)

        XCTAssertTrue(menu.editsTarget, "the Pawn lost its own items")
        XCTAssertEqual(menu.pin, .unpin(id), "the pinned Measurement could not be unpinned")
    }

    /// And a Light, which can equally stand inside one.
    func testALightInsideAPinnedMeasurementOffersBoth() {
        let id = UUID()
        let menu = LiveMenu.items(target: .light(UUID()), measurement: .pinned(id),
                                  availability: .available)
        XCTAssertTrue(menu.editsTarget)
        XCTAssertEqual(menu.pin, .unpin(id))
    }

    /// The refusal is shown wherever the DM clicked, so "why can I not measure" is answered
    /// over a Pawn as well as over bare Map.
    func testTheNoGridRefusalIsShownOverAPawnToo() {
        let menu = LiveMenu.items(target: .pawn(UUID()), measurement: nil,
                                  availability: .disabled(.noGrid))
        XCTAssertTrue(menu.editsTarget)
        XCTAssertFalse(menu.shapesOffered)
        XCTAssertEqual(menu.refusal, MeasurementControl.UnavailableReason.noGrid)
    }
}
