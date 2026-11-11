import XCTest
@testable import MapForge

/// Reading a Monster out of a note in the DM's vault.
///
/// The notes are hand-written for Obsidian and already break a strict reader (ADR-0020), so
/// most of what is pinned here is tolerance: every oddity below is one a real file in the
/// vault this was designed against actually has.
final class StatblockReaderTests: XCTestCase {
    private let gnoll = """
    ---
    tipo: mostro
    nome: Gnoll Guerriero
    ---

    # Gnoll Guerriero

    ```statblock
    name: Gnoll Guerriero
    size: Media
    type: Immondo
    alignment: Caotico Malvagio
    ac: 15
    initiative: "+1 (11)"
    hp: 27
    hit_dice: 6d8
    stats: [14, 12, 11, 6, 10, 7]
    speed: 9 m
    saves:
      - Des: 3
    skillsaves:
      - Percezione: 2
    damage_immunities: veleno
    senses: scurovisione 18 m, Percezione passiva 10
    languages: Gnoll
    cr: 1/2
    traits:
      - name: Furia
        desc: "Attacca **ancora**."
    actions:
      - name: Squartare
        desc: "*Attacco con arma da mischia:* +4 al tiro per colpire. *Colpito:* 5 (1d6 + 2) danni."
      - name: Arco d'Ossa
        desc: "*Attacco a distanza:* +3, gittata 45/180 m."
    bonus_actions:
      - name: Furia Sanguinaria (1/Giorno)
        desc: "Si sposta e attacca con [[Squartare]]."
    source: Monster Manual 2024
    ```

    ## Tattiche

    Caricano in branco.
    """

    private func monster(_ markdown: String,
                         file: StaticString = #filePath, line: UInt = #line) -> Monster? {
        guard case .monster(let monster) = StatblockReader.read(markdown) else {
            XCTFail("expected a Monster", file: file, line: line)
            return nil
        }
        return monster
    }

    /// A fence holding only `body`, for the tests that vary one key.
    private func fence(_ body: String) -> String {
        "```statblock\nname: Test\n\(body)\n```\n"
    }

    // MARK: The numbers a fight needs

    func testTheCombatNumbersAreRead() {
        let gnoll = monster(gnoll)
        XCTAssertEqual(gnoll?.name, "Gnoll Guerriero")
        XCTAssertEqual(gnoll?.armorClass, 15)
        XCTAssertEqual(gnoll?.hitPoints, 27)
        XCTAssertEqual(gnoll?.initiativeBonus, 1)
    }

    func testTheProseAroundTheFenceIsNotTheMonster() {
        // Frontmatter, headings, tactics: the DM's, and none of the app's business.
        XCTAssertEqual(monster("Intro.\n\n" + fence("ac: 12") + "\n## Lore\nac: 99\n")?.armorClass, 12)
    }

    func testANegativeInitiativeWithATypographicMinusIsRead() {
        // U+2212, which is what the vault's own files use. `Int("−1")` is nil.
        XCTAssertEqual(monster(fence("initiative: \"−1 (9)\""))?.initiativeBonus, -1)
        XCTAssertEqual(monster(fence("initiative: \"-2 (8)\""))?.initiativeBonus, -2)
        XCTAssertEqual(monster(fence("initiative: 3"))?.initiativeBonus, 3)
    }

    func testHitPointsWrittenWithTheirDiceStillGiveTheAverage() {
        // `Wraith.md` has exactly this.
        XCTAssertEqual(monster(fence("hp: 67 (9d8 + 27)"))?.hitPoints, 67)
        XCTAssertEqual(monster(fence("ac: 15 (armatura naturale)"))?.armorClass, 15)
    }

    func testAPlusSignAndAnUnquotedNegativeAreNumbers() {
        XCTAssertEqual(monster(fence("initiative: +2"))?.initiativeBonus, 2)
        XCTAssertEqual(monster(fence("initiative: -1"))?.initiativeBonus, -1)
        XCTAssertEqual(monster(fence("initiative: \"+2\""))?.initiativeBonus, 2)
    }

