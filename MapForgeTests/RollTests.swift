import XCTest
@testable import MapForge

/// The Roll vocabulary: what a d20 result at the table is made of.
///
/// See `docs/adr/0017-a-roll-is-recorded-not-resolved.md`. A Roll is a record, never a
/// resolution — nothing here generates a number or applies what a result implies.
final class RollTests: XCTestCase {

    // MARK: A Skill implies its Ability

    /// The eighteen of DnD 5.5e, each asserted explicitly rather than derived. A table
    /// written from the rules is an independent source of truth; a loop over `Skill.ability`
    /// would only assert that the code agrees with itself.
    func testEverySkillUsesTheAbilityTheRulesGiveIt() {
        let expected: [Skill: Ability] = [
            .acrobatics: .dexterity,
            .animalHandling: .wisdom,
            .arcana: .intelligence,
            .athletics: .strength,
            .deception: .charisma,
            .history: .intelligence,
            .insight: .wisdom,
            .intimidation: .charisma,
            .investigation: .intelligence,
            .medicine: .wisdom,
            .nature: .intelligence,
            .perception: .wisdom,
            .performance: .charisma,
            .persuasion: .charisma,
            .religion: .intelligence,
            .sleightOfHand: .dexterity,
            .stealth: .dexterity,
            .survival: .wisdom,
        ]

        XCTAssertEqual(expected.count, Skill.allCases.count,
                       "a Skill was added or removed without this table being updated")

        for skill in Skill.allCases {
            XCTAssertEqual(skill.ability, expected[skill], "\(skill.rawValue) uses the wrong Ability")
        }
    }

    // MARK: The total and the verdict

    func testTheTotalIsTheDiePlusTheModifier() {
        XCTAssertEqual(Roll(d20: 16, modifier: 5).total, 21)
    }

    func testAModifierCanBeNegative() {
        XCTAssertEqual(Roll(d20: 10, modifier: -3).total, 7)
    }

    /// The Difficulty Class is optional, so the verdict is too: a DM who has not decided
    /// what the Roll beats records the number and nothing else.
    func testThereIsNoVerdictWithoutADifficultyClass() {
        XCTAssertNil(Roll(d20: 16, modifier: 5).succeeded)
    }

    func testMeetingTheDifficultyClassSucceeds() {
        XCTAssertEqual(Roll(d20: 10, modifier: 5, difficultyClass: 15).succeeded, true)
    }

    func testFallingOneUnderTheDifficultyClassFails() {
        XCTAssertEqual(Roll(d20: 9, modifier: 5, difficultyClass: 15).succeeded, false)
    }

    // MARK: Wire names outlive renames

    /// A raw value is what is written to disk. Renaming one silently orphans every Roll
    /// already in a DM's Logs — the `combatantRemoved`/"benched" lesson at
    /// `CombatLogFold.swift:180-183`, pinned here so a rename has to be deliberate.
    func testAbilityWireNamesAreStable() {
        XCTAssertEqual(Ability.allCases.map(\.rawValue),
                       ["strength", "dexterity", "constitution",
                        "intelligence", "wisdom", "charisma"])
    }

    func testSkillWireNamesAreStable() {
        XCTAssertEqual(Set(Skill.allCases.map(\.rawValue)),
                       ["acrobatics", "animalHandling", "arcana", "athletics", "deception",
                        "history", "insight", "intimidation", "investigation", "medicine",
                        "nature", "perception", "performance", "persuasion", "religion",
                        "sleightOfHand", "stealth", "survival"])
    }
}
