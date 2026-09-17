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
}
