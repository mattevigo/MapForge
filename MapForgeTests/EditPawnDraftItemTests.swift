import XCTest
@testable import MapForge

/// Choosing an Item in the Edit Pawn sheet, as far as the draft is concerned: a Treasure is
/// said to be an Item as a Creature is said to be a Monster, and the label follows by the
/// same rule. There are no numbers to stamp.
final class EditPawnDraftItemTests: XCTestCase {
    private let borsa = Item(name: "Borsa")
    private let gemma = Item(name: "Gemma di Fuoco")

    private func treasure(_ label: String = "3", itemName: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: label, colorHex: "#D4A017",
             brightSquares: 0, kind: .treasure, itemName: itemName)
    }

    // MARK: Picking

    func testPickingAnItemNamesItAndLabelsTheTreasureFromItsInitials() {
        var draft = EditPawnDraft(pawn: treasure())
        draft.pick(gemma, among: [])
        XCTAssertEqual(draft.itemName, "Gemma di Fuoco")
        XCTAssertEqual(draft.label, "GDF1")
    }

    func testTheNumberFollowsTheHighestLabelOfTheSameInitialsOnTheMap() {
        let pawn = treasure()
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(borsa, among: [pawn, treasure("Bo1", itemName: "Borsa"),
                                  treasure("Bo4", itemName: "Borsa")])
        XCTAssertEqual(draft.label, "Bo5")
    }

    func testANewItemRelabelsWhatTheOldOneLabelled() {
        let bo1 = treasure("Bo1", itemName: "Borsa")
        var draft = EditPawnDraft(pawn: bo1)
        draft.pick(gemma, among: [bo1])
        XCTAssertEqual(draft.label, "GDF1")
    }

    func testALabelTheDMTypedIsNeverTouched() {
        var draft = EditPawnDraft(pawn: treasure("Il forziere"))
        draft.pick(borsa, among: [])
        XCTAssertEqual(draft.label, "Il forziere")

        var typed = EditPawnDraft(pawn: treasure("Wr2", itemName: "Borsa"))
        typed.pick(gemma, among: [])
        XCTAssertEqual(typed.label, "Wr2")
    }

    func testChangingOnesMindRelabelsToo() {
        var draft = EditPawnDraft(pawn: treasure())
        draft.pick(borsa, among: [])
        draft.pick(gemma, among: [])
        XCTAssertEqual(draft.label, "GDF1")
    }

    func testClearingForgetsTheItemAndGivesTheBornLabelBack() {
        var draft = EditPawnDraft(pawn: treasure("3"))
        draft.pick(borsa, among: [])
        draft.clearItem()
        XCTAssertNil(draft.itemName)
        XCTAssertEqual(draft.label, "3")
    }

    // MARK: Committing

    func testTheItemReachesThePawn() {
        var draft = EditPawnDraft(pawn: treasure())
        draft.pick(borsa, among: [])
        XCTAssertEqual(draft.applied(to: treasure()).itemName, "Borsa")
    }

    func testOnlyATreasureIsAnItem() {
        // The box is hidden for the other Kinds; the memory goes with it.
        var draft = EditPawnDraft(pawn: treasure(itemName: "Borsa"))
        draft.kind = .creature
        XCTAssertNil(draft.applied(to: treasure()).itemName)
        draft.kind = .player
        XCTAssertNil(draft.applied(to: treasure()).itemName)
        draft.kind = .treasure
        XCTAssertEqual(draft.applied(to: treasure()).itemName, "Borsa")
    }

    func testOnlyATreasureCanBeAnItem() {
        XCTAssertTrue(PawnKind.treasure.canBeItem)
        XCTAssertFalse(PawnKind.creature.canBeItem)
        XCTAssertFalse(PawnKind.player.canBeItem)
    }

    // MARK: What OK says

    func testOKBecomesTheItemOnlyWhenTheItemChanged() {
        var draft = EditPawnDraft(pawn: treasure(itemName: "Borsa"))
        XCTAssertNil(draft.itemToBecome, "the Item is untouched")
        draft.pick(gemma, among: [])
        XCTAssertEqual(draft.itemToBecome, "Gemma di Fuoco")
        draft.pick(borsa, among: [])
        XCTAssertNil(draft.itemToBecome, "away and back again is untouched")
        draft.clearItem()
        XCTAssertNil(draft.itemToBecome)

        var other = EditPawnDraft(pawn: treasure())
        other.pick(borsa, among: [])
        other.kind = .creature
        XCTAssertNil(other.itemToBecome, "a Creature is never an Item")
    }
}
