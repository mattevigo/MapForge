import XCTest
@testable import MapForge

/// What the Combat tab shows of a Monster while it fights: the note's own words, made
/// presentable and nothing more.
final class MonsterReferenceTests: XCTestCase {
    // MARK: A description

    func testWikilinksAreFlattenedToWhatTheDMWouldRead() {
        // Obsidian's links mean nothing outside Obsidian, and `[[` mid-sentence is noise.
        XCTAssertEqual(PageText.plain("attacca con [[Squartare]]."),
                       "attacca con Squartare.")
        XCTAssertEqual(PageText.plain("secondo il [[Tomo_del_Ferro]]"),
                       "secondo il Tomo del Ferro")
        XCTAssertEqual(PageText.plain("vedi [[03_Bestiario/Lich|il Lich]] e [[Wraith#Azioni]]"),
                       "vedi il Lich e Wraith")
    }

    func testEmphasisIsRenderedRatherThanShown() {
        let text = PageText.attributed("*Colpito:* 5 danni, **terreno difficile**.")
        XCTAssertEqual(String(text.characters), "Colpito: 5 danni, terreno difficile.")
    }

    func testTextThatIsNotValidMarkdownIsShownAsWritten() {
        // Never blank: a description the parser dislikes is still the description.
        XCTAssertEqual(String(PageText.attributed("5 * 3 [oops").characters), "5 * 3 [oops")
    }

    // MARK: The lines above the actions

    func testOnlyWhatTheNoteHasIsListed() {
        let monster = Monster(name: "Test", speed: "9 m", challengeRating: "1/2")
        XCTAssertEqual(lines(of: monster).map(\.label), ["Speed", "CR"])
    }

    func testArmourClassWithInitiativeAndHitPointsWithHitDiceComeBeforeSpeed() {
        // The definition's numbers, read from the note: a pinned Page has no Stat Block above it.
        let monster = Monster(name: "Test", armorClass: 15, hitPoints: 45, initiativeBonus: 2,
                              hitDice: "6d10 + 12", speed: "9 m")
        let printed = lines(of: monster)
        XCTAssertEqual(printed.map(\.label), ["AC", "HP", "Speed"])
        XCTAssertEqual(printed[0].value, "15")
        XCTAssertEqual(printed[0].beside, [.init(label: "Initiative", value: "+2")])
        XCTAssertEqual(printed[1].value, "45 (6d10 + 12)")
    }

    func testANumberTheNoteLacksLeavesOutOnlyThatPart() {
        let noInitiative = lines(of: Monster(name: "Test", armorClass: 12, hitPoints: 7))
        XCTAssertEqual(noInitiative, [.init(label: "AC", value: "12"), .init(label: "HP", value: "7")])

        let noArmour = lines(of: Monster(name: "Test", initiativeBonus: -1, hitDice: "2d6"))
        XCTAssertEqual(noArmour, [.init(label: "Initiative", value: "−1"),
                                  .init(label: "HP", value: "(2d6)")])
    }

    func testTheLinesUseThe2024BooksLabelsInItsOrder() {
        var monster = Monster(name: "Test", speed: "9 m", senses: "Scurovisione 18 m",
                              languages: "Comune", challengeRating: "1/2")
        monster.skills = [.init(name: "Furtività", bonus: 6)]
        monster.damageVulnerabilities = "Radiante"
        monster.damageResistances = "Freddo"
        monster.damageImmunities = "Veleno"
        XCTAssertEqual(lines(of: monster).map(\.label),
                       ["Speed", "Skills", "Vulnerabilities", "Resistances", "Immunities",
                        "Senses", "Languages", "CR"])
    }

    func testDamageAndConditionImmunitiesAreOneLine() {
        func immunities(_ damage: String?, _ conditions: String?) -> String? {
            var monster = Monster(name: "Test")
            monster.damageImmunities = damage
            monster.conditionImmunities = conditions
            return lines(of: monster).first { $0.label == "Immunities" }?.value
        }
        XCTAssertEqual(immunities("Poison", "Poisoned"), "Poison; Poisoned")
        XCTAssertEqual(immunities("Poison", nil), "Poison")
        XCTAssertEqual(immunities(nil, "Poisoned"), "Poisoned")
        XCTAssertNil(immunities(nil, nil))
    }

