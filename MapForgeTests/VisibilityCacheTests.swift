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
            _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10)
        }
        XCTAssertEqual(computations, 1)
    }

    func testMovingAPawnRecomputes() {
        // The inverse: a Pawn dragged across a doorway must light the next room as it
        // goes, so an edit has to invalidate.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10)

        var moved = document
        moved.lights[0].at = MapPoint(x: 5, y: 0)
        _ = cache.regions(for: moved, imagePixelSize: imageSize, pixelsPerSquare: 10)

        XCTAssertEqual(computations, 2)
    }

    func testRedeclaringTheGridRecomputes() {
        // Light radii are in Grid squares, so re-running Grid Fit changes how far every
        // Light reaches even though no Light was touched.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10)
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 20)
        XCTAssertEqual(computations, 2)
    }

    func testSwitchingToADifferentlySizedMapRecomputes() {
        // The boundary Walls come from the image bounds, so they change with the Map.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10)
        _ = cache.regions(for: document, imagePixelSize: CGSize(width: 800, height: 600),
                          pixelsPerSquare: 10)
        XCTAssertEqual(computations, 2)
    }

    func testTheCachedResultIsTheSameAsComputingDirectly() {
        // A cache that returns something other than what the engine computes would be
        // worse than no cache at all.
        let cache = VisibilityCache()
        let cached = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 10)
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
                                      pixelsPerSquare: 25)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 0.2, "80 Walls and 8 Lights took \(elapsed)s")
    }
}
