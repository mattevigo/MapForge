import XCTest
@testable import MapForge

final class VisibilityCacheTests: XCTestCase {
    private let document = FogDocument(
        walls: [Wall(from: MapPoint(x: -20, y: 10), to: MapPoint(x: 20, y: 10))],
        lights: [Light(at: MapPoint(x: 0, y: 0), brightSquares: 4)]
    )
    private let imageSize = CGSize(width: 400, height: 300)

    func testRepeatedReadsComputeOnce() {
        // The requirement that matters at the table: panning the Viewport is a drag-rate
        // operation, and issue 09 already cost a round of work on drag smoothness. The
        // Visibility behind it is unchanged, so it must not be recomputed per frame.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        for _ in 0..<50 {
            _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        }
        XCTAssertEqual(computations, 1)
    }

    func testMovingAPawnRecomputes() {
        // The inverse: a Pawn dragged across a doorway must light the next room as it
        // goes, so an edit has to invalidate.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)

        var moved = document
        moved.lights[0].at = MapPoint(x: 5, y: 0)
        _ = cache.regions(for: moved, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)

        XCTAssertEqual(computations, 2)
    }

    func testRedeclaringTheGridRecomputes() {
        // Light radii are in Grid squares, so re-running Grid Fit changes how far every
        // Light reaches even though no Light was touched.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 20, soloSightPawnID: nil)
        XCTAssertEqual(computations, 2)
    }

    func testSwitchingToADifferentlySizedMapRecomputes() {
        // The boundary Walls come from the image bounds, so they change with the Map.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        _ = cache.regions(for: document, imagePixelSize: CGSize(width: 800, height: 600),
                          pixelsPerSquare: 10, soloSightPawnID: nil)
        XCTAssertEqual(computations, 2)
    }

    func testTheCachedResultIsTheSameAsComputingDirectly() {
        // A cache that returns something other than what the engine computes would be
        // worse than no cache at all.
        let cache = VisibilityCache()
        let cached = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        let direct = Visibility.compute(
            walls: document.walls + Visibility.boundaryWalls(imagePixelSize: imageSize),
            lights: document.lights + document.pawns.map(\.light),
            pixelsPerSquare: 10)
        XCTAssertEqual(cached, direct)
    }

    func testARealisticMapComputesFastEnoughToFeelInstant() {
        // ADR 0002 rejected a Metal shader on the grounds that "a hand-authored Map has
        // tens of Walls, not thousands". This is that claim, measured — if it ever fails,
        // the ADR names this as the moment to reconsider.
        var walls: [Wall] = []
        for i in 0..<80 {
            let x = CGFloat(i % 10) * 100, y = CGFloat(i / 10) * 100
            walls.append(Wall(from: MapPoint(x: x, y: y), to: MapPoint(x: x + 80, y: y)))
        }
        let lights = (0..<8).map {
            Light(at: MapPoint(x: CGFloat($0) * 110 + 40, y: 250), brightSquares: 6)
        }
        let document = FogDocument(walls: walls, lights: lights)

        let started = Date()
        _ = VisibilityCache().regions(for: document,
                                      imagePixelSize: CGSize(width: 1000, height: 800),
                                      pixelsPerSquare: 25, soloSightPawnID: nil)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 0.2, "80 Walls and 8 Lights took \(elapsed)s")
    }

    // MARK: - Solo Sight

    /// Two party Pawns far apart, each lighting its own corner, plus the Map's own Light.
    private func twoPawnDocument() -> (FogDocument, Pawn, Pawn) {
        let ilyana = Pawn(at: MapPoint(x: -100, y: -80), label: "Ilyana",
                          colorHex: "#FF0000", brightSquares: 3)
        let bardo = Pawn(at: MapPoint(x: 120, y: 90), label: "Bardo",
                         colorHex: "#00FF00", brightSquares: 3)
        var document = FogDocument(lights: [Light(at: MapPoint(x: 0, y: 0), brightSquares: 4)])
        document.pawns = [ilyana, bardo]
        return (document, ilyana, bardo)
    }

    func testSoloSightDropsTheOtherPawnsLight() {
        let (document, ilyana, bardo) = twoPawnDocument()
        let cache = VisibilityCache()

        let solo = cache.regions(for: document, imagePixelSize: imageSize,
                                 pixelsPerSquare: 10, soloSightPawnID: ilyana.id)

        XCTAssertFalse(solo.contains { $0.lightID == bardo.light.id },
                       "Bardo's light survived Solo Sight on Ilyana")
        XCTAssertTrue(solo.contains { $0.lightID == ilyana.light.id },
                      "the isolated Pawn's own light went out")
    }

    func testSoloSightKeepsTheMapsOwnLights() {
        // A brazier is the room, not another character's influence. ADR 0004.
        let (document, ilyana, _) = twoPawnDocument()
        let brazier = document.lights[0]
        let cache = VisibilityCache()

        let solo = cache.regions(for: document, imagePixelSize: imageSize,
                                 pixelsPerSquare: 10, soloSightPawnID: ilyana.id)

        XCTAssertTrue(solo.contains { $0.lightID == brazier.id },
                      "Solo Sight put out the Map's own Light")
    }

    func testEnteringAndLeavingSoloSightRecomputes() {
        // The isolated ID is a lighting input like any other, so it must invalidate.
        let (document, ilyana, _) = twoPawnDocument()
        var computations = 0
        let cache = VisibilityCache { computations += 1 }

        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        _ = cache.regions(for: document, imagePixelSize: imageSize,
                          pixelsPerSquare: 10, soloSightPawnID: ilyana.id)
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)

        XCTAssertEqual(computations, 3)
    }

    func testSoloSightIsStillMemoised() {
        let (document, ilyana, _) = twoPawnDocument()
        var computations = 0
        let cache = VisibilityCache { computations += 1 }

        for _ in 0..<20 {
            _ = cache.regions(for: document, imagePixelSize: imageSize,
                              pixelsPerSquare: 10, soloSightPawnID: ilyana.id)
        }

        XCTAssertEqual(computations, 1, "panning under Solo Sight recomputed the fog")
    }

    func testLeavingSoloSightRestoresTheOriginalRegions() {
        let (document, ilyana, _) = twoPawnDocument()
        let cache = VisibilityCache()

        let before = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        _ = cache.regions(for: document, imagePixelSize: imageSize,
                          pixelsPerSquare: 10, soloSightPawnID: ilyana.id)
        let after = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)

        XCTAssertEqual(before.map(\.lightID), after.map(\.lightID))
    }

    func testSoloSightRespectsTheIsolatedPawnsOwnFlame() {
        // "Your torch just died" still means something under Solo Sight: only the Map's
        // own Lights are left.
        var (document, ilyana, _) = twoPawnDocument()
        document.pawns[0].light.isOn = false
        let cache = VisibilityCache()

        let solo = cache.regions(for: document, imagePixelSize: imageSize,
                                 pixelsPerSquare: 10, soloSightPawnID: ilyana.id)

        XCTAssertFalse(solo.contains { $0.lightID == ilyana.light.id })
    }

    func testAStaleSoloSightIDLeavesTheFogAlone() {
        // The ID outlived its Pawn somehow: the mode goes inert rather than blacking out
        // the Map on the table.
        let (document, _, _) = twoPawnDocument()
        let cache = VisibilityCache()

        let normal = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10, soloSightPawnID: nil)
        let stale = VisibilityCache().regions(for: document, imagePixelSize: imageSize,
                                              pixelsPerSquare: 10, soloSightPawnID: UUID())

        XCTAssertEqual(normal.map(\.lightID), stale.map(\.lightID))
    }
}