    func testAFormulaIsNoNumberAndTheMonsterStaysAMonster() {
        // A summoned spirit, as DM Realm imports it. Its leading 11 is wrong at every spell
        // level, so it is not taken (ADR-0023).
        let spirit = monster(fence("""
        ac: 11 + il livello dell'incantesimo
        hp: 40 + 10 per ogni livello dell'incantesimo superiore al 4°
        initiative: 2
        """))
        XCTAssertNotNil(spirit)
        XCTAssertNil(spirit?.armorClass)
        XCTAssertNil(spirit?.hitPoints)
        XCTAssertEqual(spirit?.initiativeBonus, 2)
    }

    func testOnlyABracketMayFollowTheNumber() {
        XCTAssertNil(monster(fence("ac: 15 armatura naturale"))?.armorClass)
        XCTAssertNil(monster(fence("ac: 15.5"))?.armorClass)
        XCTAssertNil(monster(fence("ac: armatura 15"))?.armorClass)
        XCTAssertNil(monster(fence("ac: \"−\""))?.armorClass)
        XCTAssertEqual(monster(fence("ac: 15(armatura naturale)"))?.armorClass, 15)
    }

    func testAMonsterMissingNumbersIsStillAMonster() {
        // Offered anyway: it stamps what it has, and the tracker flags the rest.
        let bare = monster(fence("size: Media"))
        XCTAssertNotNil(bare)
        XCTAssertNil(bare?.armorClass)
        XCTAssertNil(bare?.hitPoints)
        XCTAssertNil(bare?.initiativeBonus)
    }

    // MARK: Big

    func testOnlyLargeAndUpIsBig() {
        for size in ["Grande", "Enorme", "Mastodontica", "Large", "huge", "Gargantuan"] {
            XCTAssertEqual(monster(fence("size: \(size)"))?.isBig, true, size)
        }
        for size in ["Minuscola", "Piccola", "Media", "Small or Medium", "Boh"] {
            XCTAssertEqual(monster(fence("size: \(size)"))?.isBig, false, size)
        }
        XCTAssertEqual(monster(fence("ac: 10"))?.isBig, false)
    }

    // MARK: What the DM reads mid-fight

    func testTheReferenceLinesAreRead() {
        let gnoll = monster(gnoll)
        XCTAssertEqual(gnoll?.type, "Immondo")
        XCTAssertEqual(gnoll?.speed, "9 m")
        XCTAssertEqual(gnoll?.senses, "scurovisione 18 m, Percezione passiva 10")
        XCTAssertEqual(gnoll?.challengeRating, "1/2")
        XCTAssertEqual(gnoll?.hitDice, "6d8")
        XCTAssertEqual(gnoll?.damageImmunities, "veleno")
        XCTAssertEqual(gnoll?.saves, [Monster.Proficiency(name: "Des", bonus: 3)])
        XCTAssertEqual(gnoll?.skills, [Monster.Proficiency(name: "Percezione", bonus: 2)])
    }

    func testAWholeNumberChallengeRatingReadsAsText() {
        // YAML makes `cr: 5` an integer and `cr: 1/2` a string. The DM reads both as text.
        XCTAssertEqual(monster(fence("cr: 5"))?.challengeRating, "5")
    }

    func testTheFeaturesAreReadInTheirGroups() {
        let gnoll = monster(gnoll)
        XCTAssertEqual(gnoll?.traits.map(\.name), ["Furia"])
        XCTAssertEqual(gnoll?.actions.map(\.name), ["Squartare", "Arco d'Ossa"])
        XCTAssertEqual(gnoll?.bonusActions.map(\.name), ["Furia Sanguinaria (1/Giorno)"])
        XCTAssertEqual(gnoll?.reactions, [])
        XCTAssertEqual(gnoll?.legendaryActions, [])
        XCTAssertEqual(gnoll?.traits.first?.desc, "Attacca **ancora**.")
    }

    // MARK: What is not a Monster

    func testANoteWithoutAFenceIsNotAMonster() {
        XCTAssertEqual(StatblockReader.read("# Taverna\n\nSolo prosa.\n"), .notAMonster)
    }

    func testAnotherKindOfFenceIsNotAMonster() {
        XCTAssertEqual(StatblockReader.read("```swift\nlet name = 1\n```\n"), .notAMonster)
    }

