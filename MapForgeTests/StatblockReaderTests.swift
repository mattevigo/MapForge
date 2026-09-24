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

    func testWindowsLineEndingsAreRead() {
        XCTAssertEqual(monster("```statblock\r\nname: Test\r\nac: 13\r\n```\r\n")?.armorClass, 13)
    }
}
