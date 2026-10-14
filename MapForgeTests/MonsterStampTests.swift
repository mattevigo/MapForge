import XCTest
@testable import MapForge

/// What saying "this Creature is a Gnoll Guerriero" does to the Pawn and its Stat Block.
///
/// A copy, as a Character's Stamp is (ADR-0020). The rules pinned here are the ones a DM
/// would otherwise discover mid-fight: what a stamp heals, what it leaves alone, and what a
/// row of identical gnolls ends up being called.
final class MonsterStampTests: XCTestCase {
    private let gnoll = Monster(name: "Gnoll Guerriero", armorClass: 15, hitPoints: 27,
                                initiativeBonus: 1)
    private let capo = Monster(name: "Capo Goblin", armorClass: 17, hitPoints: 45,
                               initiativeBonus: 2)

    // MARK: The Stat Block

    func testAFreshCreatureTakesTheMonstersNumbersAndArrivesWhole() {
        let block = MonsterStamp.statBlock(from: gnoll, over: StatBlock())
        XCTAssertEqual(block.armorClass, 15)
        XCTAssertEqual(block.initiativeBonus, 1)
        XCTAssertEqual(block.maxHP, 27)
        XCTAssertEqual(block.currentHP, 27)
        XCTAssertTrue(block.isComplete)
    }

    func testBecomingADifferentMonsterMeansArrivingWhole() {
        // The DM's call: a gnoll at 12/27 made into a Capo is a Capo, not a 12/45 hybrid.
        let wounded = StatBlock(initiativeBonus: 1, armorClass: 15, currentHP: 12, maxHP: 27)
        let block = MonsterStamp.statBlock(from: capo, over: wounded)
        XCTAssertEqual(block.currentHP, 45)
        XCTAssertEqual(block.maxHP, 45)
        XCTAssertEqual(block.armorClass, 17)
    }

    func testWhatBelongsToTheFightIsLeftAlone() {
        let suffering = StatBlock(currentHP: 12, maxHP: 27, temporaryHP: 5,
                                  conditions: [.prone, .poisoned], exhaustion: 2,
                                  isConcentrating: true, isInCombat: false)
        let block = MonsterStamp.statBlock(from: capo, over: suffering)
        XCTAssertEqual(block.temporaryHP, 5)
        XCTAssertEqual(block.conditions, [.prone, .poisoned])
        XCTAssertEqual(block.exhaustion, 2)
        XCTAssertTrue(block.isConcentrating)
        XCTAssertFalse(block.isInCombat)
    }

    func testAMonsterStampsOnlyWhatItsNoteHas() {
        // A note with no `hp` must not wipe hit points the DM typed by hand.
        let typed = StatBlock(initiativeBonus: 4, armorClass: 13, currentHP: 9, maxHP: 20)
        let block = MonsterStamp.statBlock(from: Monster(name: "Abbozzo"), over: typed)
        XCTAssertEqual(block, typed)
    }

    // MARK: Asking before healing

    func testAFirstStampAsksNothing() {
        XCTAssertNil(MonsterStamp.healing(from: gnoll, over: StatBlock()))
    }

    func testOverwritingHitPointsThatExistIsNamed() {
        let wounded = StatBlock(currentHP: 12, maxHP: 27)
        XCTAssertEqual(MonsterStamp.healing(from: capo, over: wounded),
                       MonsterStamp.Healing(before: "12/27", after: "45/45"))
    }

    func testHandTypedHitPointsCountAsExisting() {
        // No previous Monster, but the DM typed these in the tracker: still theirs to lose.
        XCTAssertNotNil(MonsterStamp.healing(from: gnoll, over: StatBlock(currentHP: 30, maxHP: 30)))
    }

    func testAStampThatWouldChangeNoHitPointsAsksNothing() {
        // A dialog when nothing can be lost is one the DM learns to click through.
        XCTAssertNil(MonsterStamp.healing(from: gnoll, over: StatBlock(currentHP: 27, maxHP: 27)))
        XCTAssertNil(MonsterStamp.healing(from: Monster(name: "Abbozzo"),
                                          over: StatBlock(currentHP: 3, maxHP: 9)))
    }

