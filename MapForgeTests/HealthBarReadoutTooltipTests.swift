import XCTest
@testable import MapForge

/// What the DM's row says the table is being shown of a Pawn's Health Bar (ADR-0036).
///
/// The row knows about the two switches that withhold a bar and nothing about whether the Pawn
/// itself is drawn — hidden, unlit, outside Solo Sight — which the eye and the Solo Sight
/// switch beside it already show. So a bar neither switch withholds must not be described as
/// one the table sees: a hidden Pawn's row said exactly that.
final class HealthBarReadoutTooltipTests: XCTestCase {
    func testABarNotWithheldIsDescribedWhereverTheTableCanSeeThePawn() {
        XCTAssertEqual(HealthBarReadout.tooltip(for: .healthy, withholding: nil),
                       "Wherever the table can see this Pawn, it sees this Health Bar — Healthy.")
        XCTAssertEqual(HealthBarReadout.tooltip(for: .bloodied, withholding: nil),
                       "Wherever the table can see this Pawn, it sees this Health Bar — Bloodied.")
        XCTAssertEqual(HealthBarReadout.tooltip(for: .critical, withholding: nil),
                       "Wherever the table can see this Pawn, it sees this Health Bar — Critical.")
    }

    func testAWithheldBarNamesTheSwitchWithholdingIt() {
        XCTAssertEqual(HealthBarReadout.tooltip(for: .healthy, withholding: .allBars),
                       "The table sees no Health Bars: the Health Bars switch is off.")
        XCTAssertEqual(HealthBarReadout.tooltip(for: .healthy, withholding: .thisPawn),
                       "The table does not see this Health Bar: it is withheld in Edit Pawn.")
    }
}
