import XCTest
@testable import MapForge

/// Running a fight: rolling, ordering, advancing, correcting.
///
/// Every test here is deterministic through `ScriptedGenerator`, because ADR-0008 needs a
/// Log to be replayable and a non-deterministic Order could not be.
final class EncounterControlTests: XCTestCase {
    private let grog = UUID()
    private let goblin = UUID()
    private let chest = UUID()
    private let at = Date(timeIntervalSince1970: 1_757_600_000)

    /// The goblin is passed **first** and rolls first, so the default `[12, 18]` gives the
    /// goblin 12 and Grog 18 — an Order that is not the order they were passed in, so a
    /// test that passes by accident of input order is caught.
    private func roster() -> [EncounterControl.Entrant] {
        [
            .init(id: goblin, name: "Goblin", kind: .creature,
                  block: StatBlock(armorClass: 15, currentHP: 7, maxHP: 7)),
            .init(id: grog, name: "Grog", kind: .player,
                  block: StatBlock(armorClass: 16, currentHP: 26, maxHP: 26)),
        ]
    }

    /// Rolls are handed out in the order the entrants are passed: goblin, then Grog.
    private func startedEncounter(
        goblinRolls: Int = 12,
        grogRolls: Int = 18
    ) -> (encounter: Encounter, lines: [LogLine]) {
        var generator = ScriptedGenerator(d20Rolls: [goblinRolls, grogRolls])
        return EncounterControl.start(roster(), at: at, using: &generator)
    }

    // MARK: - Starting

    func testStartingRollsForEveryoneAndSortsDescending() {
        // Players are rolled for too: overtyping a number the players call out is faster
        // than typing into an empty field.
        let (encounter, _) = startedEncounter(goblinRolls: 12, grogRolls: 18)
        XCTAssertEqual(encounter.order, [grog, goblin])
        XCTAssertEqual(encounter.initiative(of: grog), 18)
        XCTAssertEqual(encounter.initiative(of: goblin), 12)
    }

    func testTheInitiativeBonusIsAddedToTheRoll() {
        var generator = ScriptedGenerator(d20Rolls: [10])
        let (encounter, _) = EncounterControl.start(
            [.init(id: grog, name: "Grog", kind: .player,
                   block: StatBlock(initiativeBonus: 3))],
            at: at, using: &generator)
        XCTAssertEqual(encounter.initiative(of: grog), 13)
    }

    func testTreasureNeverJoinsTheOrder() {
        // A Treasure has nothing to do on its turn. The spec states it because the Scene
        // panel is driven by PawnKind.allCases and this is the one place that must not be.
        var generator = ScriptedGenerator(d20Rolls: [12, 18, 20])
        let (encounter, _) = EncounterControl.start(roster() + [
            .init(id: chest, name: "Chest", kind: .treasure, block: StatBlock()),
        ], at: at, using: &generator)
        XCTAssertFalse(encounter.order.contains(chest))
        XCTAssertEqual(encounter.order.count, 2)
    }

    func testStartingOpensTheLogWithTheSettledOrder() {
        // ADR-0008 forbids recomputing the Order on read, so the opening line carries it.
        let (_, lines) = startedEncounter()
        guard case let .encounterStarted(_, order, combatants) = lines.first else {
            return XCTFail("expected an encounterStarted line, got \(lines)")
        }
        XCTAssertEqual(order, [grog, goblin])
        XCTAssertEqual(combatants.count, 2)
        XCTAssertEqual(combatants.first { $0.id == grog }?.initiative, 18)
    }

    func testAFightStartsInRoundOneWithTheFirstCombatantActive() {
        let (encounter, _) = startedEncounter()
        XCTAssertEqual(encounter.round, 1)
        XCTAssertEqual(encounter.activeCombatantID, grog)
    }

    func testAPawnWithNoStatBlockStillJoins() {
        // A forgotten stat block must never silently drop a monster from the fight.
        var generator = ScriptedGenerator(d20Rolls: [11])
        let (encounter, _) = EncounterControl.start(
            [.init(id: goblin, name: "Goblin", kind: .creature, block: StatBlock())],
            at: at, using: &generator)
        XCTAssertEqual(encounter.order, [goblin])
        XCTAssertFalse(encounter.blocks[goblin]?.isComplete ?? true)
    }

    // MARK: - Turns and Rounds

