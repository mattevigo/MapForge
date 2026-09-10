import XCTest
@testable import MapForge

/// Whether measuring is offered, and where a right-click lands.
///
/// Pure, and separate from `ControlView`, for the reason `SoloSightControl` is: a rule the
/// DM meets mid-session should be provable without driving a window.
final class MeasurementControlTests: XCTestCase {
    // MARK: Availability

    func testMeasuringNeedsADeclaredGrid() {
        // Distances are in Grid squares, so without one there is no metres conversion and
        // the readout would be a confident wrong number. Refuse rather than mislead — the
        // same posture as Solo Sight being unavailable on a hidden Pawn.
        XCTAssertEqual(MeasurementControl.availability(hasDeclaredGrid: false, hasMap: true),
                       .disabled(.noGrid))
    }

    func testMeasuringNeedsAMap() {
        XCTAssertEqual(MeasurementControl.availability(hasDeclaredGrid: true, hasMap: false),
                       .disabled(.noMap))
    }

    func testMeasuringIsAvailableWithAGridAndAMap() {
        XCTAssertEqual(MeasurementControl.availability(hasDeclaredGrid: true, hasMap: true),
                       .available)
    }

    func testEveryUnavailableReasonExplainsItself() {
        // A control that is merely inert teaches the DM nothing, and they read it in front
        // of players.
        for reason in MeasurementControl.UnavailableReason.allCases {
            XCTAssertFalse(reason.explanation.isEmpty)
        }
    }

    // MARK: The inverse transform

    private let map = MapScale.grid(squaresWide: 20,
                                    imagePixelSize: CGSize(width: 1000, height: 800))

    func testAViewPointRoundTripsBackToItsMapPoint() {
        // The conversion the normal-mode mirror did not have: it only ever open-coded a
        // *delta* inside the Pawn drag, so an absolute right-click had nowhere to land.
        let frame = CGRect(x: -120, y: -60, width: 2000, height: 1600)
        for point in [MapPoint(x: 0, y: 0), MapPoint(x: 500, y: 400),
                      MapPoint(x: 999, y: 799)] {
            let view = PlayerPlacement.viewPoint(point, map: map, frame: frame)
            let back = PlayerPlacement.mapPoint(view, map: map, frame: frame)
            XCTAssertEqual(back.x, point.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, point.y, accuracy: 1e-6)
        }
    }

    func testTheInverseSurvivesAPannedFrame() {
        // The frame carries the pan on both screens, so a viewport scrolled away from the
        // origin is the normal case, not an edge case.
        let frame = CGRect(x: -740, y: -310, width: 3000, height: 2400)
        let view = PlayerPlacement.viewPoint(MapPoint(x: 250, y: 125), map: map, frame: frame)
        let back = PlayerPlacement.mapPoint(view, map: map, frame: frame)
        XCTAssertEqual(back.x, 250, accuracy: 1e-6)
        XCTAssertEqual(back.y, 125, accuracy: 1e-6)
    }

    func testADegenerateFrameDoesNotDivideByZero() {
        let back = PlayerPlacement.mapPoint(CGPoint(x: 10, y: 10), map: map, frame: .zero)
        XCTAssertEqual(back, MapPoint(x: 0, y: 0))
    }

    // MARK: Hit-testing a Pawn

    func testARightClickOnAPawnAnchorsToIt() {
        // Spec 5: a Measurement from a pawn starts at that pawn's centre, so the DM does
        // not have to click the exact pixel under a token they can see.
        let pawn = Pawn(at: MapPoint(x: 500, y: 400), label: "A", colorHex: "#ff0000",
                        brightSquares: 4)
        let origin = MeasurementControl.origin(forClickAt: MapPoint(x: 505, y: 404),
                                               pawns: [pawn], pixelsPerSquare: 50)
        XCTAssertEqual(origin, .pawn(pawn.id))
    }

    func testARightClickAwayFromAnyPawnAnchorsToThePoint() {
        let pawn = Pawn(at: MapPoint(x: 500, y: 400), label: "A", colorHex: "#ff0000",
                        brightSquares: 4)
        let click = MapPoint(x: 900, y: 700)
        XCTAssertEqual(MeasurementControl.origin(forClickAt: click, pawns: [pawn],
                                                 pixelsPerSquare: 50),
                       .point(click))
    }

    func testTheNearestPawnWins() {
        let near = Pawn(at: MapPoint(x: 500, y: 400), label: "near", colorHex: "#ff0000",
                        brightSquares: 4)
        let far = Pawn(at: MapPoint(x: 530, y: 400), label: "far", colorHex: "#00ff00",
                       brightSquares: 4)
        XCTAssertEqual(MeasurementControl.origin(forClickAt: MapPoint(x: 510, y: 400),
                                                 pawns: [near, far], pixelsPerSquare: 50),
                       .pawn(near.id))
    }

    func testABigPawnIsHitOverItsWholeFootprint() {
        // A Big Pawn spans 2x2, so a click inside its token that is more than half a
        // square from its centre still belongs to it.
        let big = Pawn(at: MapPoint(x: 500, y: 400), label: "ogre", colorHex: "#ff0000",
                       brightSquares: 4, isBig: true)
        XCTAssertEqual(MeasurementControl.origin(forClickAt: MapPoint(x: 540, y: 400),
                                                 pawns: [big], pixelsPerSquare: 50),
                       .pawn(big.id))
    }

