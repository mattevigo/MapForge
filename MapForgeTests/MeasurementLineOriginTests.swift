import SwiftUI
import XCTest
@testable import MapForge

/// A Line begun from a Pawn starts where the Pawn stood when its Origin was chosen, and
/// stays there when the Pawn moves: it is a route, and a Pawn walking the route it was
/// given must not drag the route along behind it. Cone, Circle and Square still follow.
/// See `CONTEXT.md`'s **Measurement Origin**.
@MainActor
final class MeasurementLineOriginTests: XCTestCase {
    private let pixelsPerSquare: CGFloat = 50
    private let stood = MeasurementFixture.stood

    /// The Measurement a click on the Pawn's token begins, exactly as the Live View does.
    private func begin(_ shape: MeasurementShape, on pawn: Pawn,
                       in state: AppState) -> MapForge.Measurement {
        let origin = MeasurementControl.origin(forClickAt: MapPoint(x: pawn.at.x + 5,
                                                                    y: pawn.at.y + 4),
                                               pawns: state.fog.pawns,
                                               pixelsPerSquare: pixelsPerSquare,
                                               shape: shape)
        let measurement = MapForge.Measurement(origin: origin, shape: shape, distance: 0,
                                               direction: 0)
        state.setMeasurement(measurement)
        return measurement
    }

    private func total(_ state: AppState) throws -> CGFloat {
        let measurement = try XCTUnwrap(state.resolvedMeasurement)
        let origin = try XCTUnwrap(state.measurementOriginPoint)
        return measurement.chainSquares(from: origin, pixelsPerSquare: pixelsPerSquare)
    }

    func testAFinishedLineFromAPawnStaysWhereItWasDrawnWhenThePawnMoves() throws {
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        let line = begin(.line, on: rogue, in: state)
            .extended(to: MapPoint(x: 700, y: 400))
            .extended(to: MapPoint(x: 700, y: 600))
        state.setMeasurement(line.finished(origin: stood, pixelsPerSquare: pixelsPerSquare))
        XCTAssertEqual(try total(state), 8, accuracy: 1e-9, "precondition: 4 + 4 squares")

        state.movePawn(id: rogue.id, to: MapPoint(x: 900, y: 900))

        XCTAssertEqual(state.measurementOriginPoint, stood,
                       "the route moved with the Pawn walking it")
        XCTAssertEqual(state.resolvedMeasurement?.chain,
                       [MapPoint(x: 700, y: 400), MapPoint(x: 700, y: 600)])
        XCTAssertEqual(try total(state), 8, accuracy: 1e-9,
                       "the path drawn and its number disagree")
    }

    func testAPinnedLineFromAPawnStaysWhereItWasDrawnWhenThePawnMoves() throws {
        // Pinning is how a route already walked is held on screen while the DM measures the
        // next thing — the Line most likely to have its Pawn walk off along it.
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        state.setMeasurement(begin(.line, on: rogue, in: state)
            .extended(to: MapPoint(x: 700, y: 400))
            .extended(to: MapPoint(x: 700, y: 600))
            .finished(origin: stood, pixelsPerSquare: pixelsPerSquare))
        state.pinMeasurement()
        XCTAssertEqual(state.pinnedMeasurements.count, 1, "precondition: one Pinned")

        state.movePawn(id: rogue.id, to: MapPoint(x: 900, y: 900))

        let pinned = try XCTUnwrap(state.drawableMeasurements.first)
        XCTAssertEqual(state.drawableMeasurements.count, 1)
        XCTAssertEqual(pinned.origin, stood, "the Pinned route moved with the Pawn walking it")
        XCTAssertEqual(pinned.measurement.chain,
                       [MapPoint(x: 700, y: 400), MapPoint(x: 700, y: 600)])
        XCTAssertEqual(pinned.measurement.chainSquares(from: pinned.origin,
                                                       pixelsPerSquare: pixelsPerSquare),
                       8, accuracy: 1e-9, "the Pinned chain drawn and its total disagree")
    }