    func testAFenceThatIsNotYAMLIsSkippedWithAReason() {
        guard case .skipped(let reason) = StatblockReader.read("```statblock\nname: [oops\n```\n")
        else { return XCTFail("expected a skip") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testAFenceWithNoNameIsSkipped() {
        XCTAssertEqual(StatblockReader.read("```statblock\nac: 12\n```\n"),
                       .skipped(reason: "the statblock has no name"))
        XCTAssertEqual(StatblockReader.read("```statblock\nname: \"  \"\nac: 12\n```\n"),
                       .skipped(reason: "the statblock has no name"))
    }

    func testAFenceMarkedOutOfTheBestiaryIsNotAMonster() {
        // A Character's past build and a template, as DM Realm writes them (ADR-0023). The
        // template has no name, and is still not skipped: it said what it is first.
        XCTAssertEqual(StatblockReader.read(fence("bestiary: false\nac: 14")), .notAMonster)
        XCTAssertEqual(StatblockReader.read("```statblock\nbestiary: false\n```\n"), .notAMonster)
        XCTAssertEqual(monster(fence("bestiary: true\nac: 14"))?.armorClass, 14)
    }

    func testACharactersFenceIsNotAMonster() {
        let durga = """
        ```statblock
        layout: DM Realm Character
        name: Durga Pietraferma
        player: Baldu
        ac: 14
        hp: 48
        ```
        """
        XCTAssertEqual(StatblockReader.read(durga), .notAMonster)
    }

    func testACharacterNobodyPlaysYetIsStillNotAMonster() {
        // Zharyn, as DM Realm writes her: no `player`, but the keys only a Character has.
        let zharyn = """
        ```statblock
        layout: DM Realm Character
        name: Zharyn il Velato
        species: Dragonide (Ottone)
        class: Mago
        level: 2
        ac: 12
        ```
        """
        XCTAssertEqual(StatblockReader.read(zharyn), .notAMonster)
        XCTAssertEqual(StatblockReader.read(fence("species: Umano")), .notAMonster)
        XCTAssertEqual(StatblockReader.read(fence("class: Mago")), .notAMonster)
        XCTAssertEqual(StatblockReader.read(fence("level: 2")), .notAMonster)
    }

    func testWindowsLineEndingsAreRead() {
        XCTAssertEqual(monster("```statblock\r\nname: Test\r\nac: 13\r\n```\r\n")?.armorClass, 13)
    }

    // MARK: The picture a note names

    private func imageLink(_ line: String) -> String? {
        guard case .monster(let monster) = StatblockReader.read(
            "```statblock\nname: Nothic\n\(line)\n```\n") else { return nil }
        return monster.imageLink
    }

    func testAQuotedWikilinkNamesThePicture() {
        XCTAssertEqual(imageLink(#"image: "[[Nothic.webp]]""#), "Nothic.webp")
    }

    /// Unquoted, YAML reads the brackets as a list inside a list. The plugin's users write it
    /// both ways, and Obsidian draws both.
    func testAnUnquotedWikilinkNamesThePictureToo() {
        XCTAssertEqual(imageLink("image: [[Nothic.webp]]"), "Nothic.webp")
    }

    func testAPathQualifiedWikilinkKeepsItsPath() {
        XCTAssertEqual(imageLink("image: [[Riferimento/Allegati/Goblin.webp]]"),
                       "Riferimento/Allegati/Goblin.webp")
    }

    func testAWikilinksDisplayTextIsNotPartOfTheName() {
        XCTAssertEqual(imageLink(#"image: "[[Nothic.webp|Il Nothic]]""#), "Nothic.webp")
    }

    /// Opening a game must not need the network (ADR-0028).
    func testAWebAddressIsIgnored() {
        XCTAssertNil(imageLink("image: https://example.com/nothic.webp"))
    }

    func testAPlainFileNameIsNotALink() {
        XCTAssertNil(imageLink("image: Nothic.webp"))
    }

    func testAPictureInTheNotesBodyIsNeverRead() {
        let markdown = "![[Nothic.webp]]\n\n```statblock\nname: Nothic\nac: 15\n```\n"
        guard case .monster(let monster) = StatblockReader.read(markdown) else {
            return XCTFail("not read as a Monster")
        }
        XCTAssertNil(monster.imageLink)
    }

    /// An embed's `!` and a heading's `#` are how the link is written, not what it names.
    func testAnEmbedMarkAndAHeadingAreNotPartOfTheName() {
        XCTAssertEqual(imageLink(#"image: "![[Nothic.webp]]""#), "Nothic.webp")
        XCTAssertEqual(imageLink(#"image: "[[Nothic.webp#Ritratto]]""#), "Nothic.webp")
    }

    func testACharactersFenceNamesItsPictureTheSameWay() {
        let fields: StatblockReader.Fields = ["name": "Durga Pietraferma", "class": "Chierico",
                                              "image": [["Personaggi/Durga.webp"]]]
        guard case .character(let note) = StatblockReader.character(from: fields) else {
            return XCTFail("not read as a Character's note")
        }
        XCTAssertEqual(note.imageLink, "Personaggi/Durga.webp")
    }

    // MARK: Ability scores — read only to offer a Modifier (ADR-0029)

    /// `stats:` is the six scores in the rulebook's order: STR, DEX, CON, INT, WIS, CHA.
    func testTheSixScoresAreReadInTheRulebooksOrder() {
        let scores = monster(gnoll)?.abilityScores
        XCTAssertEqual(scores?[.strength], 14)
        XCTAssertEqual(scores?[.dexterity], 12)
        XCTAssertEqual(scores?[.constitution], 11)
        XCTAssertEqual(scores?[.intelligence], 6)
        XCTAssertEqual(scores?[.wisdom], 10)
        XCTAssertEqual(scores?[.charisma], 7)
    }

    func testAStatsListThatIsNotSixNumbersGivesNoScoresAndTheMonsterStaysAMonster() {
        for stats in ["[11, 12, 10, 10, 13]",
                      "[11, 12, 10, 10, 13, 10, 9]",
                      "[11, 12, dieci, 10, 13, 10]",
                      "forte e saggio",
                      "[11, 12, \"10 + il livello\", 10, 13, 10]"] {
            let read = monster(fence("ac: 13\nstats: \(stats)"))
            XCTAssertEqual(read?.armorClass, 13, stats)
            XCTAssertNil(read?.abilityScores, stats)
        }
    }

    func testANoteWithNoStatsHasNoScores() {
        XCTAssertNil(monster(fence("ac: 13"))?.abilityScores)
    }

    func testAMonsterInheritsItsScoresThroughExtends() {
        let base: StatblockReader.Fields = ["name": "Esploratore",
                                            "stats": [11, 14, 12, 11, 13, 11]]
        let fields: StatblockReader.Fields = ["name": "Vinx", "extends": "Esploratore"]
        guard case .monster(let vinx) = StatblockReader.monster(from: fields,
                                                                bases: ["Esploratore": base])
        else { return XCTFail("not read as a Monster") }
        XCTAssertEqual(vinx.abilityScores?[.wisdom], 13)
    }

    func testAMonsterThatWritesItsOwnStatsKeepsThem() {
        let base: StatblockReader.Fields = ["name": "Esploratore",
                                            "stats": [11, 14, 12, 11, 13, 11]]
        let fields: StatblockReader.Fields = ["name": "Ugof", "extends": "Esploratore",
                                              "stats": [18, 10, 16, 8, 9, 8]]
        guard case .monster(let ugof) = StatblockReader.monster(from: fields,
                                                                bases: ["Esploratore": base])
        else { return XCTFail("not read as a Monster") }
        XCTAssertEqual(ugof.abilityScores?[.wisdom], 9)
    }

    func testACharactersFenceGivesItsScoresToo() {
        let fields: StatblockReader.Fields = ["name": "Durga Pietraferma", "class": "Chierico",
                                              "stats": [14, 10, 14, 10, 16, 12]]
        guard case .character(let note) = StatblockReader.character(from: fields) else {
            return XCTFail("not read as a Character's note")
        }
        XCTAssertEqual(note.abilityScores?[.wisdom], 16)
    }

    // MARK: An Ability's modifier

    func testAnAbilitysModifierRoundsDown() {
        let cases = [(1, -5), (9, -1), (10, 0), (11, 0), (30, 10)]
        for (score, expected) in cases {
            XCTAssertEqual(AbilityScores.modifier(of: score), expected, "score \(score)")
        }
    }
}
