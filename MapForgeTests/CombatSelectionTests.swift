import XCTest
@testable import MapForge

/// What the Stat Block editor is pointed at when a fight ends.
///
/// A selection is a row in the Order. When the fight stops there is no Order to be a row of,
/// so there is nothing left for the selection to mean — and an editor still offering the last
/// Combatant's hit points under a heading that says the fight is over invites a DM to type
/// into numbers they did not choose.
final class CombatSelectionTests: XCTestCase {

    func testAnEndedEncounterLeavesNothingSelected() {
        XCTAssertNil(CombatSelectionPolicy.afterEncounterEnds(),
                     "there is no Order left to be a row of")
    }

    /// Clearing what is *pointed at* is not the same as clearing what it points *to*.
    /// `CONTEXT.md`'s **Encounter**: stopping a fight neither heals anyone nor clears their
    /// Conditions, and this must not be mistaken for doing either.
    func testClearingTheSelectionTouchesNoStatBlock() {
        var block = StatBlock()
        block.currentHP = 12
        block.conditions = [.prone]

        _ = CombatSelectionPolicy.afterEncounterEnds()

        XCTAssertEqual(block.currentHP, 12, "the state a party fought three Rounds to reach")
        XCTAssertEqual(block.conditions, Set([.prone]), "a fight ending is not a rest")
    }
}
