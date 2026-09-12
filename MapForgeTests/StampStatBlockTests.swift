import XCTest
@testable import MapForge

/// Stamping carries a Character's combat numbers onto the Pawn it creates.
///
/// ADR-0007's copy rule applying to more fields, not a new decision: the Pawn takes what
/// the Character had at drag time and then leads its own life.
final class StampStatBlockTests: XCTestCase {
    private let thorin = PartyCharacter(name: "Thorin",
                                        colorHex: "#1E90C8",
                                        sightSquares: 9,
                                        isBig: true,
                                        initiativeBonus: 2,
                                        armorClass: 18,
                                        maxHP: 44)

    func testTheStampCopiesTheCombatNumbers() {
        // The whole reason a Character carries them: a DM who typed their party's armour
        // class once does not retype it at every encounter.
        let block = Stamp.statBlock(from: thorin)
        XCTAssertEqual(block.initiativeBonus, 2)
        XCTAssertEqual(block.armorClass, 18)
        XCTAssertEqual(block.maxHP, 44)
    }

    func testAStampedCharacterArrivesAtFullHealth() {
        // A Character records what it is at full strength; a Pawn records what it is
        // right now. The party walks into the dungeon undamaged.
        XCTAssertEqual(Stamp.statBlock(from: thorin).currentHP, 44)
    }

    func testACharacterWithNoHitPointsStampsAnIncompleteBlock() {
        // A DM who has not filled in hit points still gets a Pawn; the tracker flags it
        // rather than refusing it.
        let unfinished = PartyCharacter(name: "Nameless")
        XCTAssertFalse(Stamp.statBlock(from: unfinished).isComplete)
    }

    func testAFreshCharacterStampsTheDefaultArmourClass() {
        // Not zero: an unarmoured creature is AC 10, and a 0 would make everything hit.
        XCTAssertEqual(Stamp.statBlock(from: PartyCharacter(name: "Nameless")).armorClass, 10)
    }

    // MARK: The whole way round

    /// Typed once, survives the session, arrives on the Map.
    ///
    /// The three tests above prove the Stamp copies what a Character holds; this proves a
    /// Character can *hold* what the DM typed. Both halves existed before the editor had
    /// the fields, so the numbers could only ever be their defaults — the pipe was
    /// complete and nothing could be poured into it.
    @MainActor
    func testNumbersTypedIntoTheEditorReachTheStampedPawn() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StampRoundTrip.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = AppState(preferences: DisplayPreferences(defaults: .standard),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.addParty(named: "The Wardens")
        state.addCharacter(PartyCharacter(name: "Thorin",
                                          initiativeBonus: 2,
                                          armorClass: 18,
                                          maxHP: 44))

        // A new session opening the same roster file.
        let reopened = AppState(preferences: DisplayPreferences(defaults: .standard),
                                fogStore: FogStore(),
                                partyStore: PartyStore(directory: directory))
        let thorin = try XCTUnwrap(reopened.partyBook.parties.first?.characters.first)
        let block = Stamp.statBlock(from: thorin)
        XCTAssertEqual(block.initiativeBonus, 2, "the initiative bonus did not survive the file")
        XCTAssertEqual(block.armorClass, 18, "the armour class did not survive the file")
        XCTAssertEqual(block.maxHP, 44, "the hit points did not survive the file")
        XCTAssertEqual(block.currentHP, 44, "the party should walk in undamaged")
    }

    /// A roster written before anyone could type hit points still opens.
    ///
    /// This is the shape every real `parties.json` is in right now: `initiativeBonus` and
    /// `armorClass` present at their defaults, `maxHP` absent entirely, because the editor
    /// had no fields for them. Such a Character must keep stamping an incomplete Block —
    /// flagged in the tracker, never refused — rather than throwing and taking the whole
    /// roster down with it.
    func testARosterWrittenBeforeTheFieldsExistedStillStamps() throws {
        let json = Data("""
        {"version":1,"parties":[{"id":"\(UUID().uuidString)","name":"Lost Boys",\
        "characters":[{"id":"\(UUID().uuidString)","name":"Durga","colorHex":"#FC4DE5",\
        "sightSquares":6,"isBig":false,"armorClass":10,"initiativeBonus":0}]}]}
        """.utf8)

        let book = try JSONDecoder().decode(PartyBook.self, from: json)
        let durga = try XCTUnwrap(book.parties.first?.characters.first)
        let block = Stamp.statBlock(from: durga)

        XCTAssertNil(block.maxHP, "absent hit points must stay absent, not become 0")
        XCTAssertFalse(block.isComplete, "the tracker should flag it, not hide it")
        XCTAssertEqual(block.armorClass, 10)
    }
}
