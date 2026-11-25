import XCTest
@testable import MapForge

/// Reordering Pawns from the Scene tab: a row dropped on another row of its group takes that
/// row's place, and the other Kinds keep theirs — the list *is* `fog.pawns`, so it is also
/// the stacking on the Map, lowest row on top.
final class PawnOrderTests: XCTestCase {
    private func pawn(_ label: String, _ kind: PawnKind) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: label, colorHex: Pawn.defaultColorHex,
             brightSquares: 0, kind: kind)
    }

    private func labels(_ pawns: [Pawn]?) -> [String]? { pawns?.map(\.label) }

    // Players and Creatures interleaved, as Add leaves them.
    private lazy var durga = pawn("Durga", .player)
    private lazy var goblinA = pawn("Goblin A", .creature)
    private lazy var rio = pawn("Rio", .player)
    private lazy var goblinB = pawn("Goblin B", .creature)
    private lazy var krathos = pawn("Krathos", .player)
    private lazy var pawns = [durga, goblinA, rio, goblinB, krathos]

    func testDraggedDownItLandsAfterTheRowItIsDroppedOn() {
        XCTAssertEqual(labels(PawnOrder.move(durga.id, onto: rio.id, in: pawns)),
                       ["Rio", "Goblin A", "Durga", "Goblin B", "Krathos"])
    }

    func testDraggedUpItLandsBeforeTheRowItIsDroppedOn() {
        XCTAssertEqual(labels(PawnOrder.move(krathos.id, onto: durga.id, in: pawns)),
                       ["Krathos", "Goblin A", "Durga", "Goblin B", "Rio"])
    }

    func testToTheBottomOfItsGroup() {
        XCTAssertEqual(labels(PawnOrder.move(durga.id, onto: krathos.id, in: pawns)),
                       ["Rio", "Goblin A", "Krathos", "Goblin B", "Durga"])
    }

    /// The other Kinds keep their places in the array, so a reorder of the Players never
    /// changes which Creature is on top of which.
    func testTheOtherKindsKeepTheirPlaces() {
        let moved = PawnOrder.move(krathos.id, onto: durga.id, in: pawns)
        XCTAssertEqual(moved?.filter { $0.kind == .creature }.map(\.label), ["Goblin A", "Goblin B"])
        XCTAssertEqual(moved?[1].label, "Goblin A")
        XCTAssertEqual(moved?[3].label, "Goblin B")
    }

    /// The groups are the Kinds: a Player dropped among the Creatures is refused.
    func testADropOnAnotherKindIsRefused() {
        XCTAssertNil(PawnOrder.move(durga.id, onto: goblinB.id, in: pawns))
    }

    func testADropOnItselfChangesNothing() {
        XCTAssertNil(PawnOrder.move(rio.id, onto: rio.id, in: pawns))
    }

    /// The line drawn while hovering says where the row will land, and is not drawn at all
    /// where the drop would be refused.
    func testTheLandingMatchesTheMove() {
        XCTAssertEqual(PawnOrder.landing(durga.id, onto: rio.id, in: pawns), .after)
        XCTAssertEqual(PawnOrder.landing(krathos.id, onto: durga.id, in: pawns), .before)
        XCTAssertNil(PawnOrder.landing(durga.id, onto: goblinB.id, in: pawns))
        XCTAssertNil(PawnOrder.landing(rio.id, onto: rio.id, in: pawns))
    }

    /// The list and the document can disagree for a frame after a delete.
    func testAPawnThatIsGoneIsRefused() {
        XCTAssertNil(PawnOrder.move(UUID(), onto: rio.id, in: pawns))
        XCTAssertNil(PawnOrder.move(rio.id, onto: UUID(), in: pawns))
    }
}
