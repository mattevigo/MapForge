import XCTest
@testable import MapForge

/// What saying "this Pawn is that definition" — a Creature a Gnoll Guerriero, a Treasure a
/// Borsa — does to its label and its Face: one rule for a Monster and an Item alike.
///
/// A copy, as a Character's Stamp is (ADR-0020). What a row of identical gnolls ends up being
/// called, and which Faces the app may replace, are the rules a DM would otherwise discover
/// mid-fight.
final class DefinitionStampTests: XCTestCase {
    // MARK: The label

    private func pawn(_ label: String) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature)
    }

    func testInitials() {
        XCTAssertEqual(DefinitionStamp.initials(of: "Gnoll Guerriero"), "GG")
        XCTAssertEqual(DefinitionStamp.initials(of: "Capo Goblin"), "CG")
        XCTAssertEqual(DefinitionStamp.initials(of: "Naga d'Ossa"), "ND")
        XCTAssertEqual(DefinitionStamp.initials(of: "  melma   grigia (antica) "), "MGA")
    }

    func testASingleWordTakesTwoLetters() {
        // "W1" is too thin to read at a glance across a table.
        XCTAssertEqual(DefinitionStamp.initials(of: "Wraith"), "Wr")
        XCTAssertEqual(DefinitionStamp.initials(of: "ogre"), "Og")
        XCTAssertEqual(DefinitionStamp.initials(of: "X"), "X")
    }

    func testABornNumberBecomesATalkingLabel() {
        XCTAssertEqual(DefinitionStamp.label(named: "Gnoll Guerriero", replacing: "3", among: []),
                       "GG1")
        XCTAssertEqual(DefinitionStamp.label(named: "Borsa", replacing: "3", among: []), "Bo1")
    }

    func testTheNumberFollowsTheHighestAlreadyOnTheMap() {
        let onMap = [pawn("GG1"), pawn("GG4"), pawn("CG9"), pawn("Grog")]
        XCTAssertEqual(DefinitionStamp.label(named: "Gnoll Guerriero", replacing: "7",
                                             among: onMap), "GG5")
    }

    func testTwoDefinitionsSharingInitialsShareOneNumbering() {
        // Gnoll Guerriero and Goblin Guerriero are both GG. A label's job in the Order is
        // to be unique; the colour and the reference view say which is which.
        XCTAssertEqual(DefinitionStamp.label(named: "Goblin Guerriero", replacing: "2",
                                             among: [pawn("GG1"), pawn("GG2")]), "GG3")
    }

    func testALabelTheDMTypedIsNeverTouched() {
        XCTAssertEqual(DefinitionStamp.label(named: "Gnoll Guerriero", replacing: "Yeenoghu's pet",
                                             among: []), "Yeenoghu's pet")
        XCTAssertEqual(DefinitionStamp.label(named: "Gnoll Guerriero", replacing: "", among: []), "")
    }

    func testALabelThePreviousDefinitionGaveIsReplaced() {
        XCTAssertEqual(DefinitionStamp.label(named: "Ogre", replacing: "GG1",
                                             from: "Gnoll Guerriero", among: []), "Og1")
        XCTAssertEqual(DefinitionStamp.label(named: "Ogre", replacing: "GG1", among: []), "GG1",
                       "without the previous definition, GG1 is the DM's")
    }

    func testALongerPrefixIsNotMistakenForThisOne() {
        // "GGX3" is somebody else's label, not the third GG.
        XCTAssertEqual(DefinitionStamp.label(named: "Gnoll Guerriero", replacing: "1",
                                             among: [pawn("GGX3"), pawn("GG")]), "GG1")
    }

    // MARK: The Face

    private let gnollFace = PawnFace(file: "gnoll.png", origin: .monster)
    private let ogreFace = PawnFace(file: "ogre.png", origin: .monster)
    private let borsaFace = PawnFace(file: "borsa.png", origin: .item)
    private let cordaFace = PawnFace(file: "corda.png", origin: .item)

    func testAPawnWithNoFaceTakesTheDefinitions() {
        XCTAssertEqual(DefinitionStamp.face(over: nil, from: ogreFace), ogreFace)
        XCTAssertEqual(DefinitionStamp.face(over: nil, from: cordaFace), cordaFace)
    }

    func testAFaceTakenFromTheOldDefinitionIsReplacedByTheNewOnes() {
        XCTAssertEqual(DefinitionStamp.face(over: gnollFace, from: ogreFace), ogreFace)
        XCTAssertEqual(DefinitionStamp.face(over: borsaFace, from: cordaFace), cordaFace)
    }

    /// The colour shows again, as a label taken from the old definition's initials is replaced.
    func testAFaceTakenFromTheOldDefinitionGoesWhenTheNewOneHasNone() {
        XCTAssertNil(DefinitionStamp.face(over: gnollFace, from: nil))
        XCTAssertNil(DefinitionStamp.face(over: borsaFace, from: nil))
    }

    /// A Monster's Face on a Pawn made a Treasure is one the app gave, as an Item's is, and
    /// the other way round.
    func testAFaceAMonsterOrAnItemGaveIsTheAppsToReplace() {
        XCTAssertEqual(DefinitionStamp.face(over: gnollFace, from: cordaFace), cordaFace)
        XCTAssertEqual(DefinitionStamp.face(over: borsaFace, from: gnollFace), gnollFace)
    }

    func testAFaceCutByHandIsNeverTouched() {
        let hand = PawnFace(file: "mine.png", origin: .hand)

        XCTAssertEqual(DefinitionStamp.face(over: hand, from: ogreFace), hand)
        XCTAssertEqual(DefinitionStamp.face(over: hand, from: cordaFace), hand)
        XCTAssertEqual(DefinitionStamp.face(over: hand, from: nil), hand)
    }

    func testAFaceACharacterGaveIsNeverTouched() {
        let durga = PawnFace(file: "durga.png", origin: .character)

        XCTAssertEqual(DefinitionStamp.face(over: durga, from: ogreFace), durga)
        XCTAssertEqual(DefinitionStamp.face(over: durga, from: cordaFace), durga)
    }
}