    func testCurrentHitPointsWithNoMaximumStillReadSensibly() {
        XCTAssertEqual(MonsterStamp.healing(from: gnoll, over: StatBlock(currentHP: 5))?.before,
                       "5")
    }

    // MARK: The label

    private func pawn(_ label: String) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature)
    }

    func testInitials() {
        XCTAssertEqual(MonsterStamp.initials(of: "Gnoll Guerriero"), "GG")
        XCTAssertEqual(MonsterStamp.initials(of: "Capo Goblin"), "CG")
        XCTAssertEqual(MonsterStamp.initials(of: "Naga d'Ossa"), "ND")
        XCTAssertEqual(MonsterStamp.initials(of: "  melma   grigia (antica) "), "MGA")
    }

    func testASingleWordTakesTwoLetters() {
        // "W1" is too thin to read at a glance across a table.
        XCTAssertEqual(MonsterStamp.initials(of: "Wraith"), "Wr")
        XCTAssertEqual(MonsterStamp.initials(of: "ogre"), "Og")
        XCTAssertEqual(MonsterStamp.initials(of: "X"), "X")
    }

    func testABornNumberBecomesATalkingLabel() {
        XCTAssertEqual(MonsterStamp.label(for: gnoll, replacing: "3", among: []), "GG1")
    }

    func testTheNumberFollowsTheHighestAlreadyOnTheMap() {
        let onMap = [pawn("GG1"), pawn("GG4"), pawn("CG9"), pawn("Grog")]
        XCTAssertEqual(MonsterStamp.label(for: gnoll, replacing: "7", among: onMap), "GG5")
    }

    func testTwoMonstersSharingInitialsShareOneNumbering() {
        // Gnoll Guerriero and Goblin Guerriero are both GG. A label's job in the Order is
        // to be unique; the colour and the reference view say which is which.
        let goblin = Monster(name: "Goblin Guerriero")
        XCTAssertEqual(MonsterStamp.label(for: goblin, replacing: "2",
                                          among: [pawn("GG1"), pawn("GG2")]), "GG3")
    }

    func testALabelTheDMTypedIsNeverTouched() {
        XCTAssertEqual(MonsterStamp.label(for: gnoll, replacing: "Yeenoghu's pet", among: []),
                       "Yeenoghu's pet")
        XCTAssertEqual(MonsterStamp.label(for: gnoll, replacing: "", among: []), "")
    }

    func testALongerPrefixIsNotMistakenForThisOne() {
        // "GGX3" is somebody else's label, not the third GG.
        XCTAssertEqual(MonsterStamp.label(for: gnoll, replacing: "1",
                                          among: [pawn("GGX3"), pawn("GG")]), "GG1")
    }

    // MARK: The Face

    private let gnollFace = PawnFace(file: "gnoll.png", origin: .monster)
    private let ogreFace = PawnFace(file: "ogre.png", origin: .monster)

    func testAPawnWithNoFaceTakesTheMonsters() {
        XCTAssertEqual(MonsterStamp.face(over: nil, from: ogreFace), ogreFace)
    }

    func testAFaceTakenFromTheOldMonsterIsReplacedByTheNewOnes() {
        XCTAssertEqual(MonsterStamp.face(over: gnollFace, from: ogreFace), ogreFace)
    }

    /// The colour shows again, as a label taken from the old Monster's initials is replaced.
    func testAFaceTakenFromTheOldMonsterGoesWhenTheNewOneHasNone() {
        XCTAssertNil(MonsterStamp.face(over: gnollFace, from: nil))
    }

    func testAFaceCutByHandIsNeverTouched() {
        let hand = PawnFace(file: "mine.png", origin: .hand)

        XCTAssertEqual(MonsterStamp.face(over: hand, from: ogreFace), hand)
        XCTAssertEqual(MonsterStamp.face(over: hand, from: nil), hand)
    }

    func testAFaceACharacterGaveIsNeverTouched() {
        let durga = PawnFace(file: "durga.png", origin: .character)

        XCTAssertEqual(MonsterStamp.face(over: durga, from: ogreFace), durga)
    }
}
