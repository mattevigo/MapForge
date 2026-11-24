import XCTest
@testable import MapForge

/// Why the DM's row says the table cannot see a Pawn's Health Bar (ADR-0036).
///
/// The DM's Map never draws the bar, so the row is the only place the DM learns that the
/// table is being shown nothing — and the two switches that withhold it are set in different
/// places, so the row has to say which one to go and turn back on.
final class HealthBarWithholdingTests: XCTestCase {
    private let wounded = StatBlock(currentHP: 30, maxHP: 60)

    private var withheldInEditPawn: StatBlock {
        var block = wounded
        block.showsHealthBarToPlayers = false
        return block
    }

    func testABarNeitherSwitchWithholdsIsNotWithheld() {
        XCTAssertNil(PlayerVisibility.healthBarWithholding(stats: wounded, areHealthBarsOn: true))
    }

    func testABarWithheldInEditPawnIsWithheldForThisPawn() {
        XCTAssertEqual(PlayerVisibility.healthBarWithholding(stats: withheldInEditPawn,
                                                             areHealthBarsOn: true),
                       .thisPawn)
    }

    func testSwitchingHealthBarsOffWithholdsEveryBar() {
        XCTAssertEqual(PlayerVisibility.healthBarWithholding(stats: wounded, areHealthBarsOn: false),
                       .allBars)
    }

    /// The evening's switch is named first: it is the one every row is saying at once, and
    /// turning it back on still leaves this Pawn's own setting to tell the DM about.
    func testWithBothOffTheRowNamesTheSwitchFirst() {
        XCTAssertEqual(PlayerVisibility.healthBarWithholding(stats: withheldInEditPawn,
                                                             areHealthBarsOn: false),
                       .allBars)
    }
}
