import XCTest
@testable import MapForge

/// What becoming an Item does to a Treasure's Face: `MonsterStamp`'s rule, with a Face an Item
/// gave treated as one a Monster gave.
final class ItemStampTests: XCTestCase {
    private let borsaFace = PawnFace(file: "borsa.png", origin: .item)
    private let cordaFace = PawnFace(file: "corda.png", origin: .item)

    func testATreasureWithNoFaceTakesTheItems() {
        XCTAssertEqual(ItemStamp.face(over: nil, from: cordaFace), cordaFace)
    }

    func testAFaceTakenFromTheOldItemIsReplacedByTheNewOnes() {
        XCTAssertEqual(ItemStamp.face(over: borsaFace, from: cordaFace), cordaFace)
    }

    func testAFaceTakenFromTheOldItemGoesWhenTheNewOneHasNone() {
        XCTAssertNil(ItemStamp.face(over: borsaFace, from: nil))
    }

    func testAFaceCutByHandOrGivenByACharacterIsNeverTouched() {
        let hand = PawnFace(file: "mine.png", origin: .hand)
        let durga = PawnFace(file: "durga.png", origin: .character)

        XCTAssertEqual(ItemStamp.face(over: hand, from: cordaFace), hand)
        XCTAssertEqual(ItemStamp.face(over: hand, from: nil), hand)
        XCTAssertEqual(ItemStamp.face(over: durga, from: cordaFace), durga)
    }

    /// A Monster's Face on a Pawn made a Treasure is one the app gave, as an Item's is, and
    /// a Monster's stamp replaces an Item's Face the same way.
    func testAFaceAMonsterOrAnItemGaveIsTheAppsToReplace() {
        let gnollFace = PawnFace(file: "gnoll.png", origin: .monster)

        XCTAssertEqual(ItemStamp.face(over: gnollFace, from: cordaFace), cordaFace)
        XCTAssertEqual(MonsterStamp.face(over: borsaFace, from: gnollFace), gnollFace)
    }
}
