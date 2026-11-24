import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// The DM's Health Bar, in the Scene tab's Pawn rows and the Encounter tab's Order rows.
///
/// The Order row is already full at the live panel's fixed width — Initiative, a name, hit
/// points, armour class, Conditions and three buttons — and the name is the column that
/// gives way. So the bar must not cost the row a point of width: it sits under the numbers,
/// as wide as they are, and the column is exactly as wide as it was before there was a bar.
///
/// Measured against the real SwiftUI layout, because what is on screen is the defect.
@MainActor
final class HealthBarReadoutLayoutTests: XCTestCase {
    private func width(of view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }

    /// The hit point column as the Encounter tab drew it before this bar — the formatting
    /// the ticket keeps, written out once here as the baseline.
    private func columnAsItWas(current: Int, temporary: Int = 0, max: Int) -> some View {
        HStack(spacing: 1) {
            Text("\(current)")
            if temporary > 0 { Text("+\(temporary)") }
            Text("/\(max)")
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func readout(_ stats: StatBlock, kind: PawnKind = .creature,
                         areHealthBarsOn: Bool = true,
                         flagsIncompleteStatBlock: Bool = true) -> some View {
        HealthBarReadout(kind: kind, stats: stats, areHealthBarsOn: areHealthBarsOn,
                         flagsIncompleteStatBlock: flagsIncompleteStatBlock)
    }

    func testTheBarAddsNoWidthToTheHitPointColumn() {
        XCTAssertEqual(width(of: readout(StatBlock(currentHP: 30, maxHP: 60))),
                       width(of: columnAsItWas(current: 30, max: 60)), accuracy: 0.5)
    }

    func testNorWithTemporaryHitPoints() {
        XCTAssertEqual(width(of: readout(StatBlock(currentHP: 30, maxHP: 60, temporaryHP: 5))),
                       width(of: columnAsItWas(current: 30, temporary: 5, max: 60)), accuracy: 0.5)
    }

    /// The withheld bar is drawn faded rather than with a glyph beside it, so saying the
    /// table sees nothing does not cost the name column either.
    func testNorWhenTheBarIsWithheld() {
        XCTAssertEqual(width(of: readout(StatBlock(currentHP: 30, maxHP: 60), areHealthBarsOn: false)),
                       width(of: columnAsItWas(current: 30, max: 60)), accuracy: 0.5)
    }

    /// The bar sits under the numbers: it makes the row a little taller, never wider.
    func testTheBarSitsUnderTheNumbers() {
        let numbers = NSHostingView(rootView: columnAsItWas(current: 30, max: 60)).fittingSize.height
        let withBar = NSHostingView(rootView: readout(StatBlock(currentHP: 30, maxHP: 60)))
            .fittingSize.height

        XCTAssertGreaterThan(withBar, numbers)
        XCTAssertLessThanOrEqual(withBar, numbers + HealthBarReadout.barHeight + HealthBarReadout.barGap + 0.5)
    }

    /// A Treasure's row is unchanged: the numbers the Encounter tab always showed, and no
    /// bar, because a Treasure never carries one.
    func testATreasureKeepsItsNumbersAndGetsNoBar() {
        let treasure = NSHostingView(rootView: readout(StatBlock(currentHP: 30, maxHP: 60),
                                                       kind: .treasure)).fittingSize
        let asItWas = NSHostingView(rootView: columnAsItWas(current: 30, max: 60)).fittingSize

        XCTAssertEqual(treasure.width, asItWas.width, accuracy: 0.5)
        XCTAssertEqual(treasure.height, asItWas.height, accuracy: 0.5)
    }

    /// The Scene tab adds the numbers where they exist, and no new warning where they don't:
    /// the ⚠️ stays the Encounter tab's, where a missing number stops a fight.
    func testWithNoHitPointsAndNoFlagTheReadoutIsEmpty() {
        XCTAssertEqual(width(of: readout(StatBlock(), flagsIncompleteStatBlock: false)), 0)
    }

    func testWithNoHitPointsTheEncounterTabStillFlagsIt() {
        XCTAssertGreaterThan(width(of: readout(StatBlock())), 0)
    }
}
