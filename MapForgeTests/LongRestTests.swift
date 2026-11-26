import XCTest
@testable import MapForge

/// What a Long Rest does to the active Party's Characters, worked out without `AppState`:
/// full hit points, no temporary hit points, one exhaustion level fewer, for every Character
/// with a note — and the lines the confirmation names them by (ADR-0037).
final class LongRestTests: XCTestCase {
    private let durgaNote = CharacterNote(name: "Durga Pietraferma", maxHP: 48)

    /// The Long Rest of `characters`, each of whose notes is looked up in `notes` by name.
    private func longRest(of characters: [PartyCharacter],
                          notes: [CharacterNote]) -> LongRest {
        let notes = CharacterNotes(notes: notes)
        return LongRest(of: characters) { notes.note(named: $0.noteName) }
    }

    func testAWoundedTiredCharacterWakesWholeAndOneLevelLessTired() throws {
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma",
                                   sharedNumbers: SharedNumbers(currentHP: 12, exhaustion: 2))

        let rest = longRest(of: [durga], notes: [durgaNote])

        let rested = try XCTUnwrap(rest.rested.first)
        let block = rested.sharedNumbers.laid(over: StatBlock(), maxHP: 48)
        XCTAssertEqual([block.currentHP, block.exhaustion], [48, 1])
        XCTAssertEqual(rest.lines.map(\.text), ["Durga 12/48 → 48/48, exhaustion 2 → 1"])
    }

    func testTemporaryHitPointsAreLostAndTheLineSaysSo() throws {
        let krathos = PartyCharacter(name: "Krathos", noteName: "Krathos", sharedNumbers: SharedNumbers(temporaryHP: 5))

        let rest = longRest(of: [krathos], notes: [CharacterNote(name: "Krathos", maxHP: 30)])

        XCTAssertEqual(try XCTUnwrap(rest.rested.first).sharedNumbers.temporaryHP, 0)
        XCTAssertEqual(rest.lines.map(\.text), ["Krathos +5 temp → 0"])
    }

    func testExhaustionNeverDropsBelowNone() throws {
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma", sharedNumbers: SharedNumbers(currentHP: 40))

        let rest = longRest(of: [durga], notes: [durgaNote])

        XCTAssertEqual(try XCTUnwrap(rest.rested.first).sharedNumbers.exhaustion, 0)
        XCTAssertEqual(rest.lines.map(\.text), ["Durga 40/48 → 48/48"])
    }

    func testACharacterWithNoNoteIsPassedOver() {
        // Its Pawns keep their own numbers, and there is no maximum to return it to.
        let ayla = PartyCharacter(name: "Ayla", sharedNumbers: SharedNumbers(currentHP: 3, temporaryHP: 2, exhaustion: 2))

        let rest = longRest(of: [ayla], notes: [durgaNote])

        XCTAssertEqual(rest.rested, [])
        XCTAssertEqual(rest.lines, [])
        XCTAssertFalse(rest.changesAnyone)
    }

    func testACharacterAlreadyRestedProducesNoLine() {
        // At full however it got there: never wounded, or healed to exactly the maximum.
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma")
        let krathos = PartyCharacter(name: "Krathos", noteName: "Krathos", sharedNumbers: SharedNumbers(currentHP: 30))
        let ayla = PartyCharacter(name: "Ayla", noteName: "Ayla", sharedNumbers: SharedNumbers(exhaustion: 2))

        let rest = longRest(of: [durga, krathos, ayla],
                            notes: [durgaNote, CharacterNote(name: "Krathos", maxHP: 30),
                                    CharacterNote(name: "Ayla", maxHP: 22)])

        XCTAssertEqual(rest.rested.map(\.name), ["Ayla"])
        XCTAssertEqual(rest.lines.map(\.text), ["Ayla exhaustion 2 → 1"])
    }

    func testANoteWithNoMaximumLeavesTheHitPointsAsTheyAre() throws {
        // Nothing to return them to; making them none would lose the DM's number.
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma",
                                   sharedNumbers: SharedNumbers(currentHP: 12, exhaustion: 1))

        let rest = longRest(of: [durga], notes: [CharacterNote(name: "Durga Pietraferma")])

        let rested = try XCTUnwrap(rest.rested.first)
        XCTAssertEqual([rested.sharedNumbers.currentHP, rested.sharedNumbers.exhaustion], [12, 0])
        XCTAssertEqual(rest.lines.map(\.text), ["Durga exhaustion 1 → 0"])
    }
}
