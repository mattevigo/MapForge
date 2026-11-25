import XCTest
@testable import MapForge

/// Whether a Pawn's Health Bar is drawn at the table (ADR-0036).
///
/// Tested through `PlayerVisibility` for the reason that type exists: what the players get
/// to see is the one thing in this app that must never be wrong by accident. Each test takes
/// a Pawn whose bar the table *would* see and turns off exactly one condition, so a rule
/// that forgot any one of them fails by name.
final class HealthBarVisibilityTests: XCTestCase {
    private let lit = MapPoint(x: 0, y: 0)
    private let dark = MapPoint(x: 5000, y: 5000)

    /// One region around the origin, so `lit` is lit and `dark` is not.
    private func litAroundOrigin() -> [LitRegion] {
        Visibility.compute(walls: [],
                           lights: [Light(at: MapPoint(x: 0, y: 0), brightSquares: 4)],
                           pixelsPerSquare: 10)
    }

    private func pawn(at point: MapPoint? = nil, kind: PawnKind = .creature,
                      isHidden: Bool = false) -> Pawn {
        Pawn(at: point ?? lit, label: "Ogre", colorHex: "#FF0000", brightSquares: 0,
             kind: kind, isHidden: isHidden)
    }

    private let wounded = StatBlock(currentHP: 30, maxHP: 59)

    private func shows(_ pawn: Pawn, stats: StatBlock?, solo: Pawn.ID? = nil,
                       areHealthBarsOn: Bool = true) -> Bool {
        PlayerVisibility.showsHealthBarToPlayers(pawn: pawn, stats: stats,
                                                 regions: litAroundOrigin(),
                                                 isFogOverlayOn: true, hasVisibility: true,
                                                 soloSightPawnID: solo,
                                                 areHealthBarsOn: areHealthBarsOn)
    }

    func testAVisibleWoundedCreatureShowsItsBar() {
        // The baseline every other test turns one thing off from.
        XCTAssertTrue(shows(pawn(), stats: wounded))
    }

    func testAHiddenPawnTakesItsBarWithIt() {
        XCTAssertFalse(shows(pawn(isHidden: true), stats: wounded))
    }

    func testAnUnlitCreatureTakesItsBarWithIt() {
        // A bar floating in the dark would give away the ambush the darkness is hiding.
        XCTAssertFalse(shows(pawn(at: dark), stats: wounded))
    }

    func testAPawnOutsideSoloSightTakesItsBarWithIt() {
        // Another party member around the corner is genuinely absent under Solo Sight, and
        // so is how hurt they are.
        let isolated = pawn(kind: .player)
        let elsewhere = pawn(at: dark, kind: .player)
        XCTAssertFalse(shows(elsewhere, stats: wounded, solo: isolated.id))
    }

    func testAPawnWithNoBarShowsNone() {
        XCTAssertFalse(shows(pawn(), stats: StatBlock(currentHP: nil, maxHP: 59)))
        XCTAssertFalse(shows(pawn(kind: .treasure), stats: wounded))
    }

    func testAPawnWithNoStatBlockShowsNone() {
        // No numbers at all is the same as no numbers typed: no bar rather than a guessed one.
        XCTAssertFalse(shows(pawn(), stats: nil))
    }

    func testThePawnsOwnSettingWithholdsIt() {
        var withheld = wounded
        withheld.showsHealthBarToPlayers = false
        XCTAssertFalse(shows(pawn(), stats: withheld))
    }

    func testTheTableWideSwitchWithholdsIt() {
        XCTAssertFalse(shows(pawn(), stats: wounded, areHealthBarsOn: false))
    }
}
