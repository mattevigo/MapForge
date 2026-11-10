import XCTest
@testable import MapForge

/// What the Combat tab says of the Pawns the Encounter Difficulty could not count: a note
/// giving how many on each side, and on hover, each one by its label and why.
final class EncounterDifficultyUncountedNoteTests: XCTestCase {
    private func uncounted(_ label: String, _ reason: UncountedPawn.Reason) -> UncountedPawn {
        UncountedPawn(id: UUID(), label: label, reason: reason)
    }

    private func reading(_ uncounted: [UncountedPawn]) -> EncounterDifficultyReading {
        EncounterDifficultyReading(difficulty: nil, uncounted: uncounted)
    }

    // MARK: The note

    func testTheNoteGivesTheCountsBySide() {
        let note = reading([uncounted("GG3", .noMonster), uncounted("Durga", .noNote),
                            uncounted("Ogre", .monsterNotInBestiary(monsterName: "Ogre"))])
            .uncountedNote
        XCTAssertEqual(note, "2 Creatures, 1 Player not counted")
    }

    func testTheNoteNamesOnlyTheSideWithUncountedPawns() {
        XCTAssertEqual(reading([uncounted("GG3", .noMonster)]).uncountedNote,
                       "1 Creature not counted")
        XCTAssertEqual(reading([uncounted("Durga", .noCharacter),
                                uncounted("Brom", .characterGone)]).uncountedNote,
                       "2 Players not counted")
    }

    func testThereIsNoNoteWhenEveryPawnCounted() {
        XCTAssertNil(reading([]).uncountedNote)
    }

    // MARK: On hover

    func testHoveringNamesEachPawnAndItsReasonOnALineOfItsOwn() {
        let help = reading([uncounted("GG3", .noMonster),
                            uncounted("Durga", .levelNotCounted(nil))]).uncountedHelp
        XCTAssertEqual(help, "GG3: no Monster\nDurga: the note has no level")
    }

    func testEachReasonIsSaid() {
        let said: [(UncountedPawn.Reason, String)] = [
            (.noMonster, "no Monster"),
            (.monsterNotInBestiary(monsterName: "Ogre"), "“Ogre” is not in the Bestiary"),
            (.challengeRatingNotCounted("10 (13 in lair)"),
             "Challenge Rating “10 (13 in lair)” cannot be counted"),
            (.challengeRatingNotCounted(nil), "the Monster has no Challenge Rating"),
            (.noCharacter, "no Character"),
            (.characterGone, "the Character no longer exists"),
            (.noNote, "the Character has no note"),
            (.noteNotFound(noteName: "Brom Mezzelfo"), "the note “Brom Mezzelfo” cannot be found"),
            (.levelNotCounted("Guerriero 3"), "level “Guerriero 3” cannot be counted"),
            (.levelNotCounted(nil), "the note has no level"),
        ]
        for (reason, text) in said {
            XCTAssertEqual(reason.title, text)
        }
    }
}
