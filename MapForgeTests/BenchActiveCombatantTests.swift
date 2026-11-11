import XCTest
@testable import MapForge

/// Benching — or deleting from the Map — the Combatant whose Turn is running.
///
/// Doing so ends its Turn: the line is written under its name, and the fight moves on to
/// whoever comes next, wrapping into the next Round when it was last in the Order.
final class BenchActiveCombatantTests: XCTestCase {
    private let grog = UUID()
    private let durga = UUID()
    private let goblin = UUID()
    private let at = Date(timeIntervalSince1970: 1_757_600_000)

    /// Grog 18, Durga 15, goblin 12 — the Order is [grog, durga, goblin].
    private func started() -> (encounter: Encounter, lines: [LogLine]) {
        let roster: [EncounterControl.Entrant] = [
            .init(id: grog, name: "Grog", kind: .player, block: StatBlock()),
            .init(id: durga, name: "Durga", kind: .player, block: StatBlock()),
            .init(id: goblin, name: "Goblin", kind: .creature,
                  block: StatBlock(currentHP: 7, maxHP: 7)),
        ]
        var generator = ScriptedGenerator(d20Rolls: [18, 15, 12])
        return EncounterControl.start(roster, at: at, using: &generator)
    }

    func testBenchingTheLastCombatantOnItsTurnWrapsToTheNextRound() {
        var (encounter, _) = started()
        EncounterControl.next(&encounter, at: at)
        EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, goblin)

        EncounterControl.bench(goblin, in: &encounter)

        XCTAssertEqual(encounter.activeCombatantID, grog, "nobody's Turn after the bench")
        XCTAssertEqual(encounter.round, 2)
        EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, durga, "Next stopped working")
    }

    func testBenchingAMiddleCombatantOnItsTurnHandsTheTurnToTheNextOne() {
        var (encounter, _) = started()
        EncounterControl.next(&encounter, at: at)
        EncounterControl.bench(durga, in: &encounter)

        XCTAssertEqual(encounter.activeCombatantID, goblin)
        XCTAssertEqual(encounter.round, 1)
    }

    func testTheBenchedCombatantsTurnIsWrittenUnderItsOwnName() {
        // A Turn records what happened during it: the goblin's last blow and its fall
        // belong to its Turn, not to whoever acts after it.
        var (encounter, _) = started()
        EncounterControl.next(&encounter, at: at)
        EncounterControl.next(&encounter, at: at)
        EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 0), in: &encounter)
        let lines = EncounterControl.bench(goblin, in: &encounter, at: at)

        guard case let .turn(round, combatantID, changes, _) = lines.last else {
            return XCTFail("benching the active Combatant should end its Turn")
        }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(combatantID, goblin)
        XCTAssertTrue(changes.contains(.combatantRemoved(combatantID: goblin)))
        XCTAssertTrue(encounter.pendingChanges.isEmpty, "grog's Turn should start clean")
    }

    func testBenchingTheActiveCombatantFoldsBackFromTheLog() {
        // Resuming the fight from disk must land on the same Turn as the live tracker.
        var (encounter, lines) = started()
        lines += EncounterControl.next(&encounter, at: at)
        lines += EncounterControl.next(&encounter, at: at)
        lines += EncounterControl.bench(goblin, in: &encounter, at: at)

        let resumed = Encounter(resuming: lines)
        XCTAssertEqual(resumed.activeCombatantID, encounter.activeCombatantID)
        XCTAssertEqual(resumed.round, encounter.round)
        XCTAssertEqual(resumed.order, encounter.order)
    }

    func testBenchingSomebodyElseLeavesTheTurnRunning() {
        var (encounter, _) = started()
        let lines = EncounterControl.bench(goblin, in: &encounter, at: at)

        XCTAssertTrue(lines.isEmpty, "only the active Combatant's bench ends a Turn")
        XCTAssertEqual(encounter.activeCombatantID, grog)
    }

    func testBenchingTheOnlyCombatantLeavesNobodyActive() {
        var (encounter, _) = started()
        EncounterControl.bench(goblin, in: &encounter)
        EncounterControl.bench(durga, in: &encounter)
        EncounterControl.bench(grog, in: &encounter)

        XCTAssertTrue(encounter.order.isEmpty)
        XCTAssertNil(encounter.activeCombatantID)
    }
}
