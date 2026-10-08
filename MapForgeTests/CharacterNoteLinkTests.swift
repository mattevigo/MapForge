import XCTest
@testable import MapForge

/// Saying which note is a Character's own (ADR-0024): what the roster editor's note box does,
/// proved without the box.
final class CharacterNoteLinkTests: XCTestCase {
    private let notes = CharacterNotes(notes: [
        CharacterNote(name: "Drusilla Frazer Mckenzie", armorClass: 14, maxHP: 10, initiativeBonus: 1),
        CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48, initiativeBonus: -1),
        CharacterNote(name: "Jonny Blade", armorClass: 13, maxHP: 38, initiativeBonus: 2),
        CharacterNote(name: "Zharyn il Velato", armorClass: 12, maxHP: 14, initiativeBonus: 2),
    ])

    // MARK: Searching

    func testSearchFindsANoteFromThePartOfTheNameTheDMRemembers() {
        XCTAssertEqual(notes.search("dur").map(\.name), ["Durga Pietraferma"])
        XCTAssertEqual(notes.search("VELATO").map(\.name), ["Zharyn il Velato"])
    }

    func testANameThatStartsWithTheQueryComesFirst() {
        // "d" starts Drusilla and Durga and sits inside Jonny Blade.
        XCTAssertEqual(notes.search("d").map(\.name),
                       ["Drusilla Frazer Mckenzie", "Durga Pietraferma", "Jonny Blade"])
    }

    func testSearchIgnoresAccentsAsTheMonsterSearchDoes() {
        let accented = CharacterNotes(notes: [CharacterNote(name: "Lodovico Mezzacorda Bèrtoli")])
        XCTAssertEqual(accented.search("bertoli").count, 1)
    }

    // MARK: Linking

    func testLinkingKeepsTheDMsLabel() {
        var durga = PartyCharacter(name: "Durga")
        durga.link(to: notes.notes[1])
        XCTAssertEqual(durga.name, "Durga")
        XCTAssertEqual(durga.noteName, "Durga Pietraferma")
    }

    func testACharacterCreatedFromANoteTakesItsFullName() {
        // For the DM to shorten: "Jonny Blade" → "Jonny".
        var created = PartyCharacter(name: "")
        created.link(to: notes.notes[2])
        XCTAssertEqual(created.name, "Jonny Blade")

        var blank = PartyCharacter(name: "   ")
        blank.link(to: notes.notes[2])
        XCTAssertEqual(blank.name, "Jonny Blade", "a name of spaces is no name")
    }

    func testRelinkingMovesToTheNewNote() {
        var durga = PartyCharacter(name: "Durga", noteName: "Drusilla Frazer Mckenzie")
        durga.link(to: notes.notes[1])
        XCTAssertEqual(durga.noteName, "Durga Pietraferma")
    }

    func testUnlinkingLeavesNoNumbers() {
        var durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma")
        durga.unlink()
        XCTAssertNil(durga.noteName)
        XCTAssertEqual(durga.name, "Durga")
        XCTAssertNil(Stamp.statBlock(from: notes.note(named: durga.noteName)))
    }

    // MARK: Saved through the roster

    @MainActor
    func testALinkSavedInTheRosterStampsTheNotesNumbers() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterNoteLink.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = AppState(preferences: DisplayPreferences(defaults: .standard),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.characterNotes = notes
        state.addParty(named: "Lost Boys")
        state.addCharacter(PartyCharacter(name: "Durga"))
        var durga = try XCTUnwrap(state.activeParty?.characters.first)
        XCTAssertTrue(state.isUnlinked(durga))

        // What the editor's Save does with a draft the DM linked.
        durga.link(to: try XCTUnwrap(notes.note(named: "Durga Pietraferma")))
        state.updateCharacter(durga)

        let saved = try XCTUnwrap(state.activeParty?.characters.first)
        XCTAssertFalse(state.isUnlinked(saved))
        let block = try XCTUnwrap(Stamp.statBlock(from: state.note(for: saved)))
        XCTAssertEqual(block.armorClass, 14)
        XCTAssertEqual(block.maxHP, 48)
        XCTAssertEqual(block.initiativeBonus, -1)
    }
}
