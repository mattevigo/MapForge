import XCTest
@testable import MapForge

/// Pinning: a settled Measurement the DM has parked on the Map, which stays until it is
/// unpinned rather than being cleared by the next click.
final class MeasurementPinTests: XCTestCase {
    private let pixelsPerSquare: CGFloat = 10
    private let origin = MapPoint(x: 100, y: 100)

    private func settled(_ shape: MeasurementShape, distance: CGFloat = 4,
                         direction: CGFloat = 0, chain: [MapPoint] = []) -> MapForge.Measurement {
        var m = MapForge.Measurement(origin: .point(origin), shape: shape,
                                     distance: distance, direction: direction)
        m.chain = chain
        m.isDistanceSettled = true
        return m
    }

    // MARK: Hit-testing an area shape

    func testAPointInsideACircleHitsIt() {
        let m = settled(.circle, distance: 4)   // 40 pixels radius
        XCTAssertTrue(m.contains(MapPoint(x: 120, y: 100), origin: origin,
                                 pixelsPerSquare: pixelsPerSquare))
    }

    func testAPointOutsideACircleMisses() {
        let m = settled(.circle, distance: 4)
        XCTAssertFalse(m.contains(MapPoint(x: 200, y: 100), origin: origin,
                                  pixelsPerSquare: pixelsPerSquare))
    }

    func testAPointInsideASquareHitsIt() {
        // A Square's distance is its side, so 4 squares is 40 pixels across — 20 either way.
        let m = settled(.square, distance: 4)
        XCTAssertTrue(m.contains(MapPoint(x: 115, y: 115), origin: origin,
                                 pixelsPerSquare: pixelsPerSquare))
        XCTAssertFalse(m.contains(MapPoint(x: 130, y: 100), origin: origin,
                                  pixelsPerSquare: pixelsPerSquare))
    }

    func testAPointInsideAConeHitsIt() {
        let m = settled(.cone, distance: 6, direction: 0)
        XCTAssertTrue(m.contains(MapPoint(x: 130, y: 100), origin: origin,
                                 pixelsPerSquare: pixelsPerSquare))
        // Behind the apex is not in the cone, however close.
        XCTAssertFalse(m.contains(MapPoint(x: 70, y: 100), origin: origin,
                                  pixelsPerSquare: pixelsPerSquare))
    }

    // MARK: Hit-testing a Line

    func testAPointNearALineHitsItWithinTolerance() {
        // A chain has no area, so it needs a tolerance band — the DM cannot be asked to
        // click a 2pt stroke exactly.
        let m = settled(.line, chain: [MapPoint(x: 200, y: 100)])
        XCTAssertTrue(m.contains(MapPoint(x: 150, y: 104), origin: origin,
                                 pixelsPerSquare: pixelsPerSquare))
    }

    func testAPointFarFromALineMisses() {
        let m = settled(.line, chain: [MapPoint(x: 200, y: 100)])
        XCTAssertFalse(m.contains(MapPoint(x: 150, y: 160), origin: origin,
                                  pixelsPerSquare: pixelsPerSquare))
    }

    func testEverySegmentOfAChainIsHittable() {
        // Not just the first: a DM pins a route and then wants to unpin it by clicking
        // whichever leg is nearest.
        let m = settled(.line, chain: [MapPoint(x: 200, y: 100), MapPoint(x: 200, y: 300)])
        XCTAssertTrue(m.contains(MapPoint(x: 202, y: 250), origin: origin,
                                 pixelsPerSquare: pixelsPerSquare))
    }

    func testAPointBeyondTheEndOfASegmentMisses() {
        // The band follows the segment, it does not extend past its ends into open map.
        let m = settled(.line, chain: [MapPoint(x: 200, y: 100)])
        XCTAssertFalse(m.contains(MapPoint(x: 260, y: 100), origin: origin,
                                  pixelsPerSquare: pixelsPerSquare))
    }

    // MARK: Only settled Measurements are hittable

    func testAMeasurementStillFollowingTheCursorIsNotHittable() {
        // It is under the pointer by definition, so hit-testing it would offer to pin
        // whatever the DM happens to be dragging.
        var live = settled(.circle, distance: 4)
        live.isDistanceSettled = false
        XCTAssertFalse(live.contains(MapPoint(x: 100, y: 100), origin: origin,
                                     pixelsPerSquare: pixelsPerSquare))
    }
}

/// Pinned Measurements on `AppState`: many at once, alongside the one being drawn.
@MainActor
final class MeasurementPinStateTests: XCTestCase {
    private func state() -> AppState {
        let defaults = UserDefaults(suiteName: "MeasurementPinStateTests.\(UUID().uuidString)")!
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.squaresWide = 20
        return state
    }

    private func settled(_ x: CGFloat) -> MapForge.Measurement {
        var m = MapForge.Measurement(origin: .point(MapPoint(x: x, y: 0)), shape: .circle,
                            distance: 4, direction: 0)
        m.isDistanceSettled = true
        return m
    }

    func testPinningMovesTheLiveMeasurementIntoThePinnedSet() {
        let state = state()
        state.setMeasurement(settled(10))
        state.pinMeasurement()
        XCTAssertEqual(state.pinnedMeasurements.count, 1)
        XCTAssertNil(state.measurement, "the live slot is free for the next one")
    }

    func testSeveralMeasurementsCanBePinnedAtOnce() {
        // The invariant this feature retires: one Measurement at a time. A DM comparing
        // two spell areas needs both on the Map.
        let state = state()
        for x in [CGFloat(10), 20, 30] {
            state.setMeasurement(settled(x))
            state.pinMeasurement()
        }
        XCTAssertEqual(state.pinnedMeasurements.count, 3)
    }

    func testUnpinningRemovesJustThatOne() {
        let state = state()
        state.setMeasurement(settled(10))
        state.pinMeasurement()
        state.setMeasurement(settled(20))
        state.pinMeasurement()

        let first = state.pinnedMeasurements[0]
        state.unpinMeasurement(id: first.id)
        XCTAssertEqual(state.pinnedMeasurements.count, 1)
        XCTAssertNotEqual(state.pinnedMeasurements[0].id, first.id)
    }

    func testAnUnsettledMeasurementCannotBePinned() {
        // Pinning parks a finished answer; a shape still following the cursor is not one.
        let state = state()
        state.setMeasurement(MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)),
                                         shape: .circle, distance: 4, direction: 0))
        state.pinMeasurement()
        XCTAssertTrue(state.pinnedMeasurements.isEmpty)
        XCTAssertNotNil(state.measurement)
    }

    func testPinsAreClearedWithTheMapTheyWereTakenOn() {
        // Same rule the live Measurement follows: a distance means something different
        // under another Map's Grid.
        let state = state()
        state.setMeasurement(settled(10))
        state.pinMeasurement()
        state.beginFogEditing()
        XCTAssertTrue(state.pinnedMeasurements.isEmpty)
    }

    func testAPinAnchoredToADeletedPawnGoes() {
        let state = state()
        let pawn = Pawn(at: MapPoint(x: 50, y: 50), label: "A", colorHex: "#ff0000",
                        brightSquares: 4)
        state.fog.pawns = [pawn]
        var m = MapForge.Measurement(origin: .pawn(pawn.id), shape: .circle, distance: 4, direction: 0)
        m.isDistanceSettled = true
        state.setMeasurement(m)
        state.pinMeasurement()
        XCTAssertEqual(state.pinnedMeasurements.count, 1)

        state.fog.pawns = []
        XCTAssertTrue(state.pinnedMeasurements.isEmpty)
    }
}
