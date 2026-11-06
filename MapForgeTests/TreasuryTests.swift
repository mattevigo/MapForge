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
        """, to: "Riferimento/Equipaggiamento/Bag.md")

        XCTAssertEqual(treasury.items.map(\.name), ["Borsa"])
        XCTAssertEqual(treasury.items.first?.file, "Riferimento/Equipaggiamento/Bag.md")
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
        try write("---\nfonte: XPHB p. 225\n---\n# Borsa\n", to: "Riferimento/Equipaggiamento/Bag.md")
        try write("---\nitem: false\n---\n# Corda\n", to: "Riferimento/Equipaggiamento/Rope.md")
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

    // MARK: Its Portrait

    func testTheImageIsKeptAsALinkAndFoundAmongTheWorkspacesPictures() throws {
        try write("png", to: "Riferimento/Allegati/Borsa.webp")
        try write("""
        ---
        item: true
        image: "[[Riferimento/Allegati/Borsa.webp]]"
        ---
        # Borsa

        ![[Altro.webp]]
        """, to: "Riferimento/Equipaggiamento/Bag.md")

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

    // MARK: What is skipped, and said

    func testTheSecondItemOfANameIsSkippedAndTheFirstByPathWins() throws {
        try write("---\nitem: true\n---\n# Borsa\n", to: "Riferimento/Equipaggiamento/Bag.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "Campagne/Eroi/Oggetti/Borsa.md")

        XCTAssertEqual(treasury.items.map(\.file), ["Campagne/Eroi/Oggetti/Borsa.md"])
        XCTAssertEqual(treasury.skipped.map(\.file), ["Riferimento/Equipaggiamento/Bag.md"])
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

    func testAnUnreadableFrontmatterThatNeverMentionsItemIsNoItemsBusiness() throws {
        // A tavern's note with a broken tag list: the Bestiary does not report it, and
        // neither does the Treasury, which cannot tell it was ever meant as an Item.
        try write("---\ntags: [taverna\n---\n# Il Drago Ubriaco\n", to: "Luoghi/Taverna.md")
        XCTAssertEqual(treasury.skipped, [])
    }

    func testSkippedNotesAreReportedInPathOrder() throws {
        try write("---\nitem: true\n---\n# Borsa\n", to: "A/Bag.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "C/Bag.md")
        try write("---\nitem: true\nx: [\n---\n", to: "B/Broken.md")
        XCTAssertEqual(treasury.skipped.map(\.file), ["B/Broken.md", "C/Bag.md"])
    }

    func testItemsAreSortedByName() throws {
        try write("---\nitem: true\n---\n# Zaino\n", to: "A/Backpack.md")
        try write("---\nitem: true\n---\n# Borsa\n", to: "B/Bag.md")
        try write("---\nitem: true\n---\n# Ägis\n", to: "C/Aegis.md")
        XCTAssertEqual(treasury.items.map(\.name), ["Ägis", "Borsa", "Zaino"])
    }
}