    func testNextAdvancesThroughTheOrder() {
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, goblin)
        XCTAssertEqual(encounter.round, 1)
    }

    func testTheRoundIncrementsWhenTheOrderWraps() {
        // Silently: no confirmation, because the table is waiting.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.round, 2)
        XCTAssertEqual(encounter.activeCombatantID, grog)
    }

    func testEndingATurnWritesOneLineCarryingItsChanges() {
        // The shape of the whole format: one line per Turn, with everything that happened.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 4),
                                    in: &encounter)
        let lines = EncounterControl.next(&encounter, at: at)
        guard case let .turn(round, combatantID, changes, _) = lines.first else {
            return XCTFail("expected a turn line, got \(lines)")
        }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(combatantID, grog)
        XCTAssertEqual(changes, [.hpChanged(combatantID: goblin, from: 7, to: 4)])
    }

    func testAChangeIsBufferedUntilTheTurnEnds() {
        // Event sourcing with a write-behind buffer: durability lags by at most one Turn,
        // which is what "saved at the end of the turn" already meant.
        var (encounter, _) = startedEncounter()
        XCTAssertTrue(EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 4),
                                              in: &encounter).isEmpty)
        XCTAssertEqual(encounter.pendingChanges.count, 1)
    }

    func testAChangeToSomeoneElseLandsInTheActiveTurn() {
        // A Turn records what happened during it, not what happened to one Combatant — a
        // potion given to Grog on the goblin's turn belongs in the goblin's line.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        _ = EncounterControl.record(.hpChanged(combatantID: grog, from: 26, to: 20),
                                    in: &encounter)
        let lines = EncounterControl.next(&encounter, at: at)
        guard case let .turn(_, combatantID, changes, _) = lines.first else {
            return XCTFail("expected a turn line")
        }
        XCTAssertEqual(combatantID, goblin)
        XCTAssertEqual(changes.first?.combatantID, grog)
    }

    // MARK: - The correction cursor

    func testPreviousDoesNotMoveTheLiveTurn() {
        // ADR-0010: the pointer does not rewind, a correction cursor moves instead.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        XCTAssertEqual(encounter.activeCombatantID, goblin, "the live Turn must not move")
        XCTAssertEqual(encounter.correctionTarget?.combatantID, grog)
        XCTAssertEqual(encounter.correctionTarget?.round, 1)
    }

    func testAChangeWhileCorrectingWritesACorrectionLine() {
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        let lines = EncounterControl.record(
            .noteAdded(combatantID: grog, text: "forgot the poison"), in: &encounter, at: at)
        guard case let .correction(targetRound, targetCombatantID, changes, _) = lines.first else {
            return XCTFail("expected a correction line, got \(lines)")
        }
        XCTAssertEqual(targetRound, 1)
        XCTAssertEqual(targetCombatantID, grog)
        XCTAssertEqual(changes, [.noteAdded(combatantID: grog, text: "forgot the poison")])
        XCTAssertTrue(encounter.pendingChanges.isEmpty, "a correction is not buffered")
    }

    func testNextReturnsToLiveRatherThanEndingTheTurn() {
        // The same button, two meanings, with the mode on screen. Ending a Turn from a
        // correcting state would be a mis-click waiting to happen.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        let lines = EncounterControl.next(&encounter, at: at)
        XCTAssertTrue(lines.isEmpty, "returning to live ends no Turn")
        XCTAssertNil(encounter.correctionTarget)
        XCTAssertEqual(encounter.activeCombatantID, goblin)
    }

    func testPreviousWalksBackThroughSeveralTurns() {
        // Reaching Round 1 from Round 2 without a timeline view.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)   // grog's round 1 ends
        _ = EncounterControl.next(&encounter, at: at)   // goblin's round 1 ends
        EncounterControl.previous(&encounter)
        XCTAssertEqual(encounter.correctionTarget?.combatantID, goblin)
        EncounterControl.previous(&encounter)
        XCTAssertEqual(encounter.correctionTarget?.combatantID, grog)
        XCTAssertEqual(encounter.correctionTarget?.round, 1)
    }

    func testPreviousStopsAtTheFirstTurn() {
        // There is nothing before Round 1's first Turn to correct.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        EncounterControl.previous(&encounter)
        XCTAssertEqual(encounter.correctionTarget?.combatantID, grog)
    }

    func testPreviousDoesNothingBeforeAnyTurnHasEnded() {
        var (encounter, _) = startedEncounter()
        EncounterControl.previous(&encounter)
        XCTAssertNil(encounter.correctionTarget)
    }

    func testMovementCannotBeCorrected() {
        // Where a Pawn stands is the Map's truth and cannot retroactively be elsewhere.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        let lines = EncounterControl.record(
            .moved(combatantID: grog, from: MapPoint(x: 0, y: 0),
                   to: MapPoint(x: 90, y: 0), distanceSquares: 2),
            in: &encounter, at: at)
        XCTAssertTrue(lines.isEmpty, "a movement correction records nothing")
    }

    func testAReorderWhileCorrectingIsWrittenAsACorrectionNotBufferedIntoTheLiveTurn() {
        // The leak a review caught: an operation that pushed straight into the buffer
        // would silently attach itself to the live Turn while the DM was looking at a
        // past one, which ADR-0010 forbids. Everything now goes through `record`.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        let lines = EncounterControl.reorder(from: 1, to: 0, in: &encounter)
        guard case .correction = lines.first else {
            return XCTFail("expected a correction line, got \(lines)")
        }
        XCTAssertTrue(encounter.pendingChanges.isEmpty)
    }

    func testAJoinIsRecordedOnTheSpotRatherThanOnlyBuffered() {
        // A summon's snapshot must survive a crash before the Turn ends: it is the only
        // record of what the Combatant was when it arrived.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        var generator = ScriptedGenerator(d20Rolls: [15])
        let lines = EncounterControl.join(.init(id: UUID(), name: "Wolf", kind: .creature,
                                                block: StatBlock()),
                                          in: &encounter, using: &generator)
        XCTAssertFalse(lines.isEmpty, "a join while correcting must be written, not buffered")
    }

    func testStoppingIsRefusedWhileCorrecting() {
        // ADR-0010: ending a Turn from a past one is refused rather than reinterpreted,
        // and stopping the fight is the most final version of ending a Turn.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        XCTAssertTrue(EncounterControl.stop(&encounter, at: at).isEmpty)
    }

    func testStoppingAnUntouchedTurnWritesNoEmptyTurnLine() {
        var (encounter, _) = startedEncounter()
        let lines = EncounterControl.stop(&encounter, at: at)
        XCTAssertEqual(lines.count, 1)
        guard case .encounterEnded = lines.first else {
            return XCTFail("expected only an encounterEnded line, got \(lines)")
        }
    }

    // MARK: - Joining and removal

    func testAJoinedCombatantEntersAtItsInitiative() {
        var (encounter, _) = startedEncounter()
        let wolf = UUID()
        var generator = ScriptedGenerator(d20Rolls: [15])
        _ = EncounterControl.join(.init(id: wolf, name: "Wolf", kind: .creature,
                                        block: StatBlock(currentHP: 11, maxHP: 11)),
                                  in: &encounter, using: &generator)
        XCTAssertEqual(encounter.order, [grog, wolf, goblin])
    }

    func testAJoinedCombatantDoesNotActTwiceInItsFirstRound() {
        // A summon arriving on Grog's turn with a higher initiative than Grog would
        // otherwise be inserted before the active index and act immediately.
        var (encounter, _) = startedEncounter()
        let wolf = UUID()
        var generator = ScriptedGenerator(d20Rolls: [20])
        _ = EncounterControl.join(.init(id: wolf, name: "Wolf", kind: .creature,
                                        block: StatBlock()),
                                  in: &encounter, using: &generator)
        XCTAssertEqual(encounter.activeCombatantID, grog,
                       "the active Combatant must not change when someone joins")
        // The wolf rolled 20, above Grog's 18 — but Grog's Turn was already running, so
        // the wolf lands after him rather than displacing a Turn in progress. It still
        // beats the goblin's 12, which is where its Initiative genuinely puts it.
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, wolf)
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, goblin)
        XCTAssertEqual(encounter.round, 1, "all three act in the Round the wolf arrived in")
    }

    func testASummonThatRollsBadlyStillActsInTheRoundItArrived() {
        // It cannot go before Grog, whose Turn is running. Past that it sits where its
        // Initiative earns: a 5 is below the goblin's 12, so it acts last — but it does
        // act, in the Round it was summoned, rather than waiting for the next one.
        var (encounter, _) = startedEncounter()
        let wolf = UUID()
        var generator = ScriptedGenerator(d20Rolls: [5])
        _ = EncounterControl.join(.init(id: wolf, name: "Wolf", kind: .creature,
                                        block: StatBlock()),
                                  in: &encounter, using: &generator)
        XCTAssertEqual(encounter.order, [grog, goblin, wolf])
        XCTAssertEqual(encounter.initiative(of: wolf), 5)

        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, goblin)
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.activeCombatantID, wolf)
        XCTAssertEqual(encounter.round, 1, "the wolf gets its Turn in the Round it arrived")
    }

    // Benching and returning live in `BenchTests`, which covers both directions.

    // MARK: - Reordering

    func testReorderingRecordsTheWholeNewOrder() {
        // Ties are the DM's to break, so the Order is data rather than a sort.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.reorder(from: 1, to: 0, in: &encounter)
        XCTAssertEqual(encounter.order, [goblin, grog])
        XCTAssertEqual(encounter.pendingChanges.last, .orderChanged(order: [goblin, grog]))
    }

    // MARK: - Settling by Initiative

    func testSettlingMovesAnOvertypedRowToWhereItsNumberPutsIt() {
        // The players call out their numbers; the DM overtypes the goblin's 12 as 20 and
        // presses Return. The row goes above Grog's 18, and the whole Order is recorded.
        var (encounter, _) = startedEncounter(goblinRolls: 12, grogRolls: 18)
        _ = EncounterControl.record(.initiativeChanged(combatantID: goblin, from: 12, to: 20),
                                    in: &encounter)
        XCTAssertEqual(encounter.order, [grog, goblin], "typing alone moves nobody")

        _ = EncounterControl.sortByInitiative(in: &encounter)

        XCTAssertEqual(encounter.order, [goblin, grog])
        XCTAssertEqual(encounter.pendingChanges.last, .orderChanged(order: [goblin, grog]))
    }

    func testSettlingASettledOrderRecordsNothing() {
        // Return over an unchanged column must not put an `orderChanged` in the Log.
        var (encounter, _) = startedEncounter(goblinRolls: 12, grogRolls: 18)
        let before = encounter.pendingChanges.count

        let lines = EncounterControl.sortByInitiative(in: &encounter)

        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(encounter.pendingChanges.count, before)
        XCTAssertEqual(encounter.order, [grog, goblin])
    }

    func testSettlingKeepsATieTheDMBroke() {
        // Both on 18, and the DM dragged the goblin above Grog. Return keeps that: a tie
        // is broken by the person running the table, never by the sort.
        var (encounter, _) = startedEncounter(goblinRolls: 18, grogRolls: 18)
        _ = EncounterControl.reorder(from: 1, to: 0, in: &encounter)
        let dragged = encounter.order
        let before = encounter.pendingChanges.count

        _ = EncounterControl.sortByInitiative(in: &encounter)

        XCTAssertEqual(encounter.order, dragged)
        XCTAssertEqual(encounter.pendingChanges.count, before)
    }

    func testSettlingWhileCorrectingIsWrittenAsACorrection() {
        // The same door every reorder goes through (ADR-0010): nothing reaches the live
        // Turn's buffer while the cursor is on a past one.
        var (encounter, _) = startedEncounter(goblinRolls: 12, grogRolls: 18)
        _ = EncounterControl.next(&encounter, at: at)
        EncounterControl.previous(&encounter)
        _ = EncounterControl.record(.initiativeChanged(combatantID: goblin, from: 12, to: 20),
                                    in: &encounter)
        let lines = EncounterControl.sortByInitiative(in: &encounter)
        guard case .correction = lines.first else {
            return XCTFail("expected a correction line, got \(lines)")
        }
        XCTAssertTrue(encounter.pendingChanges.isEmpty)
    }

    // MARK: - Zero hit points

    func testDroppingToZeroAppliesUnconsciousAndClearsConcentration() {
        // Unconditional in the rules, and the thing a DM most reliably forgets.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.concentrationChanged(combatantID: goblin,
                                                          isConcentrating: true),
                                    in: &encounter)
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 0),
                                    in: &encounter)
        XCTAssertTrue(encounter.pendingChanges.contains(
            .conditionAdded(combatantID: goblin, condition: .unconscious)))
        XCTAssertTrue(encounter.pendingChanges.contains(
            .concentrationChanged(combatantID: goblin, isConcentrating: false)))
    }

    func testDroppingBelowZeroAlsoAppliesUnconscious() {
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: -4),
                                    in: &encounter)
        XCTAssertTrue(encounter.pendingChanges.contains(
            .conditionAdded(combatantID: goblin, condition: .unconscious)))
    }

    func testNobodyIsRemovedAtZeroHitPoints() {
        // (c) in the spec's Q22: "monsters always die at 0" is wrong often enough to annoy.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 0),
                                    in: &encounter)
        XCTAssertFalse(encounter.benched.contains(goblin))
    }

    func testDroppingToZeroWhileAlreadyUnconsciousRecordsNoDuplicate() {
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 0),
                                    in: &encounter)
        let afterFirst = encounter.pendingChanges.count
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 0, to: 0),
                                    in: &encounter)
        XCTAssertEqual(encounter.pendingChanges.count, afterFirst + 1,
                       "only the hit point Change itself should be added")
    }

    func testHealingFromZeroDoesNotClearUnconscious() {
        // Coming back up is a decision; going down is not.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 0),
                                    in: &encounter)
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 0, to: 5),
                                    in: &encounter)
        XCTAssertTrue(encounter.blocks[goblin]?.conditions.contains(.unconscious) ?? false)
    }

    func testZeroHitPointsIsNotAppliedToAnAbsentTotal() {
        // A Creature with no hit points typed in is not unconscious; it is unfilled.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.maxHPChanged(combatantID: goblin, from: 7, to: nil),
                                    in: &encounter)
        XCTAssertFalse(encounter.blocks[goblin]?.conditions.contains(.unconscious) ?? true)
    }

    // MARK: - Re-rolling and stopping

    func testRerollingChangesTheOrderAndLeavesTheRoundAlone() {
        // The Round is a fact about history: resetting it would make the Log lie.
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.next(&encounter, at: at)
        _ = EncounterControl.next(&encounter, at: at)
        XCTAssertEqual(encounter.round, 2)

        // Re-rolls walk the Order, which is [grog, goblin]: Grog 3, the goblin 19.
        var generator = ScriptedGenerator(d20Rolls: [3, 19])
        _ = EncounterControl.rerollInitiative(in: &encounter, using: &generator)
        XCTAssertEqual(encounter.round, 2)
        XCTAssertEqual(encounter.order, [goblin, grog], "the goblin rolled 19 to Grog's 3")
    }

    func testRerollingRecordsEveryNewInitiativeAndTheOrder() {
        var (encounter, _) = startedEncounter()
        // Re-rolls walk the Order, which is [grog, goblin]: Grog 3, the goblin 19.
        var generator = ScriptedGenerator(d20Rolls: [3, 19])
        _ = EncounterControl.rerollInitiative(in: &encounter, using: &generator)
        XCTAssertTrue(encounter.pendingChanges.contains(
            .orderChanged(order: [goblin, grog])))
        XCTAssertEqual(encounter.pendingChanges.filter {
            if case .initiativeChanged = $0 { return true } else { return false }
        }.count, 2)
    }

    func testStoppingFlushesTheTurnAndEndsTheLog() {
        var (encounter, _) = startedEncounter()
        _ = EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 4),
                                    in: &encounter)
        let lines = EncounterControl.stop(&encounter, at: at)
        guard case let .turn(_, _, changes, _) = lines.first else {
            return XCTFail("the Turn in progress must be flushed, got \(lines)")
        }
        XCTAssertEqual(changes.count, 1)
        guard case .encounterEnded = lines.last else {
            return XCTFail("expected an encounterEnded line, got \(lines)")
        }
    }

    // MARK: - The invariant

    func testAWholeFightFoldsBackToWhatTheTrackerShows() {
        // The property everything rests on: run a fight, write its lines, fold them back,
        // get the same state. If this holds, the Log is the state ADR-0008 says it is.
        var lines: [LogLine] = []
        var (encounter, opening) = startedEncounter()
        lines += opening

        lines += EncounterControl.record(.hpChanged(combatantID: goblin, from: 7, to: 4),
                                         in: &encounter)
        lines += EncounterControl.record(.conditionAdded(combatantID: goblin, condition: .prone),
                                         in: &encounter)
        lines += EncounterControl.next(&encounter, at: at)

        lines += EncounterControl.record(.hpChanged(combatantID: grog, from: 26, to: 20),
                                         in: &encounter)
        lines += EncounterControl.next(&encounter, at: at)

        // Round 2, and the DM goes back to fix what they forgot.
        lines += EncounterControl.record(.tempHPChanged(combatantID: grog, from: 0, to: 5),
                                         in: &encounter)
        EncounterControl.previous(&encounter)
        lines += EncounterControl.record(.hpChanged(combatantID: goblin, from: 4, to: 2),
                                         in: &encounter, at: at)
        _ = EncounterControl.next(&encounter, at: at)
        lines += EncounterControl.next(&encounter, at: at)

        let folded = CombatLogFold.fold(lines)
        XCTAssertEqual(folded.order, encounter.order)
        XCTAssertEqual(folded.round, encounter.round)
        XCTAssertEqual(folded.blocks[goblin]?.currentHP, 2)
        XCTAssertEqual(folded.blocks[goblin]?.currentHP, encounter.blocks[goblin]?.currentHP)
        XCTAssertEqual(folded.blocks[grog]?.currentHP, encounter.blocks[grog]?.currentHP)
        XCTAssertEqual(folded.blocks[grog]?.temporaryHP, encounter.blocks[grog]?.temporaryHP)
        XCTAssertEqual(folded.blocks[goblin]?.conditions, encounter.blocks[goblin]?.conditions)
    }
}
