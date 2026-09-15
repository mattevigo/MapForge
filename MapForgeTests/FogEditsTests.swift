import XCTest
@testable import MapForge

/// `FogEdits` after the Wall Editor lost its tools (ADR-0013): Walls, and the undo stack
/// that tracing them needs.
///
/// The Light and Pawn cases that used to live here did not move with their features — the
/// Live View's edits are not undoable, so there is no buffer to test. What survived is
/// below, at the seam it actually belonged to: the acceptance tests were about
/// `Visibility`, and used `FogEdits` only as a convenient way to mutate a document.
final class FogEditsTests: XCTestCase {
    private let wall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))

    // MARK: Walls

    func testTracingAChain() {
        var edits = FogEdits(document: FogDocument())
        edits.addWalls([wall])
        XCTAssertEqual(edits.document.walls, [wall])
    }

    func testDeletingAWall() {
        var edits = FogEdits(document: FogDocument(walls: [wall]))
        edits.deleteWall(id: wall.id)
        XCTAssertTrue(edits.document.walls.isEmpty)
    }

    func testDeletingAWallThatIsNotThereIsNotAnUndoStep() {
        var edits = FogEdits(document: FogDocument(walls: [wall]))
        edits.deleteWall(id: UUID())
        XCTAssertFalse(edits.canUndo)
        XCTAssertEqual(edits.document.walls, [wall])
    }

    // MARK: Undo

    func testUndoUnwindsAWholeChainAtOnce() {
        // A chain is one action to the DM — three clicks tracing a corner — so undoing it
        // must not take two presses for its two spans.
        var edits = FogEdits(document: FogDocument())
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0)),
                        Wall(from: MapPoint(x: 100, y: 0), to: MapPoint(x: 100, y: 100))])
        edits.undo()
        XCTAssertTrue(edits.document.walls.isEmpty, "one chain took more than one undo")
    }

    func testUndoRestoresADeletedWall() {
        var edits = FogEdits(document: FogDocument(walls: [wall]))
        edits.deleteWall(id: wall.id)
        XCTAssertTrue(edits.document.walls.isEmpty)
        edits.undo()
        XCTAssertEqual(edits.document.walls, [wall])
    }

    func testUndoWithNothingToUndoDoesNothing() {
        var edits = FogEdits(document: FogDocument(walls: [wall]))
        edits.undo()
        XCTAssertEqual(edits.document.walls, [wall], "undo ate a Wall it never created")
    }

    func testUndoStopsAtTheStateTheModeOpenedIn() {
        // Undo is mode-local: it must not reach back past the fog that was already on the
        // Map when the DM entered the mode. Cancel is the tool for that.
        var edits = FogEdits(document: FogDocument(walls: [wall]))
        edits.addWalls([Wall(from: MapPoint(x: 5, y: 5), to: MapPoint(x: 6, y: 6))])
        edits.undo()
        edits.undo()
        XCTAssertEqual(edits.document.walls, [wall])
    }

    func testAnEmptyChainIsNotAnUndoStep() {
        var edits = FogEdits(document: FogDocument())
        edits.addWalls([])
        XCTAssertFalse(edits.canUndo)
    }

    /// Pawns and Lights ride along in the document because the preview draws them, but the
    /// mode never mutates them — which is what lets `applyFogEdits` copy only `walls`.
    func testTracingAWallLeavesPawnsAndLightsUntouched() {
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Vex",
                        colorHex: "#C81E1E", brightSquares: 6)
        let torch = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4)
        var edits = FogEdits(document: FogDocument(lights: [torch], pawns: [pawn]))

        edits.addWalls([wall])
        edits.undo()
        edits.addWalls([wall])

        XCTAssertEqual(edits.document.pawns, [pawn])
        XCTAssertEqual(edits.document.lights, [torch])
    }

    func testTheOriginalIsTheDocumentTheModeOpenedWith() {
        let original = FogDocument(walls: [wall])
        var edits = FogEdits(document: original)
        edits.addWalls([Wall(from: MapPoint(x: 9, y: 9), to: MapPoint(x: 20, y: 20))])
        XCTAssertEqual(edits.original, original)
    }
}
