import XCTest
@testable import MapForge

final class StatsStoreTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatsStoreTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testStatBlocksSurviveARelaunch() throws {
        // The point of the store: a DM who typed six monsters' hit points during prep
        // does not type them again next week.
        let pawn = UUID()
        let document = StatsDocument(blocks: [pawn: StatBlock(armorClass: 15, currentHP: 11, maxHP: 26)])
        try StatsStore().save(document, forMapAt: mapURL)
        XCTAssertEqual(StatsStore().load(forMapAt: mapURL), document)
    }

    func testTheFileSitsInACombatFolderBesideTheMap() throws {
        // One folder per Map keeps the DM's map directory browsable and makes "delete
        // everything about fights on this map" a single gesture.
        try StatsStore().save(StatsDocument(blocks: [UUID(): StatBlock()]), forMapAt: mapURL)
        let expected = directory
            .appendingPathComponent("dungeon.combat")
            .appendingPathComponent("stats.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    func testSavingCreatesTheCombatFolder() throws {
        // Unlike FogStore, this one writes into a directory that does not exist yet.
        try StatsStore().save(StatsDocument(blocks: [UUID(): StatBlock()]), forMapAt: mapURL)
        var isDirectory: ObjCBool = false
        let path = directory.appendingPathComponent("dungeon.combat").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testNoStatsYetIsNotAnError() {
        // The normal case for every Map nobody has ever fought on.
        XCTAssertNil(StatsStore().load(forMapAt: mapURL))
    }

    func testAnUnreadableFileIsReportedAndNotOverwritten() throws {
        // The FogStore guarantee. A DM who reopens a Map, sees no hit points, retypes
        // them and overwrites the file that would have recovered them has lost real work.
        let folder = directory.appendingPathComponent("dungeon.combat")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("stats.json")
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: file)

        let store = StatsStore()
        XCTAssertNil(store.load(forMapAt: mapURL))
        XCTAssertNotNil(store.lastLoadFailure)
        XCTAssertEqual(try Data(contentsOf: file), garbage)
    }

    func testAFailureDoesNotLingerOntoTheNextMap() {
        // One store outlives many Maps: a failure left over from a corrupt Map must not
        // attach a stale error to the next good one.
        let store = StatsStore()
        _ = store.load(forMapAt: mapURL)
        XCTAssertNil(store.lastLoadFailure)
    }

    func testTheFileIsReadableByAHuman() throws {
        // A dictionary keyed by UUID encodes as an unkeyed array of alternating keys and
        // values by default, which no DM can read or hand-edit. The whole point of JSON
        // here is that it can be opened in a text editor.
        let pawn = UUID()
        try StatsStore().save(StatsDocument(blocks: [pawn: StatBlock(armorClass: 17)]),
                              forMapAt: mapURL)
        let text = try String(contentsOf: directory
            .appendingPathComponent("dungeon.combat")
            .appendingPathComponent("stats.json"), encoding: .utf8)
        XCTAssertTrue(text.contains(pawn.uuidString), "the Pawn's id should be findable in the file")
        XCTAssertTrue(text.contains("armorClass"), "the fields should be named, not positional")
    }

    func testAnEmptyDocumentWritesNoFile() throws {
        // MapForge must not litter a DM's map folder with folders for fights that never
        // happened — the rule FogStore already follows.
        try StatsStore().save(StatsDocument(), forMapAt: mapURL)
        let path = directory.appendingPathComponent("dungeon.combat")
            .appendingPathComponent("stats.json").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testClearingEveryStatBlockRemovesTheFile() throws {
        // Deleting the last Combatant's numbers must not leave them on disk to reappear.
        let store = StatsStore()
        try store.save(StatsDocument(blocks: [UUID(): StatBlock()]), forMapAt: mapURL)
        try store.save(StatsDocument(), forMapAt: mapURL)
        XCTAssertNil(store.load(forMapAt: mapURL))
    }
}
