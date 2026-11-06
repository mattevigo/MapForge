import XCTest
@testable import MapForge

/// The Treasury: every Item read from the DM's notes, in the same walk as the Bestiary, and
/// what is said about the notes that could not be taken. An Item says so in its frontmatter
/// (`item: true`) and nowhere else (ADR-0031).
///
/// Against real folders on disk, as `BestiaryTests` is.
final class TreasuryTests: XCTestCase {
    private var root: URL!
    private var workspace: Workspace!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TreasuryTests.\(UUID().uuidString)")
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

    private var treasury: Treasury { BestiaryStore.read(workspace).treasury }

    // MARK: What an Item is

    func testANoteThatSaysItIsAnItemIsNamedByItsHeading() throws {
        // DM Realm's shape: a translated source key, the two English keys, then the
        // translated name as the first heading.
        try write("""
        ---
        fonte: XPHB p. 225, v2.36.1
        item: true
        ---
        # Borsa

        ## Descrizione
        Una borsa di stoffa.
        """, to: "Riferimento/Equipaggiamento/Borsa.md")

        XCTAssertEqual(treasury.items.map(\.name), ["Borsa"])
        XCTAssertEqual(treasury.items.first?.file, "Riferimento/Equipaggiamento/Borsa.md")
        XCTAssertEqual(treasury.skipped, [])
        XCTAssertNil(treasury.unavailable)
    }

    func testAnItemWithNoHeadingIsNamedByItsFile() throws {
        try write("---\nitem: true\n---\nSolo prosa.\n", to: "Homebrew/Gemma_di_Fuoco.md")
        XCTAssertEqual(treasury.items.map(\.name), ["Gemma di Fuoco"])
    }

    func testASecondLevelHeadingIsNoName() throws {
        try write("---\nitem: true\n---\n## Descrizione\n", to: "Homebrew/Corda.md")
        XCTAssertEqual(treasury.items.map(\.name), ["Corda"])
    }

    func testNotesThatDoNotSayTheyAreItemsAreIgnoredInSilence() throws {
        try write("---\nfonte: XPHB p. 225\n---\n# Borsa\n", to: "Riferimento/Equipaggiamento/Borsa.md")
        try write("---\nitem: false\n---\n# Corda\n", to: "Riferimento/Equipaggiamento/Corda.md")
        try write("# Indice\n\nitem: true\n", to: "Indice.md")
        try write("""
        # Goblin

        ```statblock
        name: Goblin
        item: true
        ac: 15
        ```
        """, to: "Riferimento/Mostri/Goblin.md")

        XCTAssertEqual(treasury.items, [])
        XCTAssertEqual(treasury.skipped, [])
    }

    // MARK: Its picture

    func testTheImageIsKeptAsALinkAndFoundAmongTheWorkspacesPictures() throws {
        try write("png", to: "Riferimento/Allegati/Borsa.webp")
        try write("""
        ---
        item: true
        image: "[[Riferimento/Allegati/Borsa.webp]]"
        ---
        # Borsa

        ![[Altro.webp]]
        """, to: "Riferimento/Equipaggiamento/Borsa.md")

        let borsa = try XCTUnwrap(treasury.items.first)
        XCTAssertEqual(borsa.imageLink, "Riferimento/Allegati/Borsa.webp")
        XCTAssertEqual(borsa.picture, .found("Riferimento/Allegati/Borsa.webp"))
    }

