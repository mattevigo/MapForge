import XCTest
@testable import MapForge

/// What the lighting has to do for a DM at the table, asserted against `Visibility` itself.
///
/// These were the `fog-of-war` acceptance criteria and lived in `FogEditsTests`, which used
/// `FogEdits` only as a convenient mutator. `FogEdits` no longer touches a Pawn or a Light
/// (ADR-0013), so they moved to the seam they were always about. The behaviour is unchanged.
final class LitRoomTests: XCTestCase {
    func testAPawnDraggedThroughADoorwayLightsTheNextRoomProgressively() {
        // A Pawn approaches a doorway and the room beyond opens up as it goes: not all at
        // once, and not only once it is through.
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

    func testATorchLightsFourGridSquares() {
        // A torch at 20 ft bright is 4 Grid squares (1 square = 5 ft), and the lit circle
        // must measure that on the Map.
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
        var torch = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4)
        let lit = Visibility.compute(walls: [], lights: [torch], pixelsPerSquare: 60)
        XCTAssertFalse(lit.isEmpty)

        torch.isOn = false
        let dark = Visibility.compute(walls: [], lights: [torch], pixelsPerSquare: 60)
        XCTAssertTrue(dark.isEmpty, "switching off left the region lit")
    }

    func testAPawnStillExistsWhenItsLightIsOff() {
        // "With the Fog Overlay off, the same Pawn is still visible to players as a
        // labelled coloured token." The model half of that: the token is not the light.
        var pawn = Pawn(at: MapPoint(x: 0, y: 0), label: "Vex",
                        colorHex: "#C81E1E", brightSquares: 6)
        pawn.light.isOn = false

        XCTAssertEqual(pawn.label, "Vex")
        XCTAssertEqual(pawn.colorHex, "#C81E1E")
    }

    func testChangingAPawnsSightMovesItsDimRadiusToo() {
        // The defect from the table, twice over. First the inspector's one "Sight" field
        // passed the existing dim straight back, so the outer circle sat fixed at whatever
        // the Pawn was first created with. Then coupling them at the 5e torch ratio drew a
        // halo twice the size of a character's sight — a band DnD does not have at all.
        // The edge now feathers by one square and follows the number being typed.
        var pawn = Pawn(at: MapPoint(x: 0, y: 0), label: "1",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        XCTAssertEqual(pawn.light.dimSquares, 7, "precondition: one square past sight")

        pawn.light.brightSquares = 3
        pawn.light.dimSquares = Pawn.dimSquares(forSight: 3)

        XCTAssertEqual(pawn.light.dimSquares, 4,
                       "the feathered edge did not follow the sight it is derived from")
    }
}
