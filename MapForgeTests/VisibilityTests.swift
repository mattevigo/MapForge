import XCTest
@testable import MapForge

final class VisibilityTests: XCTestCase {

    func testALightWithNoWallsSeesAllAround() {
        // The degenerate case, and the one every other test is measured against: with
        // nothing to block it a Light reaches its full radius in every direction.
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 1, dimSquares: 2)
        let regions = Visibility.compute(walls: [], lights: [light], pixelsPerSquare: 10)

        let region = try! XCTUnwrap(regions.first)
        for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
            let justInside = MapPoint(x: cos(angle) * 9, y: sin(angle) * 9)
            XCTAssertTrue(region.bright.contains(justInside),
                          "dark at \(angle) rad, inside the bright radius")
        }
    }

    func testLightDoesNotReachBeyondItsRadius() {
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 1, dimSquares: 2)
        let regions = Visibility.compute(walls: [], lights: [light], pixelsPerSquare: 10)
        let region = try! XCTUnwrap(regions.first)

        XCTAssertFalse(region.bright.contains(MapPoint(x: 11, y: 0)), "bright past its radius")
        XCTAssertTrue(region.dim.contains(MapPoint(x: 11, y: 0)), "dim should reach 2 squares")
        XCTAssertFalse(region.dim.contains(MapPoint(x: 21, y: 0)), "dim past its radius")
    }

    func testALightThatIsOffLightsNothing() {
        // Switching a Light off is the one fog action a DM performs mid-session.
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 1, isOn: false)
        XCTAssertTrue(Visibility.compute(walls: [], lights: [light], pixelsPerSquare: 10).isEmpty)
    }

    // MARK: Walls block

    func testAWallCastsAShadowBehindIt() {
        // The whole feature in one case: a Light, a Wall, and darkness behind it.
        // The Wall spans x ∈ [-20, 20] at y = 10, the Light sits at the origin, so
        // everything directly beyond it is in shadow.
        let wall = Wall(from: MapPoint(x: -20, y: 10), to: MapPoint(x: 20, y: 10))
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: [wall], lights: [light],
                                        pixelsPerSquare: 10).first!

        XCTAssertTrue(region.bright.contains(MapPoint(x: 0, y: 5)), "dark in front of the Wall")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 0, y: 30)), "lit behind the Wall")
    }

    func testLightPassesTheEndOfAWall() {
        // A Wall blocks only what it spans. Past its end the Light continues — this is
        // the wedge a doorway throws, and getting it wrong makes every room look sealed.
        let wall = Wall(from: MapPoint(x: -20, y: 10), to: MapPoint(x: 20, y: 10))
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: [wall], lights: [light],
                                        pixelsPerSquare: 10).first!

        // Unambiguously outside the shadow: the Wall's right end lies at 26.6° from the
        // Light, and this point is at 18.4°, so no ray to it can be blocked. A point
        // exactly on the shadow boundary would be a coin flip — that is the vertex case,
        // tested separately below.
        XCTAssertTrue(region.bright.contains(MapPoint(x: 60, y: 20)),
                      "dark past the end of the Wall")
    }

    func testAClosedRoomKeepsAnOutsideLightOut() {
        // From issue 05's case list. A torch in the corridor must not light the room.
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 20, dimSquares: 20)
        let region = Visibility.compute(walls: room(from: MapPoint(x: 50, y: -25),
                                                    to: MapPoint(x: 100, y: 25)),
                                        lights: [light], pixelsPerSquare: 10).first!

        XCTAssertFalse(region.bright.contains(MapPoint(x: 75, y: 0)),
                       "the room interior is lit from outside")
        XCTAssertTrue(region.bright.contains(MapPoint(x: 25, y: 0)),
                      "the corridor in front of the room is dark")
    }

    func testAGapInAChainLeaksLight() {
        // Also from the case list, and the inverse of the one above: geometry says light
        // gets through a gap, so it must — a solver that silently sealed gaps would hide
        // the DM's own mistakes from them.
        let gapped = [Wall(from: MapPoint(x: -40, y: 10), to: MapPoint(x: -5, y: 10)),
                      Wall(from: MapPoint(x: 5, y: 10), to: MapPoint(x: 40, y: 10))]
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: gapped, lights: [light],
                                        pixelsPerSquare: 10).first!

        XCTAssertTrue(region.bright.contains(MapPoint(x: 0, y: 30)), "the gap did not leak")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 30, y: 30)),
                       "leaked past the walls either side of the gap")
    }

    // MARK: Degenerate geometry

    func testARayThroughAVertexDoesNotLeak() {
        // The classic one-pixel light leak from issue 05's list. Two Walls meeting at a
        // corner: a ray aimed exactly at the shared vertex must not slip between them.
        let corner = MapPoint(x: 20, y: 20)
        let walls = [Wall(from: MapPoint(x: 20, y: -40), to: corner),
                     Wall(from: corner, to: MapPoint(x: 80, y: 20))]
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 20, dimSquares: 20)
        let region = Visibility.compute(walls: walls, lights: [light],
                                        pixelsPerSquare: 10).first!

        // Directly beyond the vertex along the light-to-corner line.
        XCTAssertFalse(region.bright.contains(MapPoint(x: 60, y: 60)),
                       "light leaked through the corner")
    }

    func testALightExactlyOnAWallStillLightsOneSide() {
        // From the case list. A Light placed on a Wall is a DM mis-click, not a crash:
        // the sweep must terminate and still light the side it is on.
        let wall = Wall(from: MapPoint(x: -50, y: 0), to: MapPoint(x: 50, y: 0))
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: [wall], lights: [light],
                                        pixelsPerSquare: 10).first!
        // Asserting the polygon is non-degenerate is far too weak: a zero-area shape
        // collapsed onto the Wall's own line has plenty of vertices and lights nothing.
        // Name the actual requirement — the side the Light is on is lit.
        XCTAssertTrue(region.bright.contains(MapPoint(x: 0, y: -30)),
                      "the side the Light is on went dark")
    }

    func testALightExactlyOnAWallEndpointTerminates() {
        let wall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: [wall], lights: [light],
                                        pixelsPerSquare: 10).first!
        XCTAssertTrue(region.bright.contains(MapPoint(x: -30, y: -30)),
                      "the side away from the Wall went dark")
    }

    func testCollinearOverlappingWallsBehaveAsOne() {
        // Two Walls drawn along the same line, overlapping — easy for a DM to produce by
        // tracing twice, and a solver that mishandles them leaks along the seam.
        let walls = [Wall(from: MapPoint(x: -40, y: 10), to: MapPoint(x: 10, y: 10)),
                     Wall(from: MapPoint(x: -10, y: 10), to: MapPoint(x: 40, y: 10))]
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: walls, lights: [light],
                                        pixelsPerSquare: 10).first!

        XCTAssertFalse(region.bright.contains(MapPoint(x: 0, y: 30)),
                       "leaked along the seam between two overlapping Walls")
        XCTAssertTrue(region.bright.contains(MapPoint(x: 0, y: 5)), "dark in front")
    }

    func testADegenerateZeroLengthWallDoesNotCrash() {
        // A double-click while drawing produces one. It blocks nothing, and must not
        // divide by zero on the way to blocking nothing.
        let wall = Wall(from: MapPoint(x: 20, y: 20), to: MapPoint(x: 20, y: 20))
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: [wall], lights: [light],
                                        pixelsPerSquare: 10).first!
        XCTAssertTrue(region.bright.contains(MapPoint(x: 40, y: 40)))
    }

    // MARK: Boundary Walls and combining

    func testNoLightEscapesTheImageBounds() {
        // Issue 02 owns drawing the implicit boundary Walls, but the engine is what makes
        // them matter: without them a Light near the edge spills into the letterbox.
        let bounds = CGSize(width: 200, height: 100)
        let light = Light(at: MapPoint(x: 190, y: 50), brightSquares: 20, dimSquares: 20)
        let region = Visibility.compute(walls: Visibility.boundaryWalls(imagePixelSize: bounds),
                                        lights: [light], pixelsPerSquare: 10).first!

        XCTAssertFalse(region.bright.contains(MapPoint(x: 230, y: 50)), "light escaped right")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 190, y: -20)), "light escaped up")
        XCTAssertTrue(region.bright.contains(MapPoint(x: 150, y: 50)), "inside went dark")
    }

    func testBrightBeatsDimWhereTwoLightsOverlap() {
        // From the case list. Two Lights side by side: a point in one's bright band and
        // the other's dim band is bright — the DM must not see a dim patch where two
        // torches meet.
        let a = Light(at: MapPoint(x: 0, y: 0), brightSquares: 5, dimSquares: 10)
        let b = Light(at: MapPoint(x: 60, y: 0), brightSquares: 5, dimSquares: 10)
        let regions = Visibility.compute(walls: [], lights: [a, b], pixelsPerSquare: 10)

        // (20,0) is inside a's bright radius (50) and inside b's dim radius only.
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 20, y: 0), in: regions), .bright)
        // (110,0) is beyond both bright radii but inside b's dim.
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 110, y: 0), in: regions), .dim)
        // Far from both.
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 400, y: 0), in: regions), .unlit)
    }

    func testAPawnLightsLikeAnyOtherLight() {
        // A Pawn IS a Light — its range of sight and its range of illumination are the
        // same number — so the engine must not care which it was given.
        let pawn = Pawn(at: MapPoint(x: 0, y: 0), label: "Vex", colorHex: "#C81E1E",
                        brightSquares: 3)
        let regions = Visibility.compute(walls: [], lights: [pawn.light], pixelsPerSquare: 10)
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 20, y: 0), in: regions), .bright)
    }

    func testALightOnAWallStillBlocksTheFarSide() {
        // The other half of the case above: not blinding the Light where it stands must
        // not turn a Wall through it into no Wall at all.
        let wall = Wall(from: MapPoint(x: -50, y: 0), to: MapPoint(x: 50, y: 0))
        let light = Light(at: MapPoint(x: 0, y: 20), brightSquares: 10, dimSquares: 10)
        let region = Visibility.compute(walls: [wall], lights: [light],
                                        pixelsPerSquare: 10).first!

        XCTAssertTrue(region.bright.contains(MapPoint(x: 0, y: 40)), "dark on the Light's side")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 0, y: -20)), "lit through the Wall")
    }

    func testBrightNeverReachesWhereDimDoesNot() {
        // Bright and dim are swept independently, with their own radius-culled Wall sets,
        // so nothing structurally guarantees one nests inside the other. Rendering assumes
        // it does: issue 06 draws dim then bright over it.
        let walls = [Wall(from: MapPoint(x: -60, y: 40), to: MapPoint(x: 60, y: 40)),
                     Wall(from: MapPoint(x: 30, y: -60), to: MapPoint(x: 30, y: 60))]
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 5, dimSquares: 10)
        let region = Visibility.compute(walls: walls, lights: [light],
                                        pixelsPerSquare: 10).first!

        for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 32) {
            for radius in stride(from: 5.0, through: 45.0, by: 5.0) {
                let point = MapPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if region.bright.contains(point) {
                    XCTAssertTrue(region.dim.contains(point),
                                  "bright but not dim at angle \(angle), radius \(radius)")
                }
            }
        }
    }

    func testTwoLightsMeetAcrossAWallWithNoSeam() {
        // The half of the case list the precedence test cannot reach: with a Wall in play
        // the two regions are real polygons, and the point where they meet must be lit by
        // one or the other — a gap there would draw as a dark seam between two torches.
        let wall = Wall(from: MapPoint(x: -100, y: 40), to: MapPoint(x: 100, y: 40))
        let a = Light(at: MapPoint(x: -30, y: 0), brightSquares: 10, dimSquares: 10)
        let b = Light(at: MapPoint(x: 30, y: 0), brightSquares: 10, dimSquares: 10)
        let regions = Visibility.compute(walls: [wall], lights: [a, b], pixelsPerSquare: 10)

        // Sweep the midline between them, in front of the Wall: every point is within
        // reach of both, so none may be unlit.
        for y in stride(from: -30.0, through: 30.0, by: 5.0) {
            XCTAssertNotEqual(Visibility.level(at: MapPoint(x: 0, y: y), in: regions), .unlit,
                              "seam between two Lights at y=\(y)")
        }
    }

    // MARK: Scale

    func testShadowsAreExactOnALargeMap() {
        // The vertex nudge is a fixed angle, so its effect in pixels grows with distance.
        // On a 6000 px map — a large VTT battle map — a corner 3000 px from the Light must
        // still block cleanly rather than leak or over-block.
        let corner = MapPoint(x: 3000, y: 3000)
        let walls = [Wall(from: MapPoint(x: 3000, y: -3000), to: corner),
                     Wall(from: corner, to: MapPoint(x: 6000, y: 3000))]
        let light = Light(at: MapPoint(x: 0, y: 0), brightSquares: 200, dimSquares: 200)
        let region = Visibility.compute(walls: walls, lights: [light],
                                        pixelsPerSquare: 40).first!

        XCTAssertTrue(region.bright.contains(MapPoint(x: 2000, y: 2000)),
                      "dark in front of the corner at map scale")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 4500, y: 4500)),
                       "leaked through the corner at map scale")
    }

    // MARK: Acceptance

    func testATorchInARoomWithADoorwayThrowsAWedgeIntoTheCorridor() {
        // Issue 05's acceptance criterion, as geometry: a room 100×100 with a 20-wide
        // doorway in its right wall, a torch inside, a corridor beyond.
        //
        //   (0,0) +--------------+ (100,0)
        //         |              |
        //         |     (*)      | <- doorway, y ∈ [40,60]
        //         |              |
        //   (0,100)+-------------+ (100,100)
        let walls = [
            Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0)),      // top
            Wall(from: MapPoint(x: 0, y: 100), to: MapPoint(x: 100, y: 100)),  // bottom
            Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 0, y: 100)),      // left
            Wall(from: MapPoint(x: 100, y: 0), to: MapPoint(x: 100, y: 40)),   // right, above door
            Wall(from: MapPoint(x: 100, y: 60), to: MapPoint(x: 100, y: 100)), // right, below door
        ]
        let torch = Light(at: MapPoint(x: 50, y: 50), brightSquares: 30, dimSquares: 30)
        let region = Visibility.compute(walls: walls, lights: [torch],
                                        pixelsPerSquare: 10).first!

        XCTAssertTrue(region.bright.contains(MapPoint(x: 50, y: 20)), "the room itself is dark")
        XCTAssertTrue(region.bright.contains(MapPoint(x: 90, y: 50)), "dark at the doorway")

        // Through the doorway: lit on the torch's line, dark above and below where the
        // wall either side of the door blocks. That contrast IS the wedge.
        XCTAssertTrue(region.bright.contains(MapPoint(x: 150, y: 50)),
                      "no light reached the corridor")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 150, y: 10)),
                       "corridor lit above the doorway")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 150, y: 90)),
                       "corridor lit below the doorway")

        // The wedge widens with distance, and by exactly how much similar triangles say:
        // the torch is 50 px from the door, so 100 px beyond it the door's 20 px opening
        // has spread threefold to y ∈ [30, 70]. Asserting the arithmetic — not just
        // "some light got through" — is what makes this a test of the geometry.
        XCTAssertTrue(region.bright.contains(MapPoint(x: 150, y: 68)), "wedge too narrow")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 150, y: 72)), "wedge too wide")
        XCTAssertTrue(region.bright.contains(MapPoint(x: 150, y: 32)), "wedge too narrow")
        XCTAssertFalse(region.bright.contains(MapPoint(x: 150, y: 28)), "wedge too wide")
    }

    // MARK: Helpers

    /// The four Walls of an axis-aligned room.
    private func room(from a: MapPoint, to b: MapPoint) -> [Wall] {
        let corners = [MapPoint(x: a.x, y: a.y), MapPoint(x: b.x, y: a.y),
                       MapPoint(x: b.x, y: b.y), MapPoint(x: a.x, y: b.y)]
        return (0..<4).map { Wall(from: corners[$0], to: corners[($0 + 1) % 4]) }
    }
}