    func testAnImageIsReadAsAFencesIsAndAnUnfoundOneIsSaid() throws {
        // Unquoted, as YAML reads a list in a list; and a web address is no link at all.
        try write("---\nitem: true\nimage: [[Corda.png]]\n---\n# Corda\n", to: "Oggetti/Corda.md")
        try write("---\nitem: true\nimage: https://example.com/a.png\n---\n# Arco\n", to: "Oggetti/Arco.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "Oggetti/Borsa.md")

        let byName = Dictionary(uniqueKeysWithValues: treasury.items.map { ($0.name, $0) })
        XCTAssertEqual(byName["Corda"]?.picture, .missing(link: "Corda.png"))
        XCTAssertNil(byName["Arco"]?.imageLink)
        XCTAssertNil(byName["Borsa"]?.picture)
        XCTAssertEqual(treasury.pictureProblems.map(\.name), ["Corda"])
    }

    /// A bare name two pictures share is no Face, and is said — the Item is still offered.
    func testABareNameTwoPicturesShareGivesNoFaceAndIsSaid() throws {
        try write("png", to: "A/Borsa.webp")
        try write("png", to: "B/Borsa.webp")
        try write("---\nitem: true\nimage: \"[[Borsa.webp]]\"\n---\n# Borsa\n", to: "Oggetti/Borsa.md")

        let borsa = try XCTUnwrap(treasury.items.first)
        XCTAssertEqual(borsa.picture, .ambiguous(link: "Borsa.webp"))
        XCTAssertEqual(treasury.pictureProblems.map(\.name), ["Borsa"])
        XCTAssertEqual(treasury.pictureProblems.map(\.file), ["Oggetti/Borsa.md"])
    }

    // MARK: What is skipped, and said

    func testTheSecondItemOfANameIsSkippedAndTheFirstByPathWins() throws {
        try write("---\nitem: true\n---\n# Borsa\n", to: "Riferimento/Equipaggiamento/Borsa.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "Campagne/Eroi/Oggetti/Borsa.md")

        XCTAssertEqual(treasury.items.map(\.file), ["Campagne/Eroi/Oggetti/Borsa.md"])
        XCTAssertEqual(treasury.skipped.map(\.file), ["Riferimento/Equipaggiamento/Borsa.md"])
        XCTAssertEqual(treasury.skipped.first?.reason,
                       String(localized: "another note already defines “Borsa”"))
    }

    func testAnItemsFrontmatterThatIsNotYAMLIsSkippedWithAReason() throws {
        try write("---\nitem: true\nimage: [[Borsa.webp\n---\n# Borsa\n", to: "Oggetti/Borsa.md")

        XCTAssertEqual(treasury.items, [])
        XCTAssertEqual(treasury.skipped.map(\.file), ["Oggetti/Borsa.md"])
        XCTAssertEqual(treasury.skipped.first?.reason,
                       String(localized: "the frontmatter is not valid YAML"))
    }

    func testAnItemsFrontmatterThatIsNotAListOfFieldsIsSkippedWithAReason() throws {
        try write("---\n- item: true\n- image: x\n---\n# Borsa\n", to: "Oggetti/Borsa.md")

        XCTAssertEqual(treasury.skipped.map(\.file), ["Oggetti/Borsa.md"])
        XCTAssertEqual(treasury.skipped.first?.reason,
                       String(localized: "the frontmatter is not a list of fields"))
    }

    /// YAML may write the fields as one flow mapping. An `item:` key there was meant as an
    /// Item as much as one on a line of its own.
    func testAnItemKeyInABrokenFlowMappingIsSkippedWithAReason() throws {
        try write("---\n{fonte: XPHB, item: true, image: [[Borsa.webp}\n---\n# Borsa\n",
                  to: "Oggetti/Borsa.md")

        XCTAssertEqual(treasury.skipped.map(\.file), ["Oggetti/Borsa.md"])
        XCTAssertEqual(treasury.skipped.first?.reason,
                       String(localized: "the frontmatter is not valid YAML"))
    }

    /// Only the key: a word that merely ends in "item", or a key that is not `item`, is not it.
    func testAnUnreadableFrontmatterWhoseKeysOnlyResembleItemIsNoItemsBusiness() throws {
        try write("---\nmagic-item: true\nitems: [a\n---\n# Borsa\n", to: "Oggetti/Borsa.md")
        XCTAssertEqual(treasury.skipped, [])
    }

    func testAnUnreadableFrontmatterThatNeverMentionsItemIsNoItemsBusiness() throws {
        // A tavern's note with a broken tag list: the Bestiary does not report it, and
        // neither does the Treasury, which cannot tell it was ever meant as an Item.
        try write("---\ntags: [taverna\n---\n# Il Drago Ubriaco\n", to: "Luoghi/Taverna.md")
        XCTAssertEqual(treasury.skipped, [])
    }

    func testSkippedNotesAreReportedInPathOrder() throws {
        try write("---\nitem: true\n---\n# Borsa\n", to: "A/Borsa.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "C/Borsa.md")
        try write("---\nitem: true\nx: [\n---\n", to: "B/Broken.md")
        XCTAssertEqual(treasury.skipped.map(\.file), ["B/Broken.md", "C/Borsa.md"])
    }

    // MARK: Searching

    private let shelf = Treasury(items: [
        Item(name: "Borsa"), Item(name: "Gemma di Fuoco"),
        Item(name: "Pozione di Guarigione"), Item(name: "Spada Lunga +1"),
    ])

    func testSearchFindsAnyPartOfTheNameStartsFirstAndIgnoresAccentsAndCase() {
        // The Bestiary's search, the same query answered the same way.
        XCTAssertEqual(shelf.search("di").map(\.name), ["Gemma di Fuoco", "Pozione di Guarigione"])
        XCTAssertEqual(shelf.search("GUAR").map(\.name), ["Pozione di Guarigione"])
        XCTAssertEqual(Treasury(items: [Item(name: "Ascia"), Item(name: "Gemma Spada")])
            .search("spa").map(\.name), ["Gemma Spada"])
        XCTAssertEqual(Treasury(items: [Item(name: "Gemma Spada"), Item(name: "Spadone")])
            .search("spa").map(\.name), ["Spadone", "Gemma Spada"])
        XCTAssertEqual(Treasury(items: [Item(name: "Pietà")]).search("pieta").count, 1)
        XCTAssertEqual(shelf.search("  ").count, 4)
    }

    func testAnItemIsFoundByTheNameATreasureRemembers() {
        XCTAssertEqual(shelf.item(named: "Borsa")?.name, "Borsa")
        XCTAssertNil(shelf.item(named: "borsa"), "a remembered name is exact, not a search")
        XCTAssertNil(shelf.item(named: nil))
    }

    func testTheTreasuryIsAvailableOnlyWhenReadAndNotEmpty() {
        XCTAssertTrue(shelf.isAvailable)
        XCTAssertFalse(Treasury().isAvailable)
        XCTAssertFalse(Treasury.closed.isAvailable)
        XCTAssertFalse(Treasury.reading.isAvailable)
        XCTAssertNotEqual(Treasury.closed, Treasury.reading)
    }

    // MARK: The caption

    func testAHealthyTreasurySaysNothing() {
        XCTAssertNil(shelf.caption)
    }

    func testSkippedFilesAreCounted() {
        var treasury = shelf
        treasury.skipped = [SkippedNote(file: "x.md", reason: "r")]
        XCTAssertEqual(treasury.caption, "4 Items · 1 file skipped")
        treasury.skipped.append(SkippedNote(file: "y.md", reason: "r"))
        XCTAssertEqual(treasury.caption, "4 Items · 2 files skipped")
        treasury.items = [Item(name: "Borsa")]
        XCTAssertEqual(treasury.caption, "1 Item · 2 files skipped")
    }

    func testAnUnavailableTreasurySaysWhy() {
        XCTAssertEqual(Treasury(unavailable: "Because.").caption, "Because.")
        XCTAssertEqual(Treasury.closed.caption, Bestiary.closed.caption)
    }

    func testAWorkspaceWithNoItemsSaysSo() {
        XCTAssertEqual(Treasury().caption, "No Items found in this Workspace.")
    }

    func testItemsAreSortedByName() throws {
        try write("---\nitem: true\n---\n# Zaino\n", to: "A/Zaino.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "B/Borsa.md")
        try write("---\nitem: true\n---\n# Ägis\n", to: "C/Aegis.md")
        XCTAssertEqual(treasury.items.map(\.name), ["Ägis", "Borsa", "Zaino"])
    }
}