    // MARK: Direction

    func testDirectionRunsFromTheOriginToTheCursor() {
        let east = MeasurementControl.direction(from: MapPoint(x: 100, y: 100),
                                                to: MapPoint(x: 200, y: 100))
        XCTAssertEqual(east, 0, accuracy: 1e-9)

        let south = MeasurementControl.direction(from: MapPoint(x: 100, y: 100),
                                                 to: MapPoint(x: 100, y: 200))
        XCTAssertEqual(south, .pi / 2, accuracy: 1e-9)
    }

    func testDirectionHoldsSteadyWhenTheCursorSitsOnTheOrigin() {
        // Otherwise the shape spins wildly as the mouse crosses its own apex.
        XCTAssertEqual(MeasurementControl.direction(from: MapPoint(x: 100, y: 100),
                                                    to: MapPoint(x: 100, y: 100)),
                       0, accuracy: 1e-9)
    }
}

/// The lifecycle of a Measurement on `AppState`: starting, dismissing, and the events that
/// clear it out from under the DM.
@MainActor
final class MeasurementLifecycleTests: XCTestCase {
    private func state() -> AppState {
        let defaults = UserDefaults(suiteName: "MeasurementLifecycleTests.\(UUID().uuidString)")!
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.squaresWide = 20
        return state
    }

    private func pawn(_ label: String = "A") -> Pawn {
        Pawn(at: MapPoint(x: 500, y: 400), label: label, colorHex: "#ff0000", brightSquares: 4)
    }

    func testAMeasurementStartsEmpty() {
        XCTAssertNil(state().measurement)
    }

    func testSettingAndDismissingAMeasurement() {
        let state = state()
        state.setMeasurement(Measurement(origin: .point(MapPoint(x: 10, y: 10)),
                                         shape: .circle, distance: 4, direction: 0))
        XCTAssertNotNil(state.measurement)
        state.setMeasurement(nil)
        XCTAssertNil(state.measurement)
    }

    func testAMeasurementAnchoredToAMissingPawnResolvesToNothing() {
        // The `resolved…` guard Solo Sight uses: a stale ID must be inert rather than
        // drawing a shape at the map origin.
        let state = state()
        state.setMeasurement(Measurement(origin: .pawn(UUID()), shape: .cone,
                                         distance: 6, direction: 0))
        XCTAssertNil(state.resolvedMeasurement)
    }

    func testAMeasurementAnchoredToALivePawnResolves() {
        let state = state()
        let pawn = pawn()
        state.fog.pawns = [pawn]
        state.setMeasurement(Measurement(origin: .pawn(pawn.id), shape: .cone,
                                         distance: 6, direction: 0))
        XCTAssertNotNil(state.resolvedMeasurement)
    }

    func testDeletingTheAnchorPawnClearsTheMeasurement() {
        let state = state()
        let pawn = pawn()
        state.fog.pawns = [pawn]
        state.setMeasurement(Measurement(origin: .pawn(pawn.id), shape: .cone,
                                         distance: 6, direction: 0))
        state.fog.pawns = []
        XCTAssertNil(state.measurement)
    }

    func testMovingTheAnchorPawnKeepsTheMeasurement() {
        // Spec: an anchored Measurement follows its Pawn. Deleting is the end of it;
        // moving is not.
        let state = state()
        let pawn = pawn()
        state.fog.pawns = [pawn]
        state.setMeasurement(Measurement(origin: .pawn(pawn.id), shape: .cone,
                                         distance: 6, direction: 0))
        state.movePawn(id: pawn.id, to: MapPoint(x: 600, y: 500))
        XCTAssertNotNil(state.measurement)
        XCTAssertEqual(state.measurementOriginPoint, MapPoint(x: 600, y: 500))
    }

    func testTheShapeCanChangeWithoutLosingTheOriginOrDistance() {
        // How a DM compares a cone against a circle from the same Pawn: changing the shape
        // re-projects in place rather than starting again.
        let state = state()
        state.setMeasurement(Measurement(origin: .point(MapPoint(x: 10, y: 10)),
                                         shape: .circle, distance: 4, direction: 1))
        var changed = state.measurement!
        changed.shape = .cone
        state.setMeasurement(changed)

        XCTAssertEqual(state.measurement?.shape, .cone)
        XCTAssertEqual(state.measurement?.origin, .point(MapPoint(x: 10, y: 10)))
        XCTAssertEqual(state.measurement?.distance, 4)
    }

    func testEnteringFogEditingClearsTheMeasurement() {
        // Measuring is a play action; fog editing is authoring. The same boundary Solo
        // Sight observes.
        let state = state()
        state.setMeasurement(Measurement(origin: .point(MapPoint(x: 10, y: 10)),
                                         shape: .circle, distance: 4, direction: 0))
        state.beginFogEditing()
        XCTAssertNil(state.measurement)
    }
}
