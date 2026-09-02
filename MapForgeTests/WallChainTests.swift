import XCTest
@testable import MapForge

final class WallChainTests: XCTestCase {

    func testAChainOfThreeClicksMakesTwoWalls() {
        // The DM traces a corner: three vertices, two spans between them.
        var chain = WallChain()
        chain.place(MapPoint(x: 0, y: 0))
        chain.place(MapPoint(x: 100, y: 0))
        chain.place(MapPoint(x: 100, y: 100))

        XCTAssertEqual(chain.finish().count, 2)
    }

    func testSpansJoinEndToEnd() {
        // Each Wall must start where the last one ended, or the chain has gaps in it and
        // Light pours through them.
        var chain = WallChain()
        chain.place(MapPoint(x: 0, y: 0))
        chain.place(MapPoint(x: 100, y: 0))
        chain.place(MapPoint(x: 100, y: 100))

        let walls = chain.finish()
        XCTAssertEqual(walls[0].from, MapPoint(x: 0, y: 0))
        XCTAssertEqual(walls[0].to, MapPoint(x: 100, y: 0))
        XCTAssertEqual(walls[1].from, MapPoint(x: 100, y: 0), "second span did not start where the first ended")
        XCTAssertEqual(walls[1].to, MapPoint(x: 100, y: 100))
    }

    func testASingleClickMakesNoWall() {
        // Starting a chain and thinking better of it must not leave a zero-length Wall
        // behind — it would block nothing and clutter the file forever.
        var chain = WallChain()
        chain.place(MapPoint(x: 50, y: 50))
        XCTAssertTrue(chain.finish().isEmpty)
    }

    func testCancellingDiscardsTheWholeChain() {
        // Esc means "forget this", not "keep what I have so far".
        var chain = WallChain()
        chain.place(MapPoint(x: 0, y: 0))
        chain.place(MapPoint(x: 100, y: 0))
        chain.cancel()
        XCTAssertTrue(chain.finish().isEmpty)
    }

