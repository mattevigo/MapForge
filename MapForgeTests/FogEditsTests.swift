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
        edits.beginLightDrag(id: torch.id)
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
        edits.beginLightDrag(id: torch.id)
        edits.endLightDrag()
        XCTAssertFalse(edits.canUndo, "a no-op drag entered the undo history")
    }

    // MARK: Acceptance

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
