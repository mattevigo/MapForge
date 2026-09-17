import XCTest
@testable import MapForge

/// The words a Log row shows.
///
/// The rule under test throughout is ADR-0008's: before → after, never a delta.
final class LogRowTextTests: XCTestCase {
    private let combatant = UUID()

    func testAHitPointChangeReadsBeforeAndAfterRatherThanADelta() {
        let text = LogRowText.describe(.hpChanged(combatantID: combatant, from: 22, to: 15),
                                       combatantName: "Grix")
        XCTAssertEqual(text, "Grix — HP 22 → 15")
        XCTAssertFalse(text.contains("7"), "a delta is the thing ADR-0008 refused to store")
    }

    /// A Pawn nobody has statted is not a Pawn at zero, and reading one as the other is the
    /// difference between an unstatted monster and a dead one.
    func testAnUnsetHitPointTotalReadsAsADashAndNotAsZero() {
        let text = LogRowText.describe(.hpChanged(combatantID: combatant, from: nil, to: 12),
                                       combatantName: "Ogre")
        XCTAssertEqual(text, "Ogre — HP — → 12")
    }

    func testAConditionReadsAsAppliedAndRemoved() {
        XCTAssertEqual(
            LogRowText.describe(.conditionAdded(combatantID: combatant, condition: .prone),
                                combatantName: "Grix"),
            "Grix — Prone applied")
        XCTAssertEqual(
            LogRowText.describe(.conditionRemoved(combatantID: combatant, condition: .prone),
                                combatantName: "Grix"),
            "Grix — Prone removed")
    }

    /// The one Change that does not render its values: a list of UUIDs is a wall, and the fact
    /// that matters is that the DM rearranged the Order.
    func testAnOrderChangeSaysOnlyThatItHappened() {
        let text = LogRowText.describe(.orderChanged(order: [UUID(), UUID(), UUID()]),
                                       combatantName: "Grix")
        XCTAssertEqual(text, "Order changed")
    }

    // MARK: Distances

    /// CONTEXT.md's Distance Unit: squares are what is stored, the unit is applied when a
    /// distance is shown. The Log is not the one place that speaks a different language.
    func testAMovementRendersInMetresRatherThanSquares() {
        let text = LogRowText.describe(
            .moved(combatantID: combatant, from: MapPoint(x: 0, y: 0),
                   to: MapPoint(x: 100, y: 0), distanceSquares: 5),
            combatantName: "Grix")
        XCTAssertEqual(text, "Grix — moved 7.5 m", "5 squares at 1.5 m to the square")
    }

    func testASessionMoveAlsoRendersInMetres() {
        let text = LogRowText.describe(.pawnMoved(label: "Grix", distanceSquares: 4,
                                                  at: Date()))
        XCTAssertEqual(text, "Grix moved 6 m")
    }

    // MARK: Rows that head groups

    func testALiveEncounterSaysItIsInProgress() {
        XCTAssertEqual(LogRowText.describe(.encounterStarted(map: "dungeon.png", isLive: true)),
                       "Encounter in progress")
    }

    func testAFinishedEncounterNamesItsMapByFileNameNotItsWholePath() {
        XCTAssertEqual(
            LogRowText.describe(.encounterStarted(map: "maps/crypt/dungeon.png", isLive: false)),
            "Encounter on dungeon.png",
            "the path disambiguates the file; the DM reads the name")
    }

    func testAnUnreadableEncounterNamesWhatItLookedFor() {
        let text = LogRowText.describe(.encounterUnreadable(map: "dungeon.png",
                                                            logFile: "gone.jsonl"))
        XCTAssertTrue(text.contains("gone.jsonl"),
                      "a DM chasing a missing fight needs the file name it wanted")
    }

    func testACorrectionNamesTheTurnItAmends() {
        XCTAssertEqual(
            LogRowText.describe(.correction(targetRound: 3, targetCombatantName: "Grix")),
            "Correction to Round 3 — Grix")
    }

    func testAnOrphanCorrectionSaysItsTurnIsMissing() {
        let text = LogRowText.describe(.orphanCorrection(targetRound: 9))
        XCTAssertTrue(text.contains("not in this log"))
    }

    // MARK: Indentation carries the grouping

    func testChangesSitDeeperThanTurnsAndTurnsDeeperThanRounds() {
        XCTAssertEqual(LogRow.roundHeading(round: 1).indent, 0)
        XCTAssertEqual(LogRow.turn(combatantName: "Grix").indent, 1)
        XCTAssertEqual(LogRow.change(.orderChanged(order: []), combatantName: "Grix").indent, 2)
        XCTAssertEqual(LogRow.correction(targetRound: 1, targetCombatantName: "Grix").indent, 1,
                       "a Correction sits where the Turn it amends sits")
    }

    // MARK: Rolls

    /// The arithmetic is shown, not just the total: a DM reading back wants to see that the
    /// 21 was a 16 on the die, because the die is the part the table remembers.
    func testASavingThrowReadsItsAbilityTotalAndVerdict() {
        let text = LogRowText.describe(
            .savingThrow(combatantID: combatant, ability: .dexterity,
                         roll: Roll(d20: 16, modifier: 5, difficultyClass: 15)),
            combatantName: "Grix")
        XCTAssertEqual(text, "Grix — DEX save 21 (16 + 5) vs DC 15 — succeeded")
    }

    /// No Difficulty Class, no verdict. The Roll is a number the DM recorded before deciding
    /// what it beat, and inventing a verdict for it would be inventing the DC.
    func testASavingThrowWithoutADifficultyClassHasNoVerdict() {
        let text = LogRowText.describe(
            .savingThrow(combatantID: combatant, ability: .wisdom,
                         roll: Roll(d20: 11, modifier: 2)),
            combatantName: "Grix")
        XCTAssertEqual(text, "Grix — WIS save 13 (11 + 2)")
    }

    /// An Ability Check names the Skill and the Ability it derives from, because the pairing
    /// is the thing a DM forgets.
    func testAnAbilityCheckNamesItsSkillAndDerivedAbility() {
        let text = LogRowText.describe(
            .abilityCheck(combatantID: combatant, skill: .stealth,
                          roll: Roll(d20: 12, modifier: 7, difficultyClass: 15)),
            combatantName: "Grix")
        XCTAssertEqual(text, "Grix — Stealth (DEX) 19 (12 + 7) vs DC 15 — succeeded")
    }

    func testAFailedRollReadsAsFailed() {
        let text = LogRowText.describe(
            .abilityCheck(combatantID: combatant, skill: .perception,
                          roll: Roll(d20: 4, modifier: 1, difficultyClass: 15)),
            combatantName: "Grix")
        XCTAssertEqual(text, "Grix — Perception (WIS) 5 (4 + 1) vs DC 15 — failed")
    }

    /// A negative Modifier reads as a subtraction rather than "+ -1", which is the shape a
    /// DM would have said out loud.
    func testANegativeModifierReadsAsASubtraction() {
        let text = LogRowText.describe(
            .savingThrow(combatantID: combatant, ability: .charisma,
                         roll: Roll(d20: 9, modifier: -1)),
            combatantName: "Grix")
        XCTAssertEqual(text, "Grix — CHA save 8 (9 - 1)")
    }
}
