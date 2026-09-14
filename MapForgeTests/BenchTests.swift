import XCTest
@testable import MapForge

/// Benching a Combatant and bringing it back.
///
/// A Pawn on the Map is either in the Order or Benched. See `CONTEXT.md`, **Benched**.
final class BenchTests: XCTestCase {
    private let grog = UUID()
    private let goblin = UUID()
    private let at = Date(timeIntervalSince1970: 1_757_600_000)

    private func roster() -> [EncounterControl.Entrant] {
        [
            .init(id: goblin, name: "Goblin", kind: .creature,
                  block: StatBlock(armorClass: 15, currentHP: 7, maxHP: 7)),
            .init(id: grog, name: "Grog", kind: .player,
                  block: StatBlock(armorClass: 16, currentHP: 26, maxHP: 26)),
        ]
    }

    /// The goblin rolls 12, Grog 18 — rolls are handed out in the order entrants are passed.
    private func started() -> Encounter {
        var generator = ScriptedGenerator(d20Rolls: [12, 18])
        return EncounterControl.start(roster(), at: at, using: &generator).encounter
    }

    // MARK: Benching

    func testBenchingTakesACombatantOutOfTheOrder() {
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)

        XCTAssertFalse(encounter.order.contains(goblin), "still in the Order")
        XCTAssertTrue(encounter.benched.contains(goblin))
    }

    func testABenchedCombatantTakesNoTurns() {
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)
        _ = EncounterControl.next(&encounter, at: at)

        XCTAssertEqual(encounter.activeCombatantID, grog, "the goblin should be skipped")
        XCTAssertEqual(encounter.round, 2, "one Combatant left, so the Round wraps")
    }

    func testBenchingTheActiveCombatantLeavesNextWorking() {
        var encounter = started()
        _ = EncounterControl.bench(grog, in: &encounter)

        XCTAssertEqual(encounter.activeCombatantID, goblin)
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, goblin)
    }

    func testTheLogStillNamesABenchedCombatant() {
        // A monster that died in Round 2 is part of what happened, whatever the tracker
        // shows now.
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)
        XCTAssertEqual(encounter.name(of: goblin), "Goblin")
        XCTAssertEqual(encounter.blocks[goblin]?.maxHP, 7)
    }

    func testBenchingKeepsTheStatBlockEditable() {
        // A dying Creature's hit points still matter: a DM heals it back and returns it.
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 3),
                                    in: &encounter)
        XCTAssertEqual(encounter.blocks[goblin]?.currentHP, 3)
    }

    func testBenchingSomebodyAlreadyBenchedChangesNothing() {
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)
        let after = encounter
        _ = EncounterControl.bench(goblin, in: &encounter)
        XCTAssertEqual(encounter.order, after.order)
        XCTAssertEqual(encounter.pendingChanges.count, after.pendingChanges.count)
    }

    // MARK: Returning

    func testReturningRollsAfreshAndRejoinsTheOrder() {
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)

        var generator = ScriptedGenerator(d20Rolls: [15])
        _ = EncounterControl.unbench(goblin, in: &encounter, using: &generator)

        XCTAssertTrue(encounter.order.contains(goblin))
        XCTAssertFalse(encounter.benched.contains(goblin))
        XCTAssertEqual(encounter.initiative(of: goblin), 15, "a fresh roll, not the old 12")
    }

    func testAReturningCombatantKeepsItsHitPoints() {
        // It is the same Creature: benching is not a reset.
        var encounter = started()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 2),
                                    in: &encounter)
        _ = EncounterControl.bench(goblin, in: &encounter)

        var generator = ScriptedGenerator(d20Rolls: [15])
        _ = EncounterControl.unbench(goblin, in: &encounter, using: &generator)

        XCTAssertEqual(encounter.blocks[goblin]?.currentHP, 2)
    }

    func testAReturningCombatantDoesNotActTwiceInItsRound() {
        // The join rule, which returning follows exactly: never ahead of the Turn already
        // running.
        var encounter = started()
        _ = EncounterControl.bench(goblin, in: &encounter)

        var generator = ScriptedGenerator(d20Rolls: [20])
        _ = EncounterControl.unbench(goblin, in: &encounter, using: &generator)

        XCTAssertEqual(encounter.activeCombatantID, grog,
                       "the active Combatant must not change")
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, goblin)
    }

    func testReturningSomebodyWhoWasNeverBenchedChangesNothing() {
        var encounter = started()
        let before = encounter.order
        var generator = ScriptedGenerator(d20Rolls: [15])
        _ = EncounterControl.unbench(grog, in: &encounter, using: &generator)
        XCTAssertEqual(encounter.order, before)
    }

    // MARK: The Log

    func testBenchingAndReturningBothFoldBack() {
        // The invariant: what the tracker shows is what the file says.
        var encounter = started()
        var lines: [LogLine] = []
        var generator = ScriptedGenerator(d20Rolls: [12, 18])
        let opening = EncounterControl.start(roster(), at: at, using: &generator)
        encounter = opening.encounter
        lines += opening.lines

        lines += EncounterControl.bench(goblin, in: &encounter)
        lines += EncounterControl.next(&encounter, at: at)

        var rejoin = ScriptedGenerator(d20Rolls: [15])
        lines += EncounterControl.unbench(goblin, in: &encounter, using: &rejoin)
        lines += EncounterControl.next(&encounter, at: at)

        let folded = CombatLogFold.fold(lines)
        XCTAssertEqual(folded.order, encounter.order)
        XCTAssertEqual(folded.benched, encounter.benched)
        XCTAssertEqual(folded.initiative(of: goblin), encounter.initiative(of: goblin))
    }
}
