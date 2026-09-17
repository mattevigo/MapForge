import XCTest
@testable import MapForge

/// Choosing a Monster in the Edit Pawn sheet, as far as the draft is concerned.
///
/// The draft only *names* the Monster and shows the DM what that does to the fields they can
/// see; the numbers are stamped on OK, by `AppState.updatePawn` (ADR-0021).
final class EditPawnDraftMonsterTests: XCTestCase {
    private let gnoll = Monster(name: "Gnoll Guerriero", hitPoints: 27)
    private let ogre = Monster(name: "Ogre", hitPoints: 68, isBig: true)

    private func creature(_ label: String = "3", monsterName: String? = nil,
                          isBig: Bool = false) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, isBig: isBig, monsterName: monsterName)
    }

    // MARK: Picking

    func testPickingAMonsterNamesItSizesThePawnAndLabelsIt() {
        var draft = EditPawnDraft(pawn: creature())
        draft.pick(ogre, among: [])
        XCTAssertEqual(draft.monsterName, "Ogre")
        XCTAssertTrue(draft.isBig)
        XCTAssertEqual(draft.label, "Og1")
    }

    func testPickingASmallerMonsterShrinksThePawnAgain() {
        var draft = EditPawnDraft(pawn: creature())
        draft.pick(ogre, among: [])
        draft.pick(gnoll, among: [])
        XCTAssertFalse(draft.isBig)
    }

    func testChangingOnesMindRelabelsToo() {
        // "Og1" was the app's label, not the DM's: a second pick may replace it.
        var draft = EditPawnDraft(pawn: creature())
        draft.pick(ogre, among: [])
        draft.pick(gnoll, among: [])
        XCTAssertEqual(draft.label, "GG1")
    }

    func testALabelTheDMTypedSurvivesAPick() {
        var draft = EditPawnDraft(pawn: creature("Il Capobranco"))
        draft.pick(gnoll, among: [])
        XCTAssertEqual(draft.label, "Il Capobranco")

        // Typed into the sheet after a pick counts as typed, too.
        var second = EditPawnDraft(pawn: creature())
        second.pick(ogre, among: [])
        second.label = "Grunk"
        second.pick(gnoll, among: [])
        XCTAssertEqual(second.label, "Grunk")
    }

    func testClearingForgetsTheMonsterAndGivesTheBornLabelBack() {
        var draft = EditPawnDraft(pawn: creature("3"))
        draft.pick(gnoll, among: [])
        draft.clearMonster()
        XCTAssertNil(draft.monsterName)
        XCTAssertEqual(draft.label, "3")
    }

    func testClearingKeepsALabelThatWasCommittedEarlier() {
        // "GG2" came from a pick in an earlier sheet. It is the Pawn's label now, and the
        // Order has been calling it that.
        var draft = EditPawnDraft(pawn: creature("GG2", monsterName: "Gnoll Guerriero"))
        draft.clearMonster()
        XCTAssertEqual(draft.label, "GG2")
    }

    // MARK: Committing

    func testTheMonsterReachesThePawn() {
        var draft = EditPawnDraft(pawn: creature())
        draft.pick(gnoll, among: [])
        XCTAssertEqual(draft.applied(to: creature()).monsterName, "Gnoll Guerriero")
    }

    func testOnlyACreatureIsAMonster() {
        // The box is hidden for the other Kinds; the memory goes with it.
        var draft = EditPawnDraft(pawn: creature(monsterName: "Gnoll Guerriero"))
        draft.kind = .treasure
        XCTAssertNil(draft.applied(to: creature()).monsterName)
        draft.kind = .creature
        XCTAssertEqual(draft.applied(to: creature()).monsterName, "Gnoll Guerriero")
    }

    // MARK: When OK stamps

    func testAChangedMonsterIsStamped() {
        var draft = EditPawnDraft(pawn: creature())
        XCTAssertNil(draft.monsterToStamp)
        draft.pick(gnoll, among: [])
        XCTAssertEqual(draft.monsterToStamp, "Gnoll Guerriero")
    }

    func testAnUntouchedMonsterIsNotStampedAgain() {
        // Or opening a wounded gnoll to change its colour would heal it.
        var draft = EditPawnDraft(pawn: creature(monsterName: "Gnoll Guerriero"))
        draft.colorHex = "#00FF00"
        XCTAssertNil(draft.monsterToStamp)
        // Away and back again inside one sheet is still untouched.
        draft.pick(ogre, among: [])
        draft.pick(gnoll, among: [])
        XCTAssertNil(draft.monsterToStamp)
    }

    func testAClearedMonsterOrAnotherKindStampsNothing() {
        var draft = EditPawnDraft(pawn: creature(monsterName: "Gnoll Guerriero"))
        draft.clearMonster()
        XCTAssertNil(draft.monsterToStamp)

        var other = EditPawnDraft(pawn: creature())
        other.pick(gnoll, among: [])
        other.kind = .player
        XCTAssertNil(other.monsterToStamp)
    }

    // MARK: Asking before healing

    private let shelf = Bestiary(monsters: [Monster(name: "Gnoll Guerriero", hitPoints: 27),
                                            Monster(name: "Ogre", hitPoints: 68, isBig: true)])

    func testOKAsksOnlyWhenTheStampWouldOverwriteHitPoints() {
        var draft = EditPawnDraft(pawn: creature("GG1", monsterName: "Gnoll Guerriero"))
        let wounded = StatBlock(currentHP: 12, maxHP: 27)
        XCTAssertNil(draft.healing(over: wounded, in: shelf), "the Monster is untouched")

        draft.pick(ogre, among: [])
        XCTAssertEqual(draft.healing(over: wounded, in: shelf),
                       MonsterStamp.Healing(before: "12/27", after: "68/68"))
        XCTAssertNil(draft.healing(over: StatBlock(), in: shelf), "nothing to lose")
        XCTAssertNil(draft.healing(over: wounded, in: Bestiary()), "nothing will be stamped")
    }
}
