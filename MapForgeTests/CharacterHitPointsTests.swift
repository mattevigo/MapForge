import XCTest
@testable import MapForge

/// What a Character's row in the Party panel shows of its hit points: the DM's exact Health
/// Bar, the numbers as `current+temp/max`, and its exhaustion when it has any — or nothing,
/// for a Character with no note (ADR-0036, ADR-0037).
final class CharacterHitPointsTests: XCTestCase {
    /// Durga as her note writes her.
    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    private func durga(currentHP: Int? = nil, temporaryHP: Int = 0,
                       exhaustion: Int = 0) -> PartyCharacter {
        PartyCharacter(name: "Durga", noteName: "Durga Pietraferma",
                       sharedNumbers: SharedNumbers(currentHP: currentHP, temporaryHP: temporaryHP,
                                                    exhaustion: exhaustion))
    }

    func testAtHalfItShowsAHalfBloodiedBarAndItsNumbers() throws {
        let shown = try XCTUnwrap(CharacterHitPoints(character: durga(currentHP: 24),
                                                     note: durgaNote))

        let bar = try XCTUnwrap(shown.bar)
        XCTAssertEqual(bar.fill, 0.5)
        XCTAssertEqual(bar.tier, .bloodied)
        XCTAssertEqual(shown.numbers?.text, "24/48")
    }

    /// Temporary hit points lengthen the bar and are written `+N`, and never move the tier:
    /// the rules do not let them stop a creature being Bloodied.
    func testTemporaryHitPointsAreASegmentAndAPlusAndLeaveTheTier() throws {
        let shown = try XCTUnwrap(CharacterHitPoints(character: durga(currentHP: 24, temporaryHP: 12),
                                                     note: durgaNote))

        let bar = try XCTUnwrap(shown.bar)
        XCTAssertEqual(bar.fill, 0.5)
        XCTAssertEqual(bar.temporary, 0.25)
        XCTAssertEqual(bar.tier, .bloodied)
        XCTAssertEqual(shown.numbers?.text, "24+12/48")
    }

    /// A Character the evening has not touched is at its note's maximum.
    func testAnUntouchedCharacterIsAtItsNotesMaximum() throws {
        let shown = try XCTUnwrap(CharacterHitPoints(character: durga(), note: durgaNote))

        XCTAssertEqual(shown.bar?.tier, .healthy)
        XCTAssertEqual(shown.numbers?.text, "48/48")
    }

    /// The bar's tooltip names its tier, so it is never told by colour alone — and says
    /// nothing of what the table sees: that is each Pawn's own switch, not the Character's.
    func testTheBarsTooltipNamesItsTierAndNotTheTable() throws {
        XCTAssertEqual(CharacterHitPoints.tooltip(for: .healthy),
                       "Shared by every Pawn of this Character, on every Map — Healthy.")
        XCTAssertEqual(CharacterHitPoints.tooltip(for: .bloodied),
                       "Shared by every Pawn of this Character, on every Map — Bloodied.")
        XCTAssertEqual(CharacterHitPoints.tooltip(for: .critical),
                       "Shared by every Pawn of this Character, on every Map — Critical.")
    }

    func testExhaustionShowsItsMarker() throws {
        let shown = try XCTUnwrap(CharacterHitPoints(character: durga(currentHP: 24, exhaustion: 2),
                                                     note: durgaNote))

        XCTAssertEqual(shown.exhaustion?.marker, "E2")
        XCTAssertEqual(shown.exhaustion?.tooltip, "Exhaustion 2")
    }

    func testNoExhaustionShowsNoMarker() throws {
        let shown = try XCTUnwrap(CharacterHitPoints(character: durga(currentHP: 24), note: durgaNote))

        XCTAssertNil(shown.exhaustion)
    }

    /// Its Pawns keep their own numbers, so the roster has none of its own to show.
    func testACharacterWithNoNoteShowsNothing() {
        let unlinked = PartyCharacter(name: "Brom")

        XCTAssertNil(CharacterHitPoints(character: unlinked, note: nil))
    }

    /// A note that gives no maximum leaves nothing to be a fraction of: no bar and no
    /// numbers, rather than a guessed one — but the exhaustion is still the Character's.
    func testANoteWithNoMaximumShowsNoBarAndNoNumbers() throws {
        let note = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: nil,
                                 initiativeBonus: -1)
        let shown = try XCTUnwrap(CharacterHitPoints(character: durga(exhaustion: 1), note: note))

        XCTAssertNil(shown.bar)
        XCTAssertNil(shown.numbers)
        XCTAssertEqual(shown.exhaustion?.marker, "E1")
    }
}
