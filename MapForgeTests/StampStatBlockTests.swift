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
}