    func testALineStillBeingDrawnRubberBandsFromWhereThePawnStood() throws {
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        state.setMeasurement(begin(.line, on: rogue, in: state)
            .extended(to: MapPoint(x: 700, y: 400)))
        let cursor = MapPoint(x: 700, y: 600)
        func aim() throws {
            let measurement = try XCTUnwrap(state.resolvedMeasurement)
            let origin = try XCTUnwrap(state.measurementOriginPoint)
            state.setMeasurement(measurement.aimed(at: cursor, from: origin,
                                                   pixelsPerSquare: pixelsPerSquare))
        }
        try aim()
        XCTAssertEqual(try XCTUnwrap(state.resolvedMeasurement).distance, 8, accuracy: 1e-9,
                       "precondition: 4 placed + 4 live")

        state.movePawn(id: rogue.id, to: MapPoint(x: 100, y: 100))
        try aim()

        XCTAssertEqual(state.measurementOriginPoint, stood)
        XCTAssertEqual(state.resolvedMeasurement?.chain, [MapPoint(x: 700, y: 400)])
        XCTAssertEqual(try XCTUnwrap(state.resolvedMeasurement).distance, 8, accuracy: 1e-9)
    }

    // MARK: A Line that stays put is still its Pawn's

    func testALineFromAPawnEndsWhenThePawnIsDeletedLiveOrPinned() {
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        state.setMeasurement(begin(.line, on: rogue, in: state)
            .extended(to: MapPoint(x: 700, y: 400))
            .finished(origin: stood, pixelsPerSquare: pixelsPerSquare))
        state.pinMeasurement()
        state.setMeasurement(begin(.line, on: rogue, in: state)
            .extended(to: MapPoint(x: 500, y: 600)))
        XCTAssertEqual(state.pinnedMeasurements.count, 1, "precondition: one Pinned")
        XCTAssertNotNil(state.measurement, "precondition: one being drawn")

        state.removePawnFromMap(rogue.id)

        XCTAssertNil(state.measurement)
        XCTAssertTrue(state.pinnedMeasurements.isEmpty)
        XCTAssertTrue(state.drawableMeasurements.isEmpty)
    }

    func testALineFromAPawnIsDrawnInThePawnsCurrentColour() {
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        state.setMeasurement(begin(.line, on: rogue, in: state)
            .extended(to: MapPoint(x: 700, y: 400)))

        var recolour = EditPawnDraft(pawn: rogue)
        recolour.colorHex = "#FF8800"
        state.updatePawn(id: rogue.id, with: recolour)

        XCTAssertEqual(state.drawableMeasurements.map(\.color),
                       [Color(.sRGB, red: 1, green: 0x88 / 255, blue: 0)])
    }

    // MARK: Everything else is as it was

    func testAConeACircleAndASquareFromAPawnStillFollowIt() {
        for shape in [MeasurementShape.cone, .circle, .square] {
            let rogue = MeasurementFixture.rogue()
            let state = MeasurementFixture.state(with: rogue)
            var measurement = begin(shape, on: rogue, in: state)
            measurement.distance = 3
            state.setMeasurement(measurement)

            state.movePawn(id: rogue.id, to: MapPoint(x: 900, y: 900))

            XCTAssertEqual(state.measurementOriginPoint, MapPoint(x: 900, y: 900), "\(shape)")
            XCTAssertEqual(state.drawableMeasurements.map(\.origin),
                           [MapPoint(x: 900, y: 900)], "\(shape)")
        }
    }

    func testALineFromAPointIsAPointOriginAsBefore() throws {
        // A click just past the token's edge — the Rogue's disc reaches 25 px from its
        // centre, and this lands 30 px out — is a click on the Map, however near.
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        let click = MapPoint(x: stood.x + 30, y: stood.y)
        let origin = MeasurementControl.origin(forClickAt: click, pawns: state.fog.pawns,
                                               pixelsPerSquare: pixelsPerSquare,
                                               shape: .line)
        XCTAssertEqual(origin, .point(click))
        state.setMeasurement(MapForge.Measurement(origin: origin, shape: .line, distance: 0,
                                                  direction: 0)
            .extended(to: MapPoint(x: click.x + 200, y: click.y))
            .extended(to: MapPoint(x: click.x + 200, y: click.y + 200))
            .finished(origin: click, pixelsPerSquare: pixelsPerSquare))
        XCTAssertEqual(try total(state), 8, accuracy: 1e-9, "precondition: 4 + 4 squares")

        // The Rogue walks onto the very point the Line was begun from.
        state.movePawn(id: rogue.id, to: click)

        XCTAssertEqual(state.measurementOriginPoint, click)
        XCTAssertEqual(state.resolvedMeasurement?.chain,
                       [MapPoint(x: click.x + 200, y: click.y),
                        MapPoint(x: click.x + 200, y: click.y + 200)])
        XCTAssertEqual(try total(state), 8, accuracy: 1e-9)
        XCTAssertEqual(state.drawableMeasurements.map(\.color), [.green],
                       "a point's Line is no one's, even with a Pawn now standing on it")
    }
}
