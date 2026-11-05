import XCTest
@testable import MapForge

/// A save or skill the DM's note names is matched onto the Ability or Skill it is, so the Roll
/// sheet can offer the note's bonus for it (ADR-0029).
///
/// The note's language is not the Mac's: a vault written in Italian is read on a Mac that
/// speaks English. So a name matches when it is the rulebook's in any language the app ships,
/// and only then — a vocabulary of our own, abbreviations included, is not the table's
/// (ADR-0022).
final class RulebookNameTests: XCTestCase {
    func testTheVaultsItalianNamesMatch() {
        XCTAssertEqual(Ability.named("Forza"), .strength)
        XCTAssertEqual(Ability.named("Destrezza"), .dexterity)
        XCTAssertEqual(Ability.named("Costituzione"), .constitution)
        XCTAssertEqual(Ability.named("Intelligenza"), .intelligence)
        XCTAssertEqual(Ability.named("Saggezza"), .wisdom)
        XCTAssertEqual(Ability.named("Carisma"), .charisma)
    }

    /// The vault marks a proficient save with a trailing dot: `Forza ●: 3`.
    func testTheProficiencyDotIsIgnored() {
        XCTAssertEqual(Ability.named("Saggezza ●"), .wisdom)
        XCTAssertEqual(Ability.named("Forza●"), .strength)
    }

    func testEveryShippedLanguageMatches() {
        XCTAssertEqual(Ability.named("Wisdom"), .wisdom)
        XCTAssertEqual(Ability.named("Weisheit"), .wisdom)
        XCTAssertEqual(Ability.named("Sabiduría"), .wisdom)
        XCTAssertEqual(Ability.named("Sagesse"), .wisdom)
        XCTAssertEqual(Ability.named("Sabedoria"), .wisdom)
        XCTAssertEqual(Ability.named("Geschicklichkeit"), .dexterity)
        XCTAssertEqual(Ability.named("Constituição"), .constitution)
    }

    func testCaseAndAccentsAreIgnored() {
        XCTAssertEqual(Ability.named("wisdom"), .wisdom)
        XCTAssertEqual(Ability.named("SAGGEZZA"), .wisdom)
        XCTAssertEqual(Ability.named("sabiduria"), .wisdom)
        XCTAssertEqual(Ability.named("Dexterite"), .dexterity)
        XCTAssertEqual(Ability.named("  Carisma  "), .charisma)
    }

    /// The old vault's `Sag` and `Des`, and the sheet's own `WIS`, are not the rulebook's name.
    func testAbbreviationsDoNotMatch() {
        XCTAssertNil(Ability.named("Sag"))
        XCTAssertNil(Ability.named("Des"))
        XCTAssertNil(Ability.named("WIS"))
    }

    func testAnythingElseMatchesNothing() {
        XCTAssertNil(Ability.named(""))
        XCTAssertNil(Ability.named("●"))
        XCTAssertNil(Ability.named("Saggezza extra"))
        XCTAssertNil(Ability.named("Furtività"), "a Skill is not an Ability")
    }

    // MARK: Skills

    /// The live vault's `skillsaves:` are the Italian 2024 rulebook's names, all eighteen.
    func testEverySkillsItalianNameMatches() {
        let italian: [String: Skill] = [
            "Acrobazia": .acrobatics, "Addestrare Animali": .animalHandling,
            "Arcano": .arcana, "Atletica": .athletics, "Inganno": .deception,
            "Storia": .history, "Intuizione": .insight, "Intimidire": .intimidation,
            "Indagare": .investigation, "Medicina": .medicine, "Natura": .nature,
            "Percezione": .perception, "Intrattenere": .performance,
            "Persuasione": .persuasion, "Religione": .religion,
            "Rapidità di Mano": .sleightOfHand, "Furtività": .stealth,
            "Sopravvivenza": .survival,
        ]
        XCTAssertEqual(Set(italian.values).count, Skill.allCases.count)
        for (name, skill) in italian {
            XCTAssertEqual(Skill.named(name), skill, name)
        }
    }

    func testEverySkillsEnglishNameMatches() {
        let english: [String: Skill] = [
            "Acrobatics": .acrobatics, "Animal Handling": .animalHandling,
            "Arcana": .arcana, "Athletics": .athletics, "Deception": .deception,
            "History": .history, "Insight": .insight, "Intimidation": .intimidation,
            "Investigation": .investigation, "Medicine": .medicine, "Nature": .nature,
            "Perception": .perception, "Performance": .performance,
            "Persuasion": .persuasion, "Religion": .religion,
            "Sleight of Hand": .sleightOfHand, "Stealth": .stealth, "Survival": .survival,
        ]
        XCTAssertEqual(Set(english.values).count, Skill.allCases.count)
        for (name, skill) in english {
            XCTAssertEqual(Skill.named(name), skill, name)
        }
    }

    func testSleightOfHandMatchesInEveryShape() {
        XCTAssertEqual(Skill.named("Rapidità di Mano"), .sleightOfHand)
        XCTAssertEqual(Skill.named("sleight of hand"), .sleightOfHand)
        XCTAssertEqual(Skill.named("Juego de manos"), .sleightOfHand)
        XCTAssertEqual(Skill.named("rapidita di mano"), .sleightOfHand)
    }

    /// One language's name for a Skill is never another Skill's name in a second language,
    /// or a note in the first would be offered the wrong bonus.
    func testEveryShippedTitleMatchesItsOwnSkill() {
        for locale in Locale.shipped {
            for skill in Skill.allCases {
                XCTAssertEqual(Skill.named(skill.title(in: locale)), skill,
                               "\(skill.title(in: locale)) in \(locale.identifier)")
            }
        }
    }

    /// A multi-word name matches whole: a word of it is not the Skill.
    func testPartOfAMultiWordNameMatchesNothing() {
        XCTAssertNil(Skill.named("Rapidità"))
        XCTAssertNil(Skill.named("Mano"))
        XCTAssertNil(Skill.named("Animal"))
        XCTAssertNil(Skill.named("Addestrare"))
        XCTAssertNil(Skill.named("Saggezza"), "an Ability is not a Skill")
    }
}
