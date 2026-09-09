import XCTest
@testable import MapForge

/// Whether the Solo Sight control is offered, and the reason when it is not.
///
/// Pure, like `FogInspectorRowHeight`, so a rule the DM meets mid-session is provable
/// without driving a window. Every disabled state must carry a reason: a control that is
/// simply inert teaches the DM nothing, and they are reading it in front of players.
final class SoloSightControlTests: XCTestCase {
    private func pawn(kind: PawnKind = .player, isHidden: Bool = false) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: "Ilyana", colorHex: "#FF0000",
             brightSquares: 6, kind: kind, isHidden: isHidden)
    }

    func testOfferedForAPartyPawn() {
        XCTAssertEqual(SoloSightControl.availability(for: pawn(), isFogOverlayOn: true,
                                                     hasDeclaredGrid: true),
                       .available)
    }

    func testAbsentForACreature() {
        // A Creature emits no Light, so isolating one shows a black Map. "What does the
        // dragon see" is a different feature.
        XCTAssertEqual(SoloSightControl.availability(for: pawn(kind: .creature),
                                                     isFogOverlayOn: true, hasDeclaredGrid: true),
                       .absent)
    }

    func testAbsentForATreasure() {
        XCTAssertEqual(SoloSightControl.availability(for: pawn(kind: .treasure),
                                                     isFogOverlayOn: true, hasDeclaredGrid: true),
                       .absent)
    }

    func testDisabledForAHiddenPawn() {
        // The eye's guarantee wins: Solo Sight does not silently un-hide. ADR 0004.
        XCTAssertEqual(SoloSightControl.availability(for: pawn(isHidden: true),
                                                     isFogOverlayOn: true, hasDeclaredGrid: true),
                       .disabled(.pawnIsHidden))
    }

    func testDisabledWithTheFogOverlayOff() {
        // The whole effect is the fog shrinking; with no fog there is nothing to shrink.
        XCTAssertEqual(SoloSightControl.availability(for: pawn(), isFogOverlayOn: false,
                                                     hasDeclaredGrid: true),
                       .disabled(.fogOverlayOff))
    }

    func testDisabledWithNoGridDeclared() {
        // Same reason the fog itself is inert without a Grid: sight radii are in squares.
        XCTAssertEqual(SoloSightControl.availability(for: pawn(), isFogOverlayOn: true,
                                                     hasDeclaredGrid: false),
                       .disabled(.noGrid))
    }

    func testHiddenBeatsTheOtherReasons() {
        // Reported in the order the DM can act on: showing the Pawn is the fix nearest to
        // hand, and it is the reason specific to the row they clicked.
        XCTAssertEqual(SoloSightControl.availability(for: pawn(isHidden: true),
                                                     isFogOverlayOn: false, hasDeclaredGrid: false),
                       .disabled(.pawnIsHidden))
    }

    func testEveryReasonExplainsItself() {
        for reason in SoloSightControl.UnavailableReason.allCases {
            XCTAssertFalse(reason.explanation.isEmpty, "\(reason) is inert with no reason")
        }
    }
}
