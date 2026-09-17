import AppKit
import XCTest
@testable import MapForge

/// Editing a Combatant's numbers, from the panel.
///
/// The rule every test here exists to hold: during an Encounter a number moves by recording
/// a `Change`, and outside one it is written straight to `stats.json`. ADR-0008's
/// consequences section calls the first of those the rule most likely to be broken by
/// accident and the one that quietly invalidates the format.
@MainActor
final class StatEditingTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatEditingTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeAppState() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.beginEvening(in: directory)
        state.mapURL = mapURL
        return state
    }

    private func pawn(_ label: String, kind: PawnKind = .creature) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind)
    }

    private func fighting() -> (AppState, Pawn) {
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin, pawn("Grog", kind: .player)]
        state.setStatBlock(StatBlock(armorClass: 15, currentHP: 7, maxHP: 7), for: goblin.id)
        state.startEncounter()
        return (state, goblin)
    }

    // MARK: During a fight

    func testEditingHitPointsMidFightRecordsAChange() {
        let (state, goblin) = fighting()
        state.editStatBlock(for: goblin.id) { $0.currentHP = 4 }

        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.currentHP, 4)
        XCTAssertTrue(state.encounter?.pendingChanges.contains(
            .hpChanged(combatantID: goblin.id, from: 7, to: 4)) ?? false,
            "the edit is not in the Turn's Changes")
    }

    func testOneEditRecordsOneChange() {
        // Committed edits, not keystrokes: typing 4 over 7 must not record 7→ nothing →4.
        let (state, goblin) = fighting()
        let before = state.encounter?.pendingChanges.count ?? 0
        state.editStatBlock(for: goblin.id) { $0.currentHP = 4 }
        XCTAssertEqual(state.encounter?.pendingChanges.count, before + 1)
    }

    func testAnEditThatChangesNothingRecordsNothing() {
        // A SwiftUI binding writes the same value back on a state resync, and a Log full of
        // 7→7 would bury the Changes that meant something.
        let (state, goblin) = fighting()
        let before = state.encounter?.pendingChanges.count ?? 0
        state.editStatBlock(for: goblin.id) { $0.currentHP = 7 }
        XCTAssertEqual(state.encounter?.pendingChanges.count, before)
    }

    func testEditingSeveralFieldsAtOnceRecordsAChangeForEach() {
        let (state, goblin) = fighting()
        state.editStatBlock(for: goblin.id) {
            $0.currentHP = 4
            $0.armorClass = 13
            $0.conditions.insert(.prone)
        }
        let pending = state.encounter?.pendingChanges ?? []
        XCTAssertTrue(pending.contains(.hpChanged(combatantID: goblin.id, from: 7, to: 4)))
        XCTAssertTrue(pending.contains(.acChanged(combatantID: goblin.id, from: 15, to: 13)))
        XCTAssertTrue(pending.contains(
            .conditionAdded(combatantID: goblin.id, condition: .prone)))
    }

    func testEditingTheInitiativeBonusMidFightRecordsItAndMovesNobody() throws {
        // The editor's "Init" is the bonus. The rolled number is the Encounter's, edited in
        // the Order's own column — and a bonus changing does not by itself move anyone.
        let (state, goblin) = fighting()
        let rolled = try XCTUnwrap(state.encounter?.initiative(of: goblin.id))

        state.editStatBlock(for: goblin.id) { $0.initiativeBonus = 3 }

        XCTAssertTrue(state.encounter?.pendingChanges.contains(
            .initiativeBonusChanged(combatantID: goblin.id, from: 0, to: 3)) ?? false)
        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.initiativeBonus, 3)
        XCTAssertEqual(state.encounter?.initiative(of: goblin.id), rolled)
    }

    func testTheInitiativeBonusIsSetInPrepStraightToTheStatBlock() {
        // Before a fight is when a bonus matters most: it is what the roll adds.
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]
        state.editStatBlock(for: goblin.id) { $0.initiativeBonus = 2 }
        XCTAssertEqual(state.statBlock(for: goblin.id).initiativeBonus, 2)
    }

    func testRemovingAConditionRecordsIt() {
        let (state, goblin) = fighting()
        state.editStatBlock(for: goblin.id) { $0.conditions.insert(.prone) }
        state.editStatBlock(for: goblin.id) { $0.conditions.remove(.prone) }
        XCTAssertTrue(state.encounter?.pendingChanges.contains(
            .conditionRemoved(combatantID: goblin.id, condition: .prone)) ?? false)
    }

    func testDamageAppliedThroughTheEditorStillTriggersTheZeroRule() {
        // The rule lives in EncounterControl precisely so it holds whichever path moved
        // the number.
        let (state, goblin) = fighting()
        state.editStatBlock(for: goblin.id) { $0.currentHP = 0 }
        XCTAssertTrue(state.encounter?.blocks[goblin.id]?.conditions.contains(.unconscious) ?? false)
    }

    func testTemporaryAndMaximumHitPointsAndExhaustionAllRecord() {
        let (state, goblin) = fighting()
        state.editStatBlock(for: goblin.id) {
            $0.temporaryHP = 5
            $0.maxHP = 9
            $0.exhaustion = 2
            $0.isConcentrating = true
        }
        let pending = state.encounter?.pendingChanges ?? []
        XCTAssertTrue(pending.contains(.tempHPChanged(combatantID: goblin.id, from: 0, to: 5)))
        XCTAssertTrue(pending.contains(.maxHPChanged(combatantID: goblin.id, from: 7, to: 9)))
        XCTAssertTrue(pending.contains(.exhaustionChanged(combatantID: goblin.id, from: 0, to: 2)))
        XCTAssertTrue(pending.contains(
            .concentrationChanged(combatantID: goblin.id, isConcentrating: true)))
    }

    func testEditingInitiativeRecordsIt() {
        // The DM overtypes what a player called out.
        //
        // The new value is derived from the rolled one rather than a literal: `startEncounter`
        // uses the system generator, so a hardcoded 17 silently becomes a no-op on the one
        // run in twenty where the die already gave 17 — which is what made this test fail
        // about a third of the time before the arithmetic was made relative.
        let (state, goblin) = fighting()
        let before = try? XCTUnwrap(state.encounter?.initiative(of: goblin.id))
        let target = (before ?? 0) + 5

        state.setInitiative(target, for: goblin.id)

        XCTAssertEqual(state.encounter?.initiative(of: goblin.id), target)
        XCTAssertTrue(state.encounter?.pendingChanges.contains(
            .initiativeChanged(combatantID: goblin.id, from: before!, to: target)) ?? false)
    }

    func testSettingTheInitiativeItAlreadyHasRecordsNothing() {
        // The no-op the flake was accidentally exercising, now on purpose: a binding that
        // writes the same number back must not fill the Log with 16→16.
        let (state, goblin) = fighting()
        let current = try? XCTUnwrap(state.encounter?.initiative(of: goblin.id))
        let before = state.encounter?.pendingChanges.count ?? 0

        state.setInitiative(current!, for: goblin.id)

        XCTAssertEqual(state.encounter?.pendingChanges.count, before)
    }

    func testWritingNilOverAnExistingValueIsStillJustOneChange() {
        // The shape of the bug that cleared a Combatant's hit points: a field the DM never
        // typed in committed its own empty text on focus loss. `NumberField` guards the
        // commit; this holds the model end, so clearing a value on purpose still works and
        // still records exactly one Change.
        let (state, goblin) = fighting()
        state.editStatBlock(for: goblin.id) { $0.currentHP = nil }
        XCTAssertNil(state.encounter?.blocks[goblin.id]?.currentHP)
        XCTAssertTrue(state.encounter?.pendingChanges.contains(
            .hpChanged(combatantID: goblin.id, from: 7, to: nil)) ?? false)
    }

    // MARK: Outside a fight

    func testEditingDuringPrepWritesStraightToDisk() {
        // There is no Log open before the first fight, so there is nothing to record into —
        // which is exactly why ADR-0009 keeps Stat Blocks out of the Log.
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]

        state.editStatBlock(for: goblin.id) { $0.maxHP = 26; $0.currentHP = 26 }

        XCTAssertNil(state.encounter)
        XCTAssertEqual(state.statBlock(for: goblin.id).maxHP, 26)
    }

    func testPrepEditsSurviveIntoTheFight() {
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]
        state.editStatBlock(for: goblin.id) { $0.maxHP = 26; $0.currentHP = 26 }

        state.startEncounter()
        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.currentHP, 26)
    }

    // MARK: Notes

    func testANoteIsRecordedAgainstTheActiveCombatant() {
        // "relative al pawn che sta svolgendo il turno" — about whoever is acting, even
        // when another row is selected in the editor.
        let (state, _) = fighting()
        let active = try? XCTUnwrap(state.encounter?.activeCombatantID)
        state.addNote("shoved the ogre into the pit")

        XCTAssertTrue(state.encounter?.pendingChanges.contains(
            .noteAdded(combatantID: active!, text: "shoved the ogre into the pit")) ?? false)
    }

    func testAnEmptyNoteIsNotRecorded() {
        let (state, _) = fighting()
        let before = state.encounter?.pendingChanges.count ?? 0
        state.addNote("   ")
        XCTAssertEqual(state.encounter?.pendingChanges.count, before)
    }

    func testANoteWithNoFightGoesNowhere() {
        let state = makeAppState()
        state.addNote("nothing is happening")
        XCTAssertNil(state.encounter)
    }

    // MARK: Correcting

    func testAnEditWhileCorrectingWritesACorrection() throws {
        let (state, goblin) = fighting()
        state.endTurn()
        state.stepBackForCorrection()
        XCTAssertTrue(state.encounter?.isCorrecting ?? false)

        state.editStatBlock(for: goblin.id) { $0.currentHP = 2 }

        let url = try XCTUnwrap(CombatLogReader().newestLogURL(forMapAt: mapURL))
        let lines = try CombatLogReader().read(at: url)
        XCTAssertTrue(lines.contains { if case .correction = $0 { return true } else { return false } },
                      "the edit did not become a Correction")
        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.currentHP, 2)
    }

    func testANoteWhileCorrectingTargetsTheTurnUnderTheCursor() throws {
        let (state, _) = fighting()
        state.endTurn()
        state.stepBackForCorrection()
        state.addNote("forgot the poison")

        let url = try XCTUnwrap(CombatLogReader().newestLogURL(forMapAt: mapURL))
        let lines = try CombatLogReader().read(at: url)
        let corrections = lines.compactMap { line -> [Change]? in
            if case let .correction(_, _, changes, _) = line { return changes } else { return nil }
        }
        XCTAssertTrue(corrections.flatMap { $0 }.contains { change in
            if case let .noteAdded(_, text) = change { return text == "forgot the poison" }
            return false
        }, "the note did not land on the Turn being corrected")
    }
}
