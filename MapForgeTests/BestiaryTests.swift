import XCTest
@testable import MapForge

/// The Bestiary: every Monster read from one folder of the DM's notes, and what is said about
/// the ones that could not be.
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

    private func configure(folder: String) throws {
        try write("{ \"version\": 1, \"folder\": \"\(folder)\" }", to: ".mapforge/bestiary.json")
    }

    private func note(_ name: String, _ extra: String = "ac: 12") -> String {
        "# \(name)\n\n```statblock\nname: \(name)\n\(extra)\n```\n"
    }

    // MARK: Reading the folder

    func testEveryMonsterInTheFolderIsRead() throws {
        try configure(folder: "03_Bestiario")
        try write(note("Gnoll Guerriero"), to: "03_Bestiario/Gnoll_Guerriero.md")
        try write(note("Wraith"), to: "03_Bestiario/Wraith.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Gnoll Guerriero", "Wraith"])
        XCTAssertNil(bestiary.unavailable)
        XCTAssertEqual(bestiary.skipped, [])
    }

    func testSubfoldersAreRead() throws {
        try configure(folder: "Bestiario")
        try write(note("Lich"), to: "Bestiario/Non_morti/Antichi/Lich.md")
        XCTAssertEqual(BestiaryStore.load(for: workspace).monsters.map(\.name), ["Lich"])
    }

    func testNotesThatAreNotMonstersAreIgnoredInSilence() throws {
        try configure(folder: "Bestiario")
        try write(note("Lich"), to: "Bestiario/Lich.md")
        try write("# Indice\n\nSolo prosa.\n", to: "Bestiario/Indice.md")
        try write("not markdown", to: "Bestiario/Immagini/lich.png")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
        XCTAssertEqual(bestiary.skipped, [])
    }

    func testABrokenStatblockIsSkippedAndNamed() throws {
        try configure(folder: "Bestiario")
        try write(note("Lich"), to: "Bestiario/Lich.md")
        try write("```statblock\nac: 12\n```\n", to: "Bestiario/Senza_Nome.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.name), ["Lich"])
        XCTAssertEqual(bestiary.skipped,
                       [Bestiary.Skipped(file: "Senza_Nome.md",
                                         reason: "the statblock has no name")])
    }

    func testTheSecondMonsterOfANameIsSkippedAndTheFirstByPathWins() throws {
        try configure(folder: "Bestiario")
        try write(note("Lich", "ac: 17"), to: "Bestiario/A/Lich.md")
        try write(note("Lich", "ac: 99"), to: "Bestiario/B/Lich_Vecchio.md")

        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters.map(\.armorClass), [17])
        XCTAssertEqual(bestiary.skipped,
                       [Bestiary.Skipped(file: "B/Lich_Vecchio.md",
                                         reason: "another note already defines “Lich”")])
    }

    // MARK: When there is no Bestiary

    func testWithoutTheFileThereIsNoBestiaryAndTheReasonNamesIt() {
        let bestiary = BestiaryStore.load(for: workspace)
        XCTAssertEqual(bestiary.monsters, [])
        XCTAssertEqual(bestiary.unavailable, "No .mapforge/bestiary.json in this Workspace.")
    }

    func testAnUnreadableFileIsSaidPlainly() throws {
        try write("{ \"folder\": ", to: ".mapforge/bestiary.json")
        XCTAssertEqual(BestiaryStore.load(for: workspace).unavailable,
                       ".mapforge/bestiary.json could not be read.")
    }

    func testAFolderThatIsNotThereIsNamed() throws {
        try configure(folder: "03_Bestario")
        XCTAssertEqual(BestiaryStore.load(for: workspace).unavailable,
                       "The Bestiary folder “03_Bestario” was not found in this Workspace.")
    }

    func testAFolderOutsideTheWorkspaceIsRefused() throws {
        // What travels with the Workspace must be inside it (ADR-0012).
        let outside = "The Bestiary folder must be inside this Workspace."
        try configure(folder: "../Altrove")
        XCTAssertEqual(BestiaryStore.load(for: workspace).unavailable, outside)
        try configure(folder: "/Users/Shared/Bestiario")
        XCTAssertEqual(BestiaryStore.load(for: workspace).unavailable, outside)
        try configure(folder: "Bestiario/../../Altrove")
        XCTAssertEqual(BestiaryStore.load(for: workspace).unavailable, outside)
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

    func testAFolderWithNoMonstersSaysSo() {
        // Configured and found, but empty: a DM staring at a search with no results should
        // not have to wonder whether the folder was read at all.
        XCTAssertEqual(Bestiary(monsters: []).caption, "No Monsters found in the Bestiary folder.")
    }
}
