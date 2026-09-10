import XCTest
@testable import MapForge

/// The token half of Solo Sight: who is drawn on the Player Display while one Pawn is
/// isolated. The lighting half is `VisibilityCacheTests`.
///
/// Tested through `PlayerVisibility` for the reason that type exists — what players do and
/// do not get to see is the one thing in this app that must never be wrong by accident,
/// and a window is not needed to prove it.
final class SoloSightTests: XCTestCase {
    private let bright = MapPoint(x: 0, y: 0)
    private let dark = MapPoint(x: 5000, y: 5000)

    /// One region around the origin, so `bright` is lit and `dark` is not.
    private func litAroundOrigin() -> [LitRegion] {
        Visibility.compute(walls: [],
                           lights: [Light(at: MapPoint(x: 0, y: 0), brightSquares: 4)],
                           pixelsPerSquare: 10)
    }

    private func pawn(at point: MapPoint, kind: PawnKind = .player,
                      isHidden: Bool = false) -> Pawn {
        Pawn(at: point, label: "P", colorHex: "#FF0000", brightSquares: 3,
             kind: kind, isHidden: isHidden)
    }

    private func shows(_ pawn: Pawn, solo: Pawn.ID?, regions: [LitRegion]) -> Bool {
        PlayerVisibility.showsToPlayers(pawn: pawn, regions: regions,
                                        isFogOverlayOn: true, hasVisibility: true,
                                        soloSightPawnID: solo)
    }

    // MARK: - The isolated Pawn is always drawn

    func testTheIsolatedPawnIsDrawnEvenInTheDark() {
        // A mode named after one Pawn where that Pawn can vanish is a bug report waiting
        // to happen. Issue 03, rule 2.
        let ilyana = pawn(at: dark)
        XCTAssertTrue(shows(ilyana, solo: ilyana.id, regions: litAroundOrigin()))
    }

    func testTheIsolatedPawnIsDrawnWithNoLightAtAll() {
        let ilyana = pawn(at: dark)
        XCTAssertTrue(shows(ilyana, solo: ilyana.id, regions: []))
    }

    // MARK: - Everyone else is discovered by light

    func testAnotherPartyPawnInTheDarkIsHiddenUnderSoloSight() {
        // The whole point of Q1=c: a party member around a corner is genuinely absent.
        let ilyana = pawn(at: bright)
        let bardo = pawn(at: dark)
        XCTAssertTrue(shows(bardo, solo: nil, regions: litAroundOrigin()),
                      "precondition: normally a party Pawn is always drawn")
        XCTAssertFalse(shows(bardo, solo: ilyana.id, regions: litAroundOrigin()))
    }

    func testAnotherPartyPawnInTheLightIsStillDrawn() {
        // Including light from the Map's own braziers, which Solo Sight never puts out.
        let ilyana = pawn(at: dark)
        let bardo = pawn(at: bright)
        XCTAssertTrue(shows(bardo, solo: ilyana.id, regions: litAroundOrigin()))
    }

    // MARK: - The eye still wins

    func testAHiddenPawnStaysHiddenUnderSoloSight() {
        let ilyana = pawn(at: bright)
        let ambusher = pawn(at: bright, isHidden: true)
        XCTAssertFalse(shows(ambusher, solo: ilyana.id, regions: litAroundOrigin()))
    }

    func testAHiddenIsolatedPawnIsStillHidden() {
        // Rule 1 beats even being the subject of the mode. ADR 0004: Solo Sight does not
        // silently un-hide, which is why the control is disabled on a hidden Pawn.
        let ilyana = pawn(at: bright, isHidden: true)
        XCTAssertFalse(shows(ilyana, solo: ilyana.id, regions: litAroundOrigin()))
    }

    // MARK: - Nothing changes when the mode is off

    func testWithNoIsolatedPawnPartyPawnsAreAlwaysDrawn() {
        let bardo = pawn(at: dark)
        XCTAssertTrue(shows(bardo, solo: nil, regions: litAroundOrigin()))
    }

    // MARK: - Creatures are unchanged

    func testACreatureInTheDarkIsHiddenWithOrWithoutSoloSight() {
        let ilyana = pawn(at: bright)
        let goblin = pawn(at: dark, kind: .creature)
        XCTAssertFalse(shows(goblin, solo: nil, regions: litAroundOrigin()))
        XCTAssertFalse(shows(goblin, solo: ilyana.id, regions: litAroundOrigin()))
    }

    func testACreatureInTheLightIsShownWithOrWithoutSoloSight() {
        let ilyana = pawn(at: dark)
        let goblin = pawn(at: bright, kind: .creature)
        XCTAssertTrue(shows(goblin, solo: nil, regions: litAroundOrigin()))
        XCTAssertTrue(shows(goblin, solo: ilyana.id, regions: litAroundOrigin()))
    }

    // MARK: - The DM keeps seeing everything

    func testTheDMSeesAPawnTheTableHasLostToSoloSight() {
        // Dimmed, never absent: a DM as blind as the players cannot run the game.
        let ilyana = pawn(at: bright)
        let bardo = pawn(at: dark)
        XCTAssertTrue(PlayerVisibility.isDimmedForDM(pawn: bardo, regions: litAroundOrigin(),
                                                     isFogOverlayOn: true, hasVisibility: true,
                                                     soloSightPawnID: ilyana.id),
                      "the DM lost sight of a Pawn the table cannot see")
    }

    func testTheIsolatedPawnIsNotDimmedForTheDM() {
        let ilyana = pawn(at: dark)
        XCTAssertFalse(PlayerVisibility.isDimmedForDM(pawn: ilyana, regions: litAroundOrigin(),
                                                      isFogOverlayOn: true, hasVisibility: true,
                                                      soloSightPawnID: ilyana.id))
    }

    // MARK: - Fog off

    func testWithTheFogOverlayOffEveryoneShows() {
        // There is no darkness to hide in, and a token nobody can explain reads as a bug.
        // This is also why the control is disabled with the Overlay off.
        let ilyana = pawn(at: bright)
        let bardo = pawn(at: dark)
        XCTAssertTrue(PlayerVisibility.showsToPlayers(pawn: bardo, regions: litAroundOrigin(),
                                                      isFogOverlayOn: false, hasVisibility: true,
                                                      soloSightPawnID: ilyana.id))
    }
}