    func testTheChallengeRatingIsTheNotesAlone() {
        // No XP and no proficiency bonus: the note's value as written.
        let monster = Monster(name: "Test", challengeRating: "1/2")
        XCTAssertEqual(lines(of: monster), [.init(label: "CR", value: "1/2")])
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

    func testTheTableIsTwoBlocksOfThreeAsTheBookPrintsIt() throws {
        let table = try XCTUnwrap(PageText.abilities(AbilityScores([10, 14, 12, 8, 13, 9]),
                                                     saves: []))
        XCTAssertEqual(table.blocks.map { $0.map(\.ability) },
                       [[.strength, .dexterity, .constitution],
                        [.intelligence, .wisdom, .charisma]])
    }

    func testWithATableTheSavesAreInItAndNotOnALine() {
        var monster = Monster(name: "Test", speed: "9 m")
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        monster.saves = [.init(name: "Destrezza", bonus: 5), .init(name: "Saggezza", bonus: 3)]
        XCTAssertEqual(lines(of: monster).map(\.label), ["Speed"])
    }

    func testTheTableGoesAfterSpeedAndBeforeTheRest() {
        // Each line is in the block it is built for, not placed by its label: a translation
        // that read "Speed" as some other line's word would not move it across the table.
        var monster = Monster(name: "Test", armorClass: 15, hitPoints: 45, speed: "9 m",
                              languages: "Comune")
        monster.skills = [.init(name: "Furtività", bonus: 6)]
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        let blocks = MonsterReference.blocks(of: monster)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[1], .armorClassToSpeed([.init(label: "AC", value: "15"),
                                                      .init(label: "HP", value: "45"),
                                                      .init(label: "Speed", value: "9 m")]))
        guard case .abilities = blocks[2] else { return XCTFail("\(blocks[2]) is not the table") }
        XCTAssertEqual(blocks[3], .skillsToChallengeRating([
            .init(label: "Skills", value: "Furtività +6"), .init(label: "Languages", value: "Comune"),
        ]))

        XCTAssertEqual(MonsterReference.blocks(of: Monster(name: "Test", languages: "Comune")),
                       [.heading, .skillsToChallengeRating([.init(label: "Languages", value: "Comune")])])
    }

    func testWithoutAllSixScoresThereIsNoTableAndTheSavesKeepTheirLine() {
        var monster = Monster(name: "Test")
        monster.saves = [.init(name: "Destrezza", bonus: 5)]
        XCTAssertNil(MonsterReference.abilities(of: monster))
        XCTAssertEqual(lines(of: monster).first { $0.label == "Saves" }?.value,
                       "Destrezza +5")
    }

    func testASaveTheTableCannotPlaceKeepsItsLineSoNothingInTheNoteIsLost() {
        // An abbreviation is not the rulebook's name (ADR-0029), so "Des" has no row to go in.
        var monster = Monster(name: "Test")
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        monster.saves = [.init(name: "Des", bonus: 5), .init(name: "Saggezza", bonus: 3)]
        XCTAssertEqual(MonsterReference.abilities(of: monster)?.rows[1].save, "+2")
        XCTAssertEqual(lines(of: monster).first { $0.label == "Saves" }?.value,
                       "Des +5")
    }

    func testSavesAndSkillsReadAsSignedBonuses() {
        var monster = Monster(name: "Test")
        monster.saves = [.init(name: "Des", bonus: 3), .init(name: "Sag", bonus: -1)]
        monster.skills = [.init(name: "Furtività", bonus: 6)]
        let printed = lines(of: monster)
        XCTAssertEqual(printed.first { $0.label == "Saves" }?.value, "Des +3, Sag −1")
        XCTAssertEqual(printed.first { $0.label == "Skills" }?.value, "Furtività +6")
    }

    func testTheGroupsKeepTheBooksOrderAndDropTheEmptyOnes() {
        var monster = Monster(name: "Test")
        monster.reactions = [.init(name: "Parata", desc: "")]
        monster.actions = [.init(name: "Morso", desc: "")]
        XCTAssertEqual(MonsterReference.groups(of: monster).map(\.title), ["Actions", "Reactions"])
    }

    private func lines(of monster: Monster) -> [PageText.Line] {
        MonsterReference.blocks(of: monster).lines
    }

    // MARK: The blocks a rule is drawn between

    func testAFullPageHasEveryBlockInTheBooksOrder() throws {
        var monster = Monster(name: "Test", armorClass: 15, languages: "Comune")
        monster.abilityScores = AbilityScores([10, 14, 12, 8, 13, 9])
        monster.actions = [.init(name: "Morso", desc: "")]
        let table = try XCTUnwrap(MonsterReference.abilities(of: monster))
        XCTAssertEqual(MonsterReference.blocks(of: monster), [
            .heading,
            .armorClassToSpeed([.init(label: "AC", value: "15")]),
            .abilities(table),
            .skillsToChallengeRating([.init(label: "Languages", value: "Comune")]),
            .groups([.init(title: "Actions", paragraphs: [.feature(.init(name: "Morso", desc: ""))])]),
        ])
    }

    func testABlockTheNoteLeavesEmptyIsNotThereToDrawARuleAfter() {
        // So two rules never sit one on the other where a block would have been.
        var monster = Monster(name: "Test", challengeRating: "1/2")
        monster.actions = [.init(name: "Morso", desc: "")]
        XCTAssertEqual(MonsterReference.blocks(of: monster), [
            .heading,
            .skillsToChallengeRating([.init(label: "CR", value: "1/2")]),
            .groups([.init(title: "Actions", paragraphs: [.feature(.init(name: "Morso", desc: ""))])]),
        ])
        XCTAssertEqual(MonsterReference.blocks(of: Monster(name: "Test")), [.heading])
    }
}
