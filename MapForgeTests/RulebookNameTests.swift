import XCTest
@testable import MapForge

/// A save the DM's note names is matched onto the Ability it is, so the Roll sheet can offer
/// the note's bonus for it (ADR-0029).
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
}
