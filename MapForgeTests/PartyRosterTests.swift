import XCTest
@testable import MapForge

/// What the Party panel shows beside each Character: how many of its Pawns stand on the Map
/// the DM is running. A glance at the start of a session — decoration, never a constraint.
final class PartyRosterTests: XCTestCase {
    private let thorin = PartyCharacter(name: "Thorin")
    private let lyra = PartyCharacter(name: "Lyra")

    private func pawn(stampedBy character: PartyCharacter? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: character?.name ?? "1",
             colorHex: Pawn.defaultColorHex, brightSquares: 6,
             characterID: character?.id)
    }

    func testACharacterWithNoPawnsIsNotCounted() {
        XCTAssertEqual(PartyRoster.placedCount(of: thorin, among: []), 0)
    }

    func testEachStampIsCounted() {
        // Duplicates are allowed on purpose — a summon, a mirror image — so the count is
        // what makes an accidental double-drop visible without forbidding a deliberate one.
        let pawns = [pawn(stampedBy: thorin), pawn(stampedBy: thorin)]
        XCTAssertEqual(PartyRoster.placedCount(of: thorin, among: pawns), 2)
    }

    func testAnotherCharactersPawnsAreNotCounted() {
        XCTAssertEqual(PartyRoster.placedCount(of: thorin, among: [pawn(stampedBy: lyra)]), 0)
    }

    func testHandPlacedPawnsAreNotCounted() {
        // A Pawn the DM clicked onto the Map belongs to nobody, however it is labelled.
        XCTAssertEqual(PartyRoster.placedCount(of: thorin, among: [pawn()]), 0)
    }

    func testTheSameNameIsNotTheSameCharacter() {
        // Identity is the Character's id, never its name. A Pawn renamed live in the sidebar
        // keeps counting, and a hand-placed Pawn that happens to read "Thorin" never starts.
        var renamed = pawn(stampedBy: thorin)
        renamed.label = "Thorin the Bold"
        let impostor = pawn()
        XCTAssertEqual(PartyRoster.placedCount(of: thorin, among: [renamed, impostor]), 1)
    }

    func testADeletedCharacterLeavesItsPawnsUncounted() {
        // Deleting a Character never cascades: the Pawn stays on the Map, fully drawn, and
        // only stops being counted. Nothing here may report it as still placed.
        let deleted = PartyCharacter(name: "Grum")
        let orphan = pawn(stampedBy: deleted)
        XCTAssertEqual(PartyRoster.placedCount(of: thorin, among: [orphan]), 0)
        XCTAssertEqual(PartyRoster.placedCount(of: lyra, among: [orphan]), 0)
    }

    // MARK: Which Party the panel offers

    func testNoPartiesMeansNoActiveParty() {
        XCTAssertNil(PartyRoster.activeParty(in: PartyBook(), id: nil))
    }

    func testTheRememberedPartyIsTheActiveOne() {
        let eroi = Party(name: "Eroi")
        let book = PartyBook(parties: [Party(name: "Alleati"), eroi])
        XCTAssertEqual(PartyRoster.activeParty(in: book, id: eroi.id), eroi)
    }

    func testADeletedPartyFallsBackRatherThanVanishing() {
        // The remembered ID outlives the Party it named. Resolving to nothing would leave a
        // DM with a roster on disk and an empty panel until they noticed the picker.
        let book = PartyBook(parties: [Party(name: "Alleati")])
        XCTAssertEqual(PartyRoster.activeParty(in: book, id: UUID())?.name, "Alleati")
    }

    // MARK: Editing the roster

    func testACharacterIsAddedToTheNamedParty() {
        let eroi = Party(name: "Eroi")
        let book = PartyBook(parties: [eroi, Party(name: "Alleati")])
        let updated = PartyRoster.addCharacter(thorin, toPartyWith: eroi.id, in: book)
        XCTAssertEqual(updated.parties[0].characters, [thorin])
        XCTAssertEqual(updated.parties[1].characters, [])
    }

    func testEditingACharacterKeepsItsPlaceInTheOrder() {
        // The order is the DM's, so an edit must not shuffle the party list under them.
        let book = PartyBook(parties: [Party(name: "Eroi", characters: [thorin, lyra])])
        var renamed = thorin
        renamed.name = "Thorin the Bold"
        let updated = PartyRoster.updateCharacter(renamed, in: book)
        XCTAssertEqual(updated.parties[0].characters.map(\.name), ["Thorin the Bold", "Lyra"])
    }

    func testDeletingAPartyLeavesTheOthers() {
        let eroi = Party(name: "Eroi")
        let book = PartyBook(parties: [eroi, Party(name: "Alleati")])
        XCTAssertEqual(PartyRoster.deleteParty(id: eroi.id, from: book).parties.map(\.name),
                       ["Alleati"])
    }

    func testDeletingACharacterRemovesOnlyThatOne() {
        let book = PartyBook(parties: [Party(name: "Eroi", characters: [thorin, lyra])])
        XCTAssertEqual(PartyRoster.deleteCharacter(id: thorin.id, in: book)
                        .parties[0].characters, [lyra])
    }
}
