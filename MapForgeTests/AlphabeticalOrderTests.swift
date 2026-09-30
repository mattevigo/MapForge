import XCTest
@testable import MapForge

/// A list that is alphabetical in English stays alphabetical in every Interface Language:
/// an Italian DM looking for *Furtività* scans for F, not for where Stealth would be.
final class AlphabeticalOrderTests: XCTestCase {
    func testSkillsAreAlphabeticalInItalian() {
        // The official Italian names, sorted: Acrobazia, Addestrare animali, Arcano, Atletica,
        // Furtività, Indagare, Inganno, Intimidire, Intrattenere, Intuizione, Medicina,
        // Natura, Percezione, Persuasione, Rapidità di mano, Religione, Sopravvivenza, Storia.
        XCTAssertEqual(Skill.alphabetical(in: Locale(identifier: "it")),
                       [.acrobatics, .animalHandling, .arcana, .athletics, .stealth,
                        .investigation, .deception, .intimidation, .performance, .insight,
                        .medicine, .nature, .perception, .persuasion, .sleightOfHand,
                        .religion, .survival, .history])
    }

    func testConditionsAreAlphabeticalInItalian() {
        // Accecato, Affascinato, Afferrato, Assordato, Avvelenato, Incapacitato, Invisibile,
        // Paralizzato, Pietrificato, Privo di sensi, Prono, Spaventato, Stordito, Trattenuto.
        XCTAssertEqual(Condition.alphabetical(in: Locale(identifier: "it")),
                       [.blinded, .charmed, .grappled, .deafened, .poisoned, .incapacitated,
                        .invisible, .paralyzed, .petrified, .unconscious, .prone, .frightened,
                        .stunned, .restrained])
    }

    func testEnglishKeepsTheOrderItAlwaysHad() {
        XCTAssertEqual(Skill.alphabetical(in: Locale(identifier: "en")), Skill.allCases)
        XCTAssertEqual(Condition.alphabetical(in: Locale(identifier: "en")), Condition.allCases)
    }
}
