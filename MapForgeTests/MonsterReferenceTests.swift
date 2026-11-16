import XCTest
@testable import MapForge

/// What the Combat tab shows of a Monster while it fights: the note's own words, made
/// presentable and nothing more.
final class MonsterReferenceTests: XCTestCase {
    // MARK: A description

    func testWikilinksAreFlattenedToWhatTheDMWouldRead() {
        // Obsidian's links mean nothing outside Obsidian, and `[[` mid-sentence is noise.
        XCTAssertEqual(MonsterReference.plain("attacca con [[Squartare]]."),
                       "attacca con Squartare.")
        XCTAssertEqual(MonsterReference.plain("secondo il [[Tomo_del_Ferro]]"),
                       "secondo il Tomo del Ferro")
        XCTAssertEqual(MonsterReference.plain("vedi [[03_Bestiario/Lich|il Lich]] e [[Wraith#Azioni]]"),
                       "vedi il Lich e Wraith")
    }

    func testEmphasisIsRenderedRatherThanShown() {
        let text = MonsterReference.attributed("*Colpito:* 5 danni, **terreno difficile**.")
        XCTAssertEqual(String(text.characters), "Colpito: 5 danni, terreno difficile.")
    }

    func testTextThatIsNotValidMarkdownIsShownAsWritten() {
        // Never blank: a description the parser dislikes is still the description.
        XCTAssertEqual(String(MonsterReference.attributed("5 * 3 [oops").characters), "5 * 3 [oops")
    }

    // MARK: The lines above the actions

    func testOnlyWhatTheNoteHasIsListed() {
        let monster = Monster(name: "Test", speed: "9 m", challengeRating: "1/2")
        XCTAssertEqual(MonsterReference.lines(of: monster).map(\.label), ["Speed", "CR"])
    }

    func testArmourClassWithInitiativeAndHitPointsWithHitDiceComeBeforeSpeed() {
        // The definition's numbers, read from the note: a pinned Page has no Stat Block above it.
        let monster = Monster(name: "Test", armorClass: 15, hitPoints: 45, initiativeBonus: 2,
                              hitDice: "6d10 + 12", speed: "9 m")
        let lines = MonsterReference.lines(of: monster)
        XCTAssertEqual(lines.map(\.label), ["AC", "HP", "Speed"])
        XCTAssertEqual(lines[0].value, "15")
        XCTAssertEqual(lines[0].beside, [.init(label: "Initiative", value: "+2")])
        XCTAssertEqual(lines[1].value, "45 (6d10 + 12)")
    }

    func testANumberTheNoteLacksLeavesOutOnlyThatPart() {
        let noInitiative = MonsterReference.lines(of: Monster(name: "Test", armorClass: 12, hitPoints: 7))
        XCTAssertEqual(noInitiative, [.init(label: "AC", value: "12"), .init(label: "HP", value: "7")])

        let noArmour = MonsterReference.lines(of: Monster(name: "Test", initiativeBonus: -1,
                                                          hitDice: "2d6"))
        XCTAssertEqual(noArmour, [.init(label: "Initiative", value: "−1"),
                                  .init(label: "HP", value: "(2d6)")])
    }

    // MARK: The ability table

    func testTheTableGivesEachScoreItsModifierAndTheNotesSaveOrElseTheModifier() throws {
        var monster = Monster(name: "Test")
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        monster.saves = [.init(name: "Destrezza", bonus: 5), .init(name: "wisdom", bonus: 3)]
        let table = try XCTUnwrap(MonsterReference.abilities(of: monster))
        XCTAssertEqual(table.rows, [
            .init(ability: .strength, score: 10, modifier: "+0", save: "+0"),
            .init(ability: .dexterity, score: 14, modifier: "+2", save: "+5"),
            .init(ability: .constitution, score: 12, modifier: "+1", save: "+1"),
            .init(ability: .intelligence, score: 8, modifier: "−1", save: "−1"),
            .init(ability: .wisdom, score: 13, modifier: "+1", save: "+3"),
            .init(ability: .charisma, score: 9, modifier: "−1", save: "−1"),
        ])
    }

    func testWithATableTheSavesAreInItAndNotOnALine() {
        var monster = Monster(name: "Test", speed: "9 m")
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        monster.saves = [.init(name: "Destrezza", bonus: 5), .init(name: "Saggezza", bonus: 3)]
        XCTAssertEqual(MonsterReference.lines(of: monster).map(\.label), ["Speed"])
    }

    func testTheTableGoesAfterSpeedAndBeforeTheRest() {
        var monster = Monster(name: "Test", armorClass: 15, hitPoints: 45, speed: "9 m",
                              languages: "Comune")
        monster.skills = [.init(name: "Furtività", bonus: 6)]
        let (above, below) = MonsterReference.split(MonsterReference.lines(of: monster))
        XCTAssertEqual(above.map(\.label), ["AC", "HP", "Speed"])
        XCTAssertEqual(below.map(\.label), ["Skills", "Languages"])

        let bare = Monster(name: "Test", languages: "Comune")
        let (none, all) = MonsterReference.split(MonsterReference.lines(of: bare))
        XCTAssertEqual(none.map(\.label), [])
        XCTAssertEqual(all.map(\.label), ["Languages"])
    }

    func testWithoutAllSixScoresThereIsNoTableAndTheSavesKeepTheirLine() {
        var monster = Monster(name: "Test")
        monster.saves = [.init(name: "Destrezza", bonus: 5)]
        XCTAssertNil(MonsterReference.abilities(of: monster))
        XCTAssertEqual(MonsterReference.lines(of: monster).first { $0.label == "Saves" }?.value,
                       "Destrezza +5")
    }

    func testASaveTheTableCannotPlaceKeepsItsLineSoNothingInTheNoteIsLost() {
        // An abbreviation is not the rulebook's name (ADR-0029), so "Des" has no row to go in.
        var monster = Monster(name: "Test")
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        monster.saves = [.init(name: "Des", bonus: 5), .init(name: "Saggezza", bonus: 3)]
        XCTAssertEqual(MonsterReference.abilities(of: monster)?.rows[1].save, "+2")
        XCTAssertEqual(MonsterReference.lines(of: monster).first { $0.label == "Saves" }?.value,
                       "Des +5")
    }

    func testSavesAndSkillsReadAsSignedBonuses() {
        var monster = Monster(name: "Test")
        monster.saves = [.init(name: "Des", bonus: 3), .init(name: "Sag", bonus: -1)]
        monster.skills = [.init(name: "Furtività", bonus: 6)]
        let lines = MonsterReference.lines(of: monster)
        XCTAssertEqual(lines.first { $0.label == "Saves" }?.value, "Des +3, Sag −1")
        XCTAssertEqual(lines.first { $0.label == "Skills" }?.value, "Furtività +6")
    }

    func testTheGroupsKeepTheBooksOrderAndDropTheEmptyOnes() {
        var monster = Monster(name: "Test")
        monster.reactions = [.init(name: "Parata", desc: "")]
        monster.actions = [.init(name: "Morso", desc: "")]
        XCTAssertEqual(MonsterReference.groups(of: monster).map(\.title), ["Actions", "Reactions"])
    }
}
