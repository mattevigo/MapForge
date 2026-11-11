import SwiftUI
import XCTest
@testable import MapForge

/// A Measurement anchored to a Pawn is drawn in that Pawn's colour; one taken from a point
/// is no one's and stays green. See `CONTEXT.md`'s **Measurement Origin**.
final class MeasurementColorTests: XCTestCase {
    private func pawn(_ kind: PawnKind, colorHex: String) -> Pawn {
        var pawn = Pawn(at: MapPoint(x: 100, y: 100), label: "A", colorHex: colorHex,
                        brightSquares: 4)
        pawn.kind = kind
        return pawn
    }

    private func color(of measurement: MapForge.Measurement, pawns: [Pawn]) -> Color {
        measurement.color { id in pawns.first(where: { $0.id == id }) }
    }

    func testAMeasurementFromAPawnOfEveryKindTakesThatPawnsColour() {
        for kind in PawnKind.allCases {
            let pawn = pawn(kind, colorHex: "#3366CC")
            let measurement = MapForge.Measurement(origin: .pawn(pawn.id), shape: .cone,
                                                   distance: 6, direction: 0)
            XCTAssertEqual(color(of: measurement, pawns: [pawn]),
                           Color(.sRGB, red: 0x33 / 255, green: 0x66 / 255, blue: 0xCC / 255),
                           "\(kind)")
        }
    }

    func testAPawnWithAFaceStillGivesItsMeasurementItsOwnColour() {
        // The Face covers the colour on the token, not in the Pawn: the colour is still
        // its own underneath, and the table still needs to tell whose Measurement it is.
        var pawn = pawn(.creature, colorHex: "#3366CC")
        pawn.face = PawnFace(file: "goblin.png", origin: .hand)
        let measurement = MapForge.Measurement(origin: .pawn(pawn.id), shape: .circle,
                                               distance: 4, direction: 0)
        XCTAssertEqual(color(of: measurement, pawns: [pawn]),
                       Color(.sRGB, red: 0x33 / 255, green: 0x66 / 255, blue: 0xCC / 255))
    }

    func testAMeasurementFromAPointStaysGreenEvenWithAPawnStandingThere() {
        // A point Origin is no one's, wherever it happens to be.
        let pawn = pawn(.player, colorHex: "#3366CC")
        let measurement = MapForge.Measurement(origin: .point(pawn.at), shape: .circle,
                                               distance: 4, direction: 0)
        XCTAssertEqual(color(of: measurement, pawns: [pawn]), .green)
    }
}

/// The colour each screen draws a Measurement in, resolved on `AppState` next to its
/// Origin so the Control mirror and the Player Display cannot disagree.
@MainActor
final class MeasurementColorAppStateTests: XCTestCase {
    private let blue = Color(.sRGB, red: 0x33 / 255, green: 0x66 / 255, blue: 0xCC / 255)
    private let orange = Color(.sRGB, red: 0xFF / 255, green: 0x88 / 255, blue: 0x00 / 255)

    private func settled(_ origin: MeasurementOrigin,
                         _ shape: MeasurementShape = .circle) -> MapForge.Measurement {
        var measurement = MapForge.Measurement(origin: origin, shape: shape, distance: 4,
                                               direction: 0)
        measurement.isDistanceSettled = true
        return measurement
    }

    func testBothScreensDrawAPawnsMeasurementsInItsColourAndAPointsInGreen() {
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        state.setMeasurement(settled(.point(MapPoint(x: 10, y: 10))))
        state.pinMeasurement()
        state.setMeasurement(settled(.pawn(rogue.id), .cone))

        XCTAssertEqual(state.drawableMeasurements.map(\.color), [.green, blue])
        XCTAssertEqual(state.playerMeasurements.map(\.color), [.green, blue],
                       "the table and the DM must see the same colours")
    }

    func testRecolouringAPawnRecoloursItsLiveAndPinnedMeasurements() {
        let rogue = MeasurementFixture.rogue()
        let state = MeasurementFixture.state(with: rogue)
        state.setMeasurement(settled(.pawn(rogue.id)))
        state.pinMeasurement()
        state.setMeasurement(settled(.pawn(rogue.id), .cone))

        var recolour = EditPawnDraft(pawn: rogue)
        recolour.colorHex = "#FF8800"
        state.updatePawn(id: rogue.id, with: recolour)

        XCTAssertEqual(state.drawableMeasurements.map(\.color), [orange, orange])
    }
}
