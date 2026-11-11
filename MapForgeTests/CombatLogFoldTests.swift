import XCTest
@testable import MapForge

/// The fold: a Combat Log read back as the state it describes.
///
/// ADR-0008 makes this the load-bearing piece of the whole feature — current hit points are
/// not stored anywhere, they are what you get by replaying every Change. If this is wrong,
/// the tracker is wrong and no test of the UI would catch it.
final class CombatLogFoldTests: XCTestCase {
    private let grog = UUID()
    private let goblin = UUID()
    private let at = Date(timeIntervalSince1970: 1_757_600_000)

    private func started(order: [UUID]? = nil) -> LogLine {
        .encounterStarted(startedAt: at, order: order ?? [grog, goblin], combatants: [
            Combatant(id: grog, name: "Grog", kind: .player, initiative: 18,
                      block: StatBlock(armorClass: 16, currentHP: 26, maxHP: 26)),
            Combatant(id: goblin, name: "Goblin", kind: .creature, initiative: 12,
                      block: StatBlock(armorClass: 15, currentHP: 7, maxHP: 7)),
        ])
    }

    func testTheOpeningLineIsEnoughToStartFrom() {
        // It carries the settled Order and a snapshot of everyone, so a Log opens without
        // reference to any Pawn, any Map or any roster.
        let state = CombatLogFold.fold([started()])
        XCTAssertEqual(state.order, [grog, goblin])
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.blocks[grog]?.currentHP, 26)
        XCTAssertEqual(state.name(of: goblin), "Goblin")
    }

    func testHitPointsAreWhatTheChangesLeftThem() {
        // The fold, at its simplest: nobody stored 9, it is what two Changes produce.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.hpChanged(combatantID: goblin, from: 7, to: 4)], endedAt: at),
            .turn(round: 1, combatantID: goblin,
                  changes: [.hpChanged(combatantID: grog, from: 26, to: 20)], endedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 4)
        XCTAssertEqual(state.blocks[grog]?.currentHP, 20)
    }

    func testTheRoundIsTheLastOneWritten() {
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .turn(round: 1, combatantID: goblin, changes: [], endedAt: at),
            .turn(round: 2, combatantID: grog, changes: [], endedAt: at),
        ])
        XCTAssertEqual(state.round, 2)
    }

    func testACorrectionChangesTheResultThoughItComesLast() {
        // The point of ADR-0010: a DM in Round 4 fixes the damage they forgot in Round 1,
        // and the tracker shows the corrected number.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .turn(round: 2, combatantID: grog, changes: [], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 7, to: 4)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 4)
    }

    func testTwoCorrectionsAgainstTheSameTurnBothApply() {
        // Nothing stops a DM correcting the same Turn twice, and neither correction may
        // quietly replace the other.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 7, to: 4)],
                        recordedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.conditionAdded(combatantID: goblin, condition: .prone)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 4)
        XCTAssertEqual(state.blocks[goblin]?.conditions, [.prone])
    }

    func testACorrectionLandsBeforeLaterTurns() {
        // A Correction amends the Turn it targets, so a later Turn's Change is applied
        // after it — not the file order, which would let an old value win.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .turn(round: 2, combatantID: grog,
                  changes: [.hpChanged(combatantID: goblin, from: 4, to: 1)], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 7, to: 4)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 1,
                       "Round 2's Change happened after the Turn being corrected")
    }

    func testACorrectionBeatsWhatTheTurnItselfRecorded() {
        // The one ordering rule in the fold, and the reason a Correction is worth having:
        // the DM recorded 4 at the time and later decided it should have been 2. Applying
        // the Correction first would let the original value win and silently discard the
        // amendment.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.hpChanged(combatantID: goblin, from: 7, to: 4)], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 4, to: 2)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 2)
    }

    func testALaterTurnOverridesACorrectionToAnEarlierOne() {
        // The rule when a Correction and a later Turn touch the same field: the later
        // recorded value wins, absolutely. A Change's `to` is authoritative — it is the
        // number the DM saw on screen at that moment — so it is never reinterpreted as a
        // delta to be reapplied on top of an amended history.
        //
        // The consequence is real and is the UI's to handle, not the fold's: correcting
        // Round 1's damage when Round 2 already set a new total changes nothing visible,
        // and the tracker must say so rather than letting a DM believe it landed.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.hpChanged(combatantID: goblin, from: 10, to: 8)], endedAt: at),
            .turn(round: 2, combatantID: grog,
                  changes: [.hpChanged(combatantID: goblin, from: 8, to: 5)], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 8, to: 6)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 5,
                       "Round 2 set 5 after the Turn being corrected, and it stands")
    }

    func testACorrectionToAFieldNoLaterTurnTouchedSurvives() {
        // The other half of the same rule, and the common case: nothing overwrote it, so
        // the amendment is what the tracker shows.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.hpChanged(combatantID: goblin, from: 10, to: 8)], endedAt: at),
            .turn(round: 2, combatantID: grog,
                  changes: [.hpChanged(combatantID: grog, from: 26, to: 22)], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 8, to: 6)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 6)
        XCTAssertEqual(state.blocks[grog]?.currentHP, 22)
    }

    func testACorrectionForATurnThatNeverHappenedIsIgnored() {
        // A hand-edited file, or one from a later version. Not fatal: the rest of the
        // fight is still readable.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .correction(targetRound: 9, targetCombatantID: grog,
                        changes: [.hpChanged(combatantID: goblin, from: 7, to: 4)],
                        recordedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 7)
    }

    func testAJoinedCombatantEntersWithItsSnapshot() {
        // A summon stamped mid-fight.
        let wolf = UUID()
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [
                .combatantJoined(combatantID: wolf, name: "Wolf", kind: .creature,
                                 initiative: 15, block: StatBlock(currentHP: 11, maxHP: 11)),
                .orderChanged(order: [grog, wolf, goblin]),
            ], endedAt: at),
        ])
        XCTAssertEqual(state.order, [grog, wolf, goblin])
        XCTAssertEqual(state.blocks[wolf]?.currentHP, 11)
        XCTAssertEqual(state.name(of: wolf), "Wolf")
    }

    func testABenchedCombatantLeavesTheOrderButNotTheLog() {
        // Out of the Order entirely — it takes no Turns and is listed apart — while its
        // name and numbers stay, because a monster that died in Round 2 is part of what
        // happened and a DM may yet heal it and send it back.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.combatantRemoved(combatantID: goblin)], endedAt: at),
        ])
        XCTAssertTrue(state.benched.contains(goblin))
        XCTAssertFalse(state.order.contains(goblin), "a Benched Pawn is not in the Order")
        XCTAssertEqual(state.name(of: goblin), "Goblin")
        XCTAssertEqual(state.blocks[goblin]?.maxHP, 7)
    }

    func testTheOrderIsWhatWasRecordedNotASortOnInitiative() {
        // ADR-0008: two Combatants on 14 would sort arbitrarily, so the Order is data.
        // Here the DM has put the lower initiative first by hand.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.orderChanged(order: [goblin, grog])], endedAt: at),
        ])
        XCTAssertEqual(state.order, [goblin, grog])
    }

    func testEveryKindOfChangeFolds() {
        // One Turn applying one of everything, so a case added without fold handling is
        // caught here rather than by a DM whose tracker silently ignores it.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [
                .hpChanged(combatantID: grog, from: 26, to: 20),
                .tempHPChanged(combatantID: grog, from: 0, to: 5),
                .maxHPChanged(combatantID: grog, from: 26, to: 30),
                .acChanged(combatantID: grog, from: 16, to: 18),
                .conditionAdded(combatantID: grog, condition: .prone),
                .conditionAdded(combatantID: grog, condition: .poisoned),
                .conditionRemoved(combatantID: grog, condition: .prone),
                .exhaustionChanged(combatantID: grog, from: 0, to: 2),
                .concentrationChanged(combatantID: grog, isConcentrating: true),
                .initiativeChanged(combatantID: grog, from: 18, to: 11),
                .moved(combatantID: grog, from: MapPoint(x: 0, y: 0),
                       to: MapPoint(x: 300, y: 0), distanceSquares: 6),
                .noteAdded(combatantID: grog, text: "shoved the ogre into the pit"),
            ], endedAt: at),
        ])
        let block = state.blocks[grog]
        XCTAssertEqual(block?.currentHP, 20)
        XCTAssertEqual(block?.temporaryHP, 5)
        XCTAssertEqual(block?.maxHP, 30)
        XCTAssertEqual(block?.armorClass, 18)
        XCTAssertEqual(block?.conditions, [.poisoned])
        XCTAssertEqual(block?.exhaustion, 2)
        XCTAssertEqual(block?.isConcentrating, true)
        XCTAssertEqual(state.initiative(of: grog), 11)
    }

    /// A Roll is a record, not a mutation: it folds to nothing, exactly as `.moved` and
    /// `.noteAdded` do. See `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
    func testARollChangesNothingTheTrackerShows() {
        let lines: [LogLine] = [
            started(),
            .turn(round: 1, combatantID: grog, changes: [
                .hpChanged(combatantID: grog, from: 26, to: 20),
            ], endedAt: at),
        ]
        let withoutRolls = CombatLogFold.fold(lines)

        var withRolls = lines
        withRolls.append(.turn(round: 1, combatantID: goblin, changes: [
            .savingThrow(combatantID: grog, name: "Grix", ability: .dexterity,
                         roll: Roll(d20: 3, modifier: 1, difficultyClass: 18)),
            .abilityCheck(combatantID: grog, name: "Grix", skill: .stealth,
                          roll: Roll(d20: 19, modifier: 7, difficultyClass: 15)),
        ], endedAt: at))
        let folded = CombatLogFold.fold(withRolls)

        // Even a failed save leaves hit points, conditions and the Order untouched: the DM
        // applies what a result implies, the app does not.
        XCTAssertEqual(folded.blocks[grog], withoutRolls.blocks[grog])
        XCTAssertEqual(folded.order, withoutRolls.order)
        XCTAssertEqual(folded.benched, withoutRolls.benched)
    }

    func testAnUnrecognisedChangeIsSkippedNotFatal() {
        // A Log written by a later version stays readable by this one.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [
                .unrecognised,
                .hpChanged(combatantID: goblin, from: 7, to: 4),
            ], endedAt: at),
        ])
        XCTAssertEqual(state.blocks[goblin]?.currentHP, 4)
    }

    func testAnEndedEncounterIsMarkedEnded() {
        // What tells a resuming app that this fight is over and a new one should start.
        XCTAssertTrue(CombatLogFold.fold([started(), .encounterEnded(endedAt: at)]).hasEnded)
        XCTAssertFalse(CombatLogFold.fold([started()]).hasEnded)
    }

    func testAnEmptyLogIsAnEmptyState() {
        XCTAssertEqual(CombatLogFold.fold([]).order, [])
    }

    func testTheRoundAdvancesWhenTheLastCombatantsTurnIsWritten() {
        // Resuming a Map whose Log ends on the last Turn of a Round must come back in the
        // *next* Round — the fight is waiting on the first Combatant again. Reading the
        // Round straight off the last Turn line would put the DM a Round behind.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .turn(round: 1, combatantID: goblin, changes: [], endedAt: at),
        ])
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.activeCombatantID, grog)
    }

    func testTheRoundStandsStillMidRound() {
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
        ])
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.activeCombatantID, goblin, "the goblin has not acted yet")
    }

    func testARemovedCombatantIsSkippedWhenResuming() {
        // The Order still names it, so the resumed active Combatant must step over it.
        let state = CombatLogFold.fold([
            started(),
            .turn(round: 1, combatantID: grog,
                  changes: [.combatantRemoved(combatantID: goblin)], endedAt: at),
        ])
        XCTAssertEqual(state.round, 2)
        XCTAssertEqual(state.activeCombatantID, grog)
    }
}
