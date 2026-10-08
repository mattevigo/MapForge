import XCTest
@testable import MapForge

/// The Bestiary: every Monster read from the DM's notes, wherever in the Workspace they are
/// (ADR-0023), and what is said about the ones that could not be.
///
/// Against real folders on disk, as `PartyStoreTests` is — what is under test is a reading of
/// files, and a fake file system would prove only that it agrees with itself.
final class BestiaryTests: XCTestCase {
    private var root: URL!
    private var workspace: Workspace!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BestiaryTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mapforge"),
                                                withIntermediateDirectories: true)
        workspace = Workspace(url: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func write(_ text: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func note(_ name: String, _ extra: String = "ac: 12") -> String {
        "# \(name)\n\n```statblock\nname: \(name)\n\(extra)\n```\n"
    }

    // MARK: Reading the Workspace

    func testEveryMonsterInTheWorkspaceIsReadWhereverTheNotesKeepIt() throws {
        // DM Realm's layout: a reference shelf, a campaign's own creature, its named NPCs.
        try write(note("Goblin Guerriero"), to: "Riferimento/Mostri/Goblin_Guerriero.md")
        try write(note("Caos Orb"), to: "Campagne/Eroi/Homebrew_Mostri/Caos_Orb.md")
        try write(note("Narthus"), to: "Campagne/Eroi/PNG/Narthus.md")
        try write(note("Wraith"), to: "Wraith.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name),
                       ["Caos Orb", "Goblin Guerriero", "Narthus", "Wraith"])
        XCTAssertNil(bestiary.unavailable)
        XCTAssertEqual(bestiary.skipped, [])
    }

    func testDeepSubfoldersAreRead() throws {
        try write(note("Lich"), to: "Bestiario/Non_morti/Antichi/Lich.md")
        XCTAssertEqual(BestiaryStore.load(for: workspace).monsters.map(\.name), ["Lich"])
    }

    func testNotesThatAreNotMonstersAreIgnoredInSilence() throws {
        try write(note("Lich"), to: "Bestiario/Lich.md")
        try write("# Indice\n\nSolo prosa.\n", to: "Bestiario/Indice.md")
        try write("not markdown", to: "Bestiario/Immagini/lich.png")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
        XCTAssertEqual(bestiary.skipped, [])
    }

    func testFencesThatSayTheyAreNoMonsterAreNeitherListedNorSkipped() throws {
        try write(note("Lich"), to: "Riferimento/Mostri/Lich.md")
        try write("```statblock\nbestiary: false\n```\n", to: "Modelli/Mostro_Homebrew.md")
        try write(note("Durga Pietraferma", "bestiary: false\nplayer: Baldu"),
                  to: "Personaggi/Durga_Pietraferma/Build_Passate/Durga_Pietraferma_01.md")
        try write(note("Durga Pietraferma", "player: Baldu\nhp: 48"),
                  to: "Personaggi/Durga_Pietraferma/Durga_Pietraferma.md")
        try write(note("Zharyn il Velato", "species: Dragonide\nclass: Mago\nlevel: 2"),
                  to: "Personaggi/Zharyn_il_Velato/Zharyn_il_Velato.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
        XCTAssertEqual(bestiary.skipped, [])
    }

    func testHiddenFoldersAreNotRead() throws {
        try write(note("Lich"), to: "Bestiario/Lich.md")
        try write(note("Ombra"), to: ".obsidian/plugins/fantasy-statblocks/Ombra.md")
        try write(note("Spettro"), to: ".git/Spettro.md")
        try write(note("Fantasma"), to: ".mapforge/Fantasma.md")
        try write(note("Larva"), to: "Bestiario/.bozze/Larva.md")

        XCTAssertEqual(BestiaryStore.load(for: workspace).monsters.map(\.name), ["Lich"])
    }

    func testABrokenStatblockIsSkippedAndNamedFromTheWorkspaceRoot() throws {
        try write(note("Lich"), to: "Bestiario/Lich.md")
        try write("```statblock\nac: 12\n```\n", to: "Bestiario/Senza_Nome.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
        XCTAssertEqual(bestiary.skipped,
                       [Bestiary.Skipped(file: "Bestiario/Senza_Nome.md",
                                         reason: "the statblock has no name")])
    }

    func testTheSecondMonsterOfANameIsSkippedAndTheFirstByPathWins() throws {
        try write(note("Lich", "ac: 17"), to: "Bestiario/A/Lich.md")
        try write(note("Lich", "ac: 99"), to: "Bestiario/B/Lich_Vecchio.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.armorClass), [17])
        XCTAssertEqual(bestiary.skipped,
                       [Bestiary.Skipped(file: "Bestiario/B/Lich_Vecchio.md",
                                         reason: "another note already defines “Lich”")])
    }

    // MARK: A Monster written as another

    private let esploratore = """
        ac: 13
        ac_class: armatura di cuoio
        hp: 16
        initiative: 2
        size: Media
        languages: Comune
        actions:
          - name: Spada Corta
            desc: "+4 al tiro per colpire."
          - name: Arco Lungo
            desc: "+4 al tiro per colpire."
        """

    private func monster(_ name: String, in bestiary: Bestiary) -> Monster? {
        bestiary.monster(named: name)
    }

    func testAnNPCIsItsBaseWithItsOwnChangesLaidOver() throws {
        // Vinx, as DM Realm writes a campaign NPC.
        try write(note("Esploratore", esploratore), to: "Riferimento/Mostri/Esploratore.md")
        try write(note("Vinx", "extends: Esploratore\nsize: Piccola\nlanguages: Comune e Nanico"),
                  to: "Campagne/Eroi/PNG/Vinx.md")

        let bestiary = BestiaryStore.load(for: workspace)
        let vinx = try XCTUnwrap(monster("Vinx", in: bestiary))
        XCTAssertEqual(vinx.name, "Vinx")
        XCTAssertEqual(vinx.armorClass, 13)
        XCTAssertEqual(vinx.hitPoints, 16)
        XCTAssertEqual(vinx.initiativeBonus, 2)
        XCTAssertEqual(vinx.size, "Piccola")
        XCTAssertEqual(vinx.languages, "Comune e Nanico")
        XCTAssertEqual(vinx.actions.map(\.name), ["Spada Corta", "Arco Lungo"])
        XCTAssertNotNil(monster("Esploratore", in: bestiary), "the base is still a Monster")
        XCTAssertEqual(bestiary.skipped, [])
    }

    func testAnNPCsNumbersReplaceTheBases() throws {
        // Ugof overrides armour and hit points and keeps the base's initiative.
        try write(note("Esploratore", esploratore), to: "Riferimento/Mostri/Esploratore.md")
        try write(note("Ugof", "extends: Esploratore\nac: 12\nac_class: senza armatura\nhp: 58"),
                  to: "Campagne/Eroi/PNG/Ugof.md")

        let ugof = try XCTUnwrap(monster("Ugof", in: BestiaryStore.load(for: workspace)))
        XCTAssertEqual(ugof.armorClass, 12)
        XCTAssertEqual(ugof.hitPoints, 58)
        XCTAssertEqual(ugof.initiativeBonus, 2)
    }

    func testAListTheNPCWritesReplacesTheBasesWhole() throws {
        try write(note("Esploratore", esploratore), to: "Riferimento/Mostri/Esploratore.md")
        try write(note("Narthus", """
            extends: Esploratore
            actions:
              - name: Pugnale
                desc: "+3 al tiro per colpire."
            """), to: "Campagne/Eroi/PNG/Narthus.md")

        let narthus = try XCTUnwrap(monster("Narthus", in: BestiaryStore.load(for: workspace)))
        XCTAssertEqual(narthus.actions.map(\.name), ["Pugnale"])
    }

    func testAChainIsFollowedAndTheNearestChangeWins() throws {
        // A base defined *after* the note extending it in path order is found all the same.
        try write(note("Capo", "extends: Veterano\nhp: 90"), to: "A/Capo.md")
        try write(note("Veterano", "extends: Esploratore\nac: 17\nhp: 58"), to: "B/Veterano.md")
        try write(note("Esploratore", esploratore), to: "C/Esploratore.md")

        let capo = try XCTUnwrap(monster("Capo", in: BestiaryStore.load(for: workspace)))
        XCTAssertEqual(capo.armorClass, 17)
        XCTAssertEqual(capo.hitPoints, 90)
        XCTAssertEqual(capo.initiativeBonus, 2)
    }

    func testSeveralBasesAreLaidInOrder() throws {
        try write(note("Esploratore", esploratore), to: "Esploratore.md")
        try write(note("Bandito", "ac: 12\nhp: 11"), to: "Bandito.md")
        try write(note("Ladro", "extends: [Esploratore, Bandito]"), to: "Ladro.md")

        let ladro = try XCTUnwrap(monster("Ladro", in: BestiaryStore.load(for: workspace)))
        XCTAssertEqual(ladro.armorClass, 12)
        XCTAssertEqual(ladro.initiativeBonus, 2)
    }

    func testABaseKeptOutOfTheBestiaryCanStillBeExtended() throws {
        try write(note("Guardia Base", "bestiary: false\nac: 16\nhp: 11"), to: "Modelli/Guardia_Base.md")
        try write(note("Guardia del Porto", "extends: Guardia Base"), to: "PNG/Guardia_del_Porto.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Guardia del Porto"])
        XCTAssertEqual(monster("Guardia del Porto", in: bestiary)?.armorClass, 16)
    }

    func testAHiddenDraftNeverTakesTheNameOfAListedMonster() throws {
        // The draft comes first by path, and still loses the name to the Monster the DM sees.
        try write(note("Esploratore", "bestiary: false\nac: 99"), to: "A/Bozza.md")
        try write(note("Esploratore", esploratore), to: "B/Esploratore.md")
        try write(note("Vinx", "extends: Esploratore"), to: "C/Vinx.md")

        XCTAssertEqual(monster("Vinx", in: BestiaryStore.load(for: workspace))?.armorClass, 13)
    }

    func testAMissingBaseIsSkippedAndNamed() throws {
        try write(note("Vinx", "extends: Esploratore"), to: "PNG/Vinx.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters, [])
        XCTAssertEqual(bestiary.skipped,
                       [Bestiary.Skipped(file: "PNG/Vinx.md",
                                         reason: "extends: “Esploratore” names a Monster no note defines")])
    }

    func testALoopIsSkippedRatherThanFollowed() throws {
        try write(note("Uno", "extends: Due"), to: "Uno.md")
        try write(note("Due", "extends: Uno"), to: "Due.md")
        try write(note("Tre", "extends: Tre"), to: "Tre.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters, [])
        XCTAssertEqual(bestiary.skipped.map(\.file), ["Due.md", "Tre.md", "Uno.md"])
        XCTAssertEqual(Set(bestiary.skipped.map(\.reason)), ["its extends chain comes back to itself"])
    }

    func testACharacterIsNeverABase() throws {
        try write(note("Durga Pietraferma", "player: Baldu\nac: 14"), to: "Personaggi/Durga.md")
        try write(note("Sosia", "extends: Durga Pietraferma"), to: "PNG/Sosia.md")

        XCTAssertEqual(BestiaryStore.load(for: workspace).skipped.map(\.reason),
                       ["extends: “Durga Pietraferma” names a Monster no note defines"])
    }

    // MARK: The old configuration

    func testAWorkspaceWithoutAConfigurationHasABestiary() throws {
        // `.mapforge/config.json` once named the one folder to read; nothing needs it now.
        try write(note("Lich"), to: "Bestiario/Lich.md")
        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertNil(bestiary.unavailable)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
    }

    func testAnOldConfigurationNamingOneFolderIsIgnored() throws {
        // DM Realm's Setup writes the key pointing at its reference shelf, which would hide
        // every campaign NPC were it still obeyed.
        try write("{ \"bestiaryStatBlockPath\": \"Riferimento/Mostri\" }", to: ".mapforge/config.json")
        try write(note("Goblin Guerriero"), to: "Riferimento/Mostri/Goblin_Guerriero.md")
        try write(note("Narthus"), to: "Campagne/Eroi/PNG/Narthus.md")
        XCTAssertEqual(BestiaryStore.load(for: workspace).monsters.map(\.name),
                       ["Goblin Guerriero", "Narthus"])

        try write("{ \"bestiaryStatBlockPath\": ", to: ".mapforge/config.json")
        XCTAssertEqual(BestiaryStore.load(for: workspace).monsters.count, 2,
                       "a broken file nothing reads breaks nothing")
    }

    func testAWorkspaceUnderPrivateIsReadAsItself() throws {
        // `standardizingPath` strips a leading /private; the paths it reports must still be
        // relative to the Workspace however its root was spelled.
        try write("```statblock\nac: 12\n```\n", to: "Bestiario/Senza_Nome.md")
        try write(note("Lich"), to: "Bestiario/Lich.md")
        let spelledOut = Workspace(url: URL(fileURLWithPath: "/private" + root.path))
        let bestiary = BestiaryStore.load(for: spelledOut)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
        XCTAssertEqual(bestiary.skipped.map(\.file), ["Bestiario/Senza_Nome.md"])
    }

    // MARK: Searching

    private let shelf = Bestiary(monsters: [
        Monster(name: "Capo Goblin"), Monster(name: "Goblin Guerriero"),
        Monster(name: "Mostruosità Blu"), Monster(name: "Wraith"),
    ])

    func testSearchFindsAnyPartOfTheNameWhateverItsCase() {
        XCTAssertEqual(shelf.search("gob").map(\.name), ["Goblin Guerriero", "Capo Goblin"])
        XCTAssertEqual(shelf.search("RAI").map(\.name), ["Wraith"])
    }

    func testANameThatStartsWithTheQueryComesFirst() {
        // "Goblin Guerriero" before "Capo Goblin": the DM typing "gob" is spelling a name
        // from its start far more often than from its middle.
        XCTAssertEqual(shelf.search("goblin").first?.name, "Goblin Guerriero")
    }

    func testSearchIgnoresAccents() {
        // An Italian vault on a keyboard where à is two keys.
        XCTAssertEqual(shelf.search("mostruosita").map(\.name), ["Mostruosità Blu"])
    }

    func testAnEmptySearchOffersEverything() {
        XCTAssertEqual(shelf.search("  ").count, 4)
    }

    func testAMonsterIsFoundByTheNameAPawnRemembers() {
        XCTAssertEqual(shelf.monster(named: "Wraith")?.name, "Wraith")
        XCTAssertNil(shelf.monster(named: "wraith"), "a remembered name is exact, not a search")
        XCTAssertNil(shelf.monster(named: nil))
    }

    // MARK: The caption

    func testAHealthyBestiarySaysNothing() {
        XCTAssertNil(shelf.caption)
    }

    func testSkippedFilesAreCounted() {
        var bestiary = shelf
        bestiary.skipped = [Bestiary.Skipped(file: "x.md", reason: "r")]
        XCTAssertEqual(bestiary.caption, "4 Monsters · 1 file skipped")
        bestiary.skipped.append(Bestiary.Skipped(file: "y.md", reason: "r"))
        XCTAssertEqual(bestiary.caption, "4 Monsters · 2 files skipped")
    }

    func testAnUnavailableBestiarySaysWhy() {
        XCTAssertEqual(Bestiary(unavailable: "Because.").caption, "Because.")
    }

    func testAWorkspaceWithNoMonstersSaysSo() {
        // Read, but empty: a DM staring at a search with no results should not have to
        // wonder whether the notes were read at all.
        XCTAssertEqual(Bestiary(monsters: []).caption, "No Monsters found in this Workspace.")
    }
}
