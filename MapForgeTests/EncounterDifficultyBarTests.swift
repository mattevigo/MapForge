import XCTest
@testable import MapForge

/// Where the Combat tab's bar puts the Encounter Difficulty: proportional to XP up to the
/// party's High budget, then a short fixed stub for whatever overspends it.
final class EncounterDifficultyBarTests: XCTestCase {
    private let party = EncounterDifficulty.Budgets(low: 600, moderate: 900, high: 1_600)

    func testTheMarksStandAtTheBudgetsAlongTheBar() {
        let layout = EncounterDifficultyBar.Layout(creatureXP: 650, budgets: party)
        XCTAssertEqual(layout.marks, [0.375, 0.5625, 1])
    }

    func testTheBarIsFilledToTheTotal() {
        let layout = EncounterDifficultyBar.Layout(creatureXP: 400, budgets: party)
        XCTAssertEqual(layout.fill, 0.25)
        XCTAssertFalse(layout.fillsBeyond)
    }

    func testTheMarksDependOnlyOnTheParty() {
        // Ticking a goblin in moves the fill, never the marks the DM reads it against.
        XCTAssertEqual(EncounterDifficultyBar.Layout(creatureXP: 50, budgets: party).marks,
                       EncounterDifficultyBar.Layout(creatureXP: 5_000, budgets: party).marks)
    }

    func testATotalThatSpendsTheWholeHighBudgetFillsTheBarAndNotTheStub() {
        let layout = EncounterDifficultyBar.Layout(creatureXP: 1_600, budgets: party)
        XCTAssertEqual(layout.fill, 1)
        XCTAssertFalse(layout.fillsBeyond)
    }

    func testATotalOverTheHighBudgetFillsTheStubAndNoFurther() {
        let layout = EncounterDifficultyBar.Layout(creatureXP: 9_000, budgets: party)
        XCTAssertEqual(layout.fill, 1, "the bar is never drawn longer than it is")
        XCTAssertTrue(layout.fillsBeyond)
    }
}
