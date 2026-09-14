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
                                              sightSquares: 6, isBig: false)])
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

    func testARosterWrittenBeforeCombatNumbersStillLoads() throws {
        // A DM who has been using MapForge since 1.2.0 has a parties.json with no
        // initiative bonus, armour class or hit points in it. It must open, and the
        // Characters in it must come back with sensible numbers rather than zeroes that
        // would make everything hit.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"""
        {"version": 1, "parties": [{"id": "\#(UUID().uuidString)", "name": "Eroi",
          "characters": [{"id": "\#(UUID().uuidString)", "name": "Thorin",
                          "colorHex": "#1E90C8", "sightSquares": 9, "isBig": false}]}]}
        """#.utf8).write(to: store().fileURL)

        let character = try XCTUnwrap(store().load().parties.first?.characters.first)
        XCTAssertEqual(character.name, "Thorin")
        XCTAssertEqual(character.initiativeBonus, 0)
        XCTAssertEqual(character.armorClass, StatBlock.defaultArmorClass)
        XCTAssertNil(character.maxHP)
    }
}
