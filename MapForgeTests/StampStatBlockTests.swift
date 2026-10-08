import XCTest
@testable import MapForge

/// Stamping carries a Character's combat numbers onto the Pawn it creates — read from the
/// Character's note, the only place they are written (ADR-0024).
///
/// ADR-0007's copy rule applying to more fields, not a new decision: the Pawn takes what the
/// note said at drag time and then leads its own life.
final class StampStatBlockTests: XCTestCase {
    /// Durga as her note writes her.
    private let durga = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                      initiativeBonus: -1)

    func testTheStampCopiesTheNotesNumbers() throws {
        let block = try XCTUnwrap(Stamp.statBlock(from: durga))
        XCTAssertEqual(block.initiativeBonus, -1)
        XCTAssertEqual(block.armorClass, 14)
        XCTAssertEqual(block.maxHP, 48)
    }

    func testAStampedCharacterArrivesAtFullHealth() {
        // A note records what a Character is at full strength; a Pawn records what it is
        // right now. The party walks into the dungeon undamaged.
        XCTAssertEqual(Stamp.statBlock(from: durga)?.currentHP, 48)
    }

    func testACharacterWithNoNoteStampsNoNumbers() {
        // Not a block of defaults: AC 10 and +0 would pass for the hero's own numbers. The
        // Pawn is one the DM types onto, as one placed by hand is.
        XCTAssertNil(Stamp.statBlock(from: nil))
    }

    func testANoteMissingHitPointsStampsAnIncompleteBlock() {
        // The tracker flags it rather than refusing it.
        let sketched = CharacterNote(name: "Abbozzo", armorClass: 12)
        XCTAssertFalse(Stamp.statBlock(from: sketched)?.isComplete ?? true)
        XCTAssertNil(Stamp.statBlock(from: sketched)?.maxHP, "absent must not become 0")
    }

    // MARK: The whole way round

    /// Linked once, survives the session, arrives on the Map with the note's numbers.
    @MainActor
    func testALinkedCharacterStampsItsNotesNumbersAfterARelaunch() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StampRoundTrip.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = AppState(preferences: DisplayPreferences(defaults: .standard),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.addParty(named: "Lost Boys")
        state.addCharacter(PartyCharacter(name: "Durga", noteName: "Durga Pietraferma"))

        // A new session opening the same roster file, and reading the same notes.
        let reopened = AppState(preferences: DisplayPreferences(defaults: .standard),
                                fogStore: FogStore(),
                                partyStore: PartyStore(directory: directory))
        reopened.characterNotes = CharacterNotes(notes: [durga])
        let character = try XCTUnwrap(reopened.partyBook.parties.first?.characters.first)
        XCTAssertEqual(character.noteName, "Durga Pietraferma", "the link did not survive the file")
        let block = try XCTUnwrap(Stamp.statBlock(from: reopened.note(for: character)))
        XCTAssertEqual(block.armorClass, 14)
        XCTAssertEqual(block.maxHP, 48)
        XCTAssertEqual(block.currentHP, 48)
    }

    @MainActor
    func testACharacterWhoseNoteWasRenamedIsUnlinked() {
        // The note's `name` changed in the vault: the Character still points at the old one,
        // and is said to have no note rather than quietly given another's numbers.
        let state = AppState(preferences: DisplayPreferences(defaults: .standard),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())))
        state.characterNotes = CharacterNotes(notes: [
            CharacterNote(name: "Durga la Pietraferma", armorClass: 14, maxHP: 48),
        ])
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma")
        XCTAssertNil(state.note(for: durga))
        XCTAssertTrue(state.isUnlinked(durga))

        state.bestiary = .reading
        XCTAssertFalse(state.isUnlinked(durga), "said while the notes were still being read")
    }
}