    func testFinishingClearsTheChainForTheNextOne() {
        // The DM traces one room, then another. The second must not inherit the first.
        var chain = WallChain()
        chain.place(MapPoint(x: 0, y: 0))
        chain.place(MapPoint(x: 100, y: 0))
        _ = chain.finish()

        chain.place(MapPoint(x: 500, y: 500))
        chain.place(MapPoint(x: 600, y: 500))
        let second = chain.finish()

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].from, MapPoint(x: 500, y: 500))
    }

    func testRepeatedClicksOnOneSpotAddNothing() {
        // A double-click ends a chain, so its second click must not also place a
        // zero-length Wall on top of the last vertex.
        var chain = WallChain()
        chain.place(MapPoint(x: 0, y: 0))
        chain.place(MapPoint(x: 100, y: 0))
        chain.place(MapPoint(x: 100, y: 0))

        XCTAssertEqual(chain.finish().count, 1, "a zero-length Wall was created")
    }

    func testTheChainReportsWhereItIsDrawingFrom() {
        // The UI draws a rubber-band span from here to the cursor, and the angle
        // constraint measures from it.
        var chain = WallChain()
        XCTAssertNil(chain.lastVertex, "nothing placed yet")
        chain.place(MapPoint(x: 30, y: 40))
        XCTAssertEqual(chain.lastVertex, MapPoint(x: 30, y: 40))
    }

    // MARK: Undo

    func testUndoRemovesTheLastCommittedChain() {
        // The issue requires undo over drawing and deletion. A DM who traces a wrong
        // room must not have to select and delete each span of it by hand.
        var history = WallEdits(walls: [])
        history.add([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))])
        history.add([Wall(from: MapPoint(x: 0, y: 50), to: MapPoint(x: 100, y: 50))])
        XCTAssertEqual(history.walls.count, 2)

        history.undo()
        XCTAssertEqual(history.walls.count, 1)
        XCTAssertEqual(history.walls[0].from, MapPoint(x: 0, y: 0))
    }

    func testUndoRestoresADeletedWall() {
        // Deletion is the easier half to get wrong: undo has to put the Wall back, not
        // merely stop deleting further ones.
        let wall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))
        var history = WallEdits(walls: [wall])
        history.delete(wall)
        XCTAssertTrue(history.walls.isEmpty)

        history.undo()
        XCTAssertEqual(history.walls, [wall])
    }

    func testUndoUnwindsAWholeChainAtOnce() {
        // A chain is one action to the DM — three clicks tracing a corner — so undoing
        // it must not take two presses for its two spans.
        var history = WallEdits(walls: [])
        history.add([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0)),
                     Wall(from: MapPoint(x: 100, y: 0), to: MapPoint(x: 100, y: 100))])
        history.undo()
        XCTAssertTrue(history.walls.isEmpty, "one chain took more than one undo")
    }

    func testUndoWithNothingToUndoDoesNothing() {
        var history = WallEdits(walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 1, y: 1))])
        history.undo()
        XCTAssertEqual(history.walls.count, 1, "undo ate a Wall it never created")
    }

    func testUndoStopsAtTheStateTheModeOpenedIn() {
        // Undo is mode-local: it must not reach back past the Walls that were already
        // on the Map when the DM entered the mode. Cancel is the tool for that.
        let existing = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 1, y: 1))
        var history = WallEdits(walls: [existing])
        history.add([Wall(from: MapPoint(x: 5, y: 5), to: MapPoint(x: 6, y: 6))])
        history.undo()
        history.undo()
        XCTAssertEqual(history.walls, [existing])
    }

    // MARK: Acceptance

    func testAChainJoinsOntoAnExistingWallsEndpoint() {
        // The half of the acceptance sentence the room test does not reach: "on existing
        // endpoints when starting a chain where another ends". No Grid at all here, so
        // only endpoint snapping can close the join.
        let existing = [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))]
        let sloppyStart = MapPoint(x: 104, y: 3)

        let snapped = WallSnap.snap(sloppyStart, to: WallSnap.endpoints(of: existing),
                                    gridPixels: nil, tolerance: 12)
        XCTAssertEqual(snapped.target, .endpoint)

        var chain = WallChain()
        chain.place(snapped.point)
        chain.place(MapPoint(x: 100, y: 100))
        let walls = existing + chain.finish()

        // The join is watertight if a Light on one side of the corner cannot round it
        // through a gap: the two Walls share an exact endpoint.
        XCTAssertEqual(walls[0].to, walls[1].from, "the chain did not start where the Wall ended")
    }

    func testATracedRoomIsWatertight() {
        // Issue 02's acceptance criterion, checked the way it asks to be checked: through
        // issue 05's Visibility. A DM traces a room by clicking near-but-not-exactly on
        // each corner; snapping is what closes it, and the proof is that a torch inside
        // lights nothing outside.
        let grid: CGFloat = 50
        let sloppyClicks = [MapPoint(x: 98, y: 103), MapPoint(x: 297, y: 96),
                            MapPoint(x: 303, y: 302), MapPoint(x: 104, y: 298),
                            MapPoint(x: 101, y: 99)]

        var chain = WallChain()
        for click in sloppyClicks {
            // Exactly what the UI does per click: snap, then place.
            chain.place(WallSnap.snap(click, to: chain.vertices.first.map { [$0] } ?? [],
                                      gridPixels: grid, tolerance: 12).point)
        }
        let walls = chain.finish()
        XCTAssertEqual(walls.count, 4, "a traced room should be four Walls")

        let torch = Light(at: MapPoint(x: 200, y: 200), brightSquares: 20, dimSquares: 20)
        let region = Visibility.compute(walls: walls, lights: [torch],
                                        pixelsPerSquare: 50).first!

        XCTAssertTrue(region.bright.contains(MapPoint(x: 200, y: 200)), "the room itself is dark")
        for outside in [MapPoint(x: 200, y: 50), MapPoint(x: 200, y: 350),
                        MapPoint(x: 50, y: 200), MapPoint(x: 350, y: 200)] {
            XCTAssertFalse(region.bright.contains(outside),
                           "Light leaked out of the traced room at \(outside)")
        }
    }
}
