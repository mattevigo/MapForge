import XCTest
@testable import MapForge

final class FogEditsTests: XCTestCase {
    private let wall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))
    private let torch = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4)

    // MARK: Lights

    func testPlacingALight() {
        var edits = FogEdits(document: FogDocument())
        edits.addLight(torch)
        XCTAssertEqual(edits.document.lights, [torch])
    }

    func testMovingALight() {
        // Dragging a Light to reposition it. The identity must survive the move, or its
        // on/off toggle in the live panel would jump around under the DM's cursor.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.moveLight(id: torch.id, to: MapPoint(x: 200, y: 200))

        XCTAssertEqual(edits.document.lights.count, 1)
        XCTAssertEqual(edits.document.lights[0].id, torch.id)
        XCTAssertEqual(edits.document.lights[0].at, MapPoint(x: 200, y: 200))
    }

    func testDeletingALight() {
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.deleteLight(id: torch.id)
        XCTAssertTrue(edits.document.lights.isEmpty)
    }

    func testTogglingALightOff() {
        // The one fog action performed mid-session, with players watching.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.toggleLight(id: torch.id)
        XCTAssertFalse(edits.document.lights[0].isOn)
    }

    func testSettingRadii() {
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.setLightRadii(id: torch.id, brightSquares: 6, dimSquares: 9)
        XCTAssertEqual(edits.document.lights[0].brightSquares, 6)
        XCTAssertEqual(edits.document.lights[0].dimSquares, 9)
    }

    func testADimRadiusOfZeroIsLegal() {
        // Explicitly allowed by the issue: a sharp-edged source with no falloff band.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.setLightRadii(id: torch.id, brightSquares: 4, dimSquares: 0)
        XCTAssertEqual(edits.document.lights[0].dimSquares, 0)
    }

    func testANegativeRadiusIsClampedToZero() {
        // The stepper and the text field both let a DM type past zero.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.setLightRadii(id: torch.id, brightSquares: -5, dimSquares: -1)
        XCTAssertEqual(edits.document.lights[0].brightSquares, 0)
        XCTAssertEqual(edits.document.lights[0].dimSquares, 0)
    }

    // MARK: Undo across both kinds

    func testUndoRestoresADeletedLight() {
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.deleteLight(id: torch.id)
        edits.undo()
        XCTAssertEqual(edits.document.lights, [torch])
    }

    func testUndoUnwindsWallsAndLightsInOneHistory() {
        // One undo stack over the whole fog document: the DM thinks in actions, not in
        // which kind of thing each action touched.
        var edits = FogEdits(document: FogDocument())
        edits.addWalls([wall])
        edits.addLight(torch)

        edits.undo()
        XCTAssertTrue(edits.document.lights.isEmpty, "the Light was not undone")
        XCTAssertEqual(edits.document.walls, [wall], "the Wall was undone too early")

        edits.undo()
        XCTAssertTrue(edits.document.walls.isEmpty)
    }

    func testTogglingIsNotUndoable() {
        // Toggling is a live performance action, not an edit. Filling the undo stack with
        // toggles would bury the DM's actual authoring work behind them.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.toggleLight(id: torch.id)
        XCTAssertFalse(edits.canUndo, "a toggle entered the undo history")
    }

    func testADragProducesOneUndoStep() {
        // Dragging a Light emits a position per frame. Each becoming an undo step would
        // take dozens of presses to walk back one drag.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.beginLightDrag()
        for x in stride(from: 60.0, through: 200.0, by: 10.0) {
            edits.moveLight(id: torch.id, to: MapPoint(x: x, y: 50))
        }
        edits.endLightDrag()

        edits.undo()
        XCTAssertEqual(edits.document.lights[0].at, torch.at, "a drag took more than one undo")
    }

    func testAClickThatDoesNotDragLeavesNoUndoStep() {
        // Selecting a Light is a mousedown-mouseup that begins and ends a drag without
        // moving anything. It must not cost the DM an undo press.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.beginLightDrag()
        edits.endLightDrag()
        XCTAssertFalse(edits.canUndo, "a no-op drag entered the undo history")
    }

    func testDeletingDuringADragIsStillOneUndoStep() {
        // Not a gesture a DM performs deliberately, but the state machine must not corrupt
        // its history if it happens: ⌫ while a drag is in flight.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.beginLightDrag()
        edits.moveLight(id: torch.id, to: MapPoint(x: 200, y: 200))
        edits.deleteLight(id: torch.id)
        edits.endLightDrag()

        // ONE press must restore it, not two.
        edits.undo()
        XCTAssertFalse(edits.document.lights.isEmpty, "undo did not restore the Light")
        XCTAssertFalse(edits.canUndo, "the delete-during-drag left a second history entry")
    }

    func testANestedDragStartIsIgnored() {
        // Two begins without an end between them must not push two history entries, or
        // the drag would take two presses to undo.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.beginLightDrag()
        edits.moveLight(id: torch.id, to: MapPoint(x: 100, y: 100))
        edits.beginLightDrag()
        edits.moveLight(id: torch.id, to: MapPoint(x: 200, y: 200))
        edits.endLightDrag()

        edits.undo()
        XCTAssertEqual(edits.document.lights[0].at, torch.at, "the drag took more than one undo")
    }

    func testADanglingDragDoesNotSwallowLaterUndoSteps() {
        // If a drag is never ended — the mode torn down mid-gesture — every later edit
        // would silently skip recording, and undo would stop working for the session.
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        edits.beginLightDrag()
        edits.moveLight(id: torch.id, to: MapPoint(x: 99, y: 99))
        edits.endLightDrag()

        edits.addWalls([wall])
        edits.undo()
        XCTAssertTrue(edits.document.walls.isEmpty, "a later edit was not undoable")
    }

    // MARK: Pawns

    private var vex: Pawn { Pawn(at: MapPoint(x: 100, y: 100), label: "Vex",
                                 colorHex: "#C81E1E", brightSquares: 6) }

    func testPlacingAPawn() {
        var edits = FogEdits(document: FogDocument())
        edits.addPawn(vex)
        XCTAssertEqual(edits.document.pawns.count, 1)
        XCTAssertEqual(edits.document.pawns[0].label, "Vex")
    }

    func testAPawnKeepsItsIdentityWhenMoved() {
        // The party moves constantly. A Pawn that changed identity on every drag would
        // lose its selection and its place in the live toggle row.
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        let id = edits.document.pawns[0].id
        edits.movePawn(id: id, to: MapPoint(x: 400, y: 400))

        XCTAssertEqual(edits.document.pawns[0].id, id)
        XCTAssertEqual(edits.document.pawns[0].at, MapPoint(x: 400, y: 400))
        XCTAssertEqual(edits.document.pawns[0].label, "Vex")
    }

    func testRenamingAndRecolouringAPawn() {
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        let id = edits.document.pawns[0].id
        edits.setPawnLabel(id: id, "Grog")
        edits.setPawnColor(id: id, hex: "#1E88C8")

        XCTAssertEqual(edits.document.pawns[0].label, "Grog")
        XCTAssertEqual(edits.document.pawns[0].colorHex, "#1E88C8")
    }

    func testDeletingAPawn() {
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        edits.deletePawn(id: edits.document.pawns[0].id)
        XCTAssertTrue(edits.document.pawns.isEmpty)
    }

    func testAPawnsLightTogglesLikeAnyOther() {
        // A character who puts out their torch keeps their token on the Map.
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        let id = edits.document.pawns[0].id
        edits.togglePawnLight(id: id)

        XCTAssertFalse(edits.document.pawns[0].light.isOn)
        XCTAssertEqual(edits.document.pawns.count, 1, "the Pawn vanished with its light")
    }

    func testSettingAPawnsRange() {
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        let id = edits.document.pawns[0].id
        edits.setPawnRange(id: id, brightSquares: 8, dimSquares: 12)
        XCTAssertEqual(edits.document.pawns[0].light.brightSquares, 8)
        XCTAssertEqual(edits.document.pawns[0].light.dimSquares, 12)
    }

    func testDraggingAPawnIsOneUndoStep() {
        // Dragging is a live table action emitting a position per frame.
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        let id = edits.document.pawns[0].id
        edits.beginPawnDrag()
        for x in stride(from: 110.0, through: 400.0, by: 10.0) {
            edits.movePawn(id: id, to: MapPoint(x: x, y: 100))
        }
        edits.endPawnDrag()

        edits.undo()
        XCTAssertEqual(edits.document.pawns[0].at, MapPoint(x: 100, y: 100),
                       "a Pawn drag took more than one undo")
    }

    // MARK: Wall undo — restored from WallChainTests when WallEdits became FogEdits

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

    // MARK: Acceptance

    func testAPawnDraggedThroughADoorwayLightsTheNextRoomProgressively() {
        // Issue 04's acceptance criterion. A Pawn approaches a doorway and the room beyond
        // opens up as it goes: not all at once, and not only once it is through.
        //
        // Measured as lit *area* across the far room, not one point — a point on the
        // doorway's centre line is visible from the very start (that is what a doorway is),
        // so a single probe would say nothing about the wedge widening.
        let walls = [Wall(from: MapPoint(x: -300, y: 0), to: MapPoint(x: -20, y: 0)),
                     Wall(from: MapPoint(x: 20, y: 0), to: MapPoint(x: 300, y: 0))]
        var pawn = Pawn(at: .init(x: 0, y: 0), label: "Vex", colorHex: "#C81E1E",
                        brightSquares: 6)

        /// How many probe points across the far room are lit from `y`.
        func litCount(fromY y: CGFloat) -> Int {
            pawn.at = MapPoint(x: 0, y: y)
            let regions = Visibility.compute(walls: walls, lights: [pawn.light],
                                             pixelsPerSquare: 30)
            return stride(from: -250.0, through: 250.0, by: 10.0).count { x in
                Visibility.level(at: MapPoint(x: x, y: 60), in: regions) != .unlit
            }
        }

        let far = litCount(fromY: -150)
        let atDoor = litCount(fromY: -30)
        let through = litCount(fromY: 30)

        XCTAssertGreaterThan(atDoor, far, "the wedge did not widen as the Pawn approached")
        XCTAssertGreaterThan(through, atDoor, "the room did not open up once through the doorway")
    }

    func testAPawnStillExistsWhenItsLightIsOff() {
        // "With the Fog Overlay off, the same Pawn is still visible to players as a
        // labelled coloured token." The model half of that: the token is not the light.
        var edits = FogEdits(document: FogDocument(pawns: [vex]))
        edits.togglePawnLight(id: edits.document.pawns[0].id)

        XCTAssertEqual(edits.document.pawns.count, 1)
        XCTAssertEqual(edits.document.pawns[0].label, "Vex")
        XCTAssertEqual(edits.document.pawns[0].colorHex, "#C81E1E")
    }


    func testATorchLightsFourGridSquares() {
        // Issue 03's acceptance criterion: a torch at 20 ft bright is 4 Grid squares
        // (1 square = 5 ft), and the lit circle must measure that on the Map.
        let grid: CGFloat = 60   // image pixels per Grid square
        let torch = Light(at: MapPoint(x: 500, y: 500), brightSquares: 4)
        let region = Visibility.compute(walls: [], lights: [torch], pixelsPerSquare: grid).first!

        // 4 squares = 240 px. Lit just inside, dark just outside.
        XCTAssertTrue(region.bright.contains(MapPoint(x: 500 + 4 * grid - 5, y: 500)))
        XCTAssertFalse(region.bright.contains(MapPoint(x: 500 + 4 * grid + 5, y: 500)))
        // Dim defaults to twice bright, so 8 squares.
        XCTAssertTrue(region.dim.contains(MapPoint(x: 500 + 8 * grid - 5, y: 500)))
        XCTAssertFalse(region.dim.contains(MapPoint(x: 500 + 8 * grid + 5, y: 500)))
    }

    func testSwitchingATorchOffDarkensExactlyItsRegion() {
        var edits = FogEdits(document: FogDocument(lights: [torch]))
        let lit = Visibility.compute(walls: [], lights: edits.document.lights, pixelsPerSquare: 60)
        XCTAssertFalse(lit.isEmpty)

        edits.toggleLight(id: torch.id)
        let dark = Visibility.compute(walls: [], lights: edits.document.lights, pixelsPerSquare: 60)
        XCTAssertTrue(dark.isEmpty, "switching off left the region lit")
    }

    func testCancelRestoresTheDocumentTheModeOpenedWith() {
        let original = FogDocument(walls: [wall], lights: [torch])
        var edits = FogEdits(document: original)
        edits.addLight(Light(at: MapPoint(x: 9, y: 9), brightSquares: 2))
        edits.deleteLight(id: torch.id)
        XCTAssertEqual(edits.original, original)
    }
}
