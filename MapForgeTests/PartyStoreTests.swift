import XCTest
@testable import MapForge

final class PartyStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PartyStoreTests.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func store() -> PartyStore {
        PartyStore(directory: directory)
    }

    func testTheRosterSurvivesARelaunch() throws {
        // The whole point of the feature: a DM defines the party once, not once per session.
        let book = PartyBook(parties: [
            Party(name: "Eroi delle Terre di Confine",
                  characters: [PartyCharacter(name: "Thorin", colorHex: "#C81E1E",
                                              sightSquares: 6,
                                              noteName: "Thorin Scudodiquercia"),
                               PartyCharacter(name: "Ospite")])
        ])
        try store().save(book)
        XCTAssertEqual(store().load(), book)
    }

    func testNoRosterYetIsAnEmptyBookNotAnError() {
        // The normal case on a machine that has never defined a Party. An error here would
        // put a failure in front of a DM who has simply not used the feature yet.
        XCTAssertEqual(store().load(), PartyBook())
        XCTAssertNil(store().lastLoadFailure)
    }

    func testSavingCreatesApplicationSupportWhenItIsAbsent() throws {
        // Unlike FogStore, this store owns its directory: on a fresh machine
        // ~/Library/Application Support/MapForge does not exist, and the first Party a DM
        // defines must not be lost to a missing folder.
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path),
                       "precondition: the directory does not exist yet")
        try store().save(PartyBook(parties: [Party(name: "Eroi")]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store().fileURL.path))
    }

    func testAnUnreadableRosterIsReportedAndLeftOnDisk() throws {
        // A roster typed in by hand is irreplaceable. If it cannot be parsed the failure has
        // to be visible and the bytes left alone for recovery — never quietly replaced with
        // an empty book that the next save would then persist.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data(#"{"parties": [ truncated"#.utf8)
        try corrupt.write(to: store().fileURL)

        let store = self.store()
        XCTAssertEqual(store.load(), PartyBook())
        XCTAssertNotNil(store.lastLoadFailure)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }

    func testDeletingTheLastPartyRemovesTheFile() throws {
        // The FogStore rule: an emptied roster must not leave yesterday's Parties on disk to
        // reappear at the next launch.
        let store = self.store()
        try store.save(PartyBook(parties: [Party(name: "Eroi")]))
        try store.save(PartyBook())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(store.load(), PartyBook())
    }

    func testTheVersionIsStampedNotEchoed() throws {
        // FogDocument's rule: a file this app writes announces the shape this app writes, so
        // a hand-edited or older version number cannot survive a save and mislead a reader.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 99, "parties": [{"id": "\#(UUID().uuidString)", "name": "Eroi", "characters": []}]}"#.utf8)
            .write(to: store().fileURL)

        let store = self.store()
        try store.save(store.load())

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL))
        XCTAssertEqual((json as? [String: Any])?["version"] as? Int, PartyBook.current)
    }

    func testARosterWrittenBeforeNotesOpensWithEveryCharacterUnlinked() throws {
        // The real "Lost Boys" roster: typed numbers, no note. It must open, link nothing by
        // guessing from the name, and lose the typed numbers at the next write (ADR-0024).
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"""
        {"version": 1, "parties": [{"id": "\#(UUID().uuidString)", "name": "Lost Boys",
          "characters": [{"id": "\#(UUID().uuidString)", "name": "Durga",
                          "colorHex": "#FC4DE5", "sightSquares": 6, "isBig": false,
                          "initiativeBonus": -1, "armorClass": 14, "maxHP": 36}]}]}
        """#.utf8).write(to: store().fileURL)

        let durga = try XCTUnwrap(store().load().parties.first?.characters.first)
        XCTAssertEqual(durga.name, "Durga")
        XCTAssertEqual(durga.colorHex, "#FC4DE5")
        XCTAssertNil(durga.noteName, "linked by guessing")

        try store().save(store().load())
        let written = try String(contentsOf: store().fileURL, encoding: .utf8)
        for key in ["isBig", "initiativeBonus", "armorClass", "maxHP"] {
            XCTAssertFalse(written.contains(key), "\(key) survived the write")
        }
    }
}
