import XCTest
@testable import MapForge

/// What the Roll sheet will and will not let a DM record.
///
/// The gate is the **die**, not the Difficulty Class: a DM who has not decided what the Roll
/// beats still has a number worth keeping. See
/// `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
final class RollDraftTests: XCTestCase {

    private let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "Grix",
                            colorHex: "#FF8800", brightSquares: 6)

    // MARK: Recording is gated on the die

    func testNothingIsRecordableBeforeADieIsChosen() {
        var draft = RollDraft(pawn: pawn, kind: .savingThrow)
        draft.ability = .dexterity
        XCTAssertNil(draft.roll, "the d20 is the one thing a Roll cannot be invented without")
    }

    /// The subject is required too — the sheet prompts for it in its subtitle, and a save
    /// against nothing in particular is not a record anybody can read.
    func testNothingIsRecordableBeforeAnAbilityIsChosen() {
        var draft = RollDraft(pawn: pawn, kind: .savingThrow)
        draft.d20 = 16
        XCTAssertNil(draft.roll)
    }

    /// The sheet opens with DC 15 pre-selected, as the design does — the number a DM reaches
    /// for most, offered rather than demanded.
    func testTheSheetOpensWithTheCommonDifficultyClass() {
        XCTAssertEqual(RollDraft(pawn: pawn, kind: .savingThrow).difficultyClass, 15)
    }

    func testADieAndAnAbilityAreEnough() {
        var draft = RollDraft(pawn: pawn, kind: .savingThrow)
        draft.d20 = 16
        draft.ability = .dexterity
        XCTAssertEqual(draft.roll, Roll(d20: 16, modifier: 0, difficultyClass: 15))
    }

    /// The Difficulty Class is optional and must not gate the button: forcing a number here
    /// would invite a made-up one.
    func testTheDifficultyClassDoesNotGateRecording() {
        var draft = RollDraft(pawn: pawn, kind: .savingThrow)
        draft.d20 = 16
        draft.ability = .dexterity
        draft.difficultyClass = nil
        XCTAssertNotNil(draft.roll)
        XCTAssertNil(draft.roll?.succeeded, "no DC, no verdict")
    }

    func testAnAbilityCheckIsGatedOnItsSkill() {
        var draft = RollDraft(pawn: pawn, kind: .abilityCheck)
        draft.d20 = 12
        XCTAssertNil(draft.roll, "an Ability Check needs the Skill it is a check of")

        draft.skill = .stealth
        XCTAssertEqual(draft.roll, Roll(d20: 12, modifier: 0, difficultyClass: 15))
    }

    /// The two kinds do not share a subject: choosing an Ability does not make an Ability
    /// Check recordable, and choosing a Skill does not make a Saving Throw recordable.
    func testTheTwoKindsDoNotShareASubject() {
        var check = RollDraft(pawn: pawn, kind: .abilityCheck)
        check.d20 = 12
        check.ability = .dexterity
        XCTAssertNil(check.roll)

        var save = RollDraft(pawn: pawn, kind: .savingThrow)
        save.d20 = 12
        save.skill = .stealth
        XCTAssertNil(save.roll)
    }

    // MARK: The numbers

    func testTheModifierIsCarriedIntoTheRoll() {
        var draft = RollDraft(pawn: pawn, kind: .savingThrow)
        draft.d20 = 16
        draft.ability = .dexterity
        draft.typeModifier(5)
        draft.difficultyClass = 15
        XCTAssertEqual(draft.roll, Roll(d20: 16, modifier: 5, difficultyClass: 15))
        XCTAssertEqual(draft.roll?.total, 21)
        XCTAssertEqual(draft.roll?.succeeded, true)
    }

    func testANegativeModifierIsAllowed() {
        var draft = RollDraft(pawn: pawn, kind: .savingThrow)
        draft.d20 = 9
        draft.ability = .charisma
        draft.typeModifier(-1)
        XCTAssertEqual(draft.roll?.total, 8)
    }
}
