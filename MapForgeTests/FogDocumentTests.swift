import XCTest
@testable import MapForge

final class FogDocumentTests: XCTestCase {

    func testRoundTripPreservesAWall() throws {
        // The whole point of the file: what the DM drew comes back exactly.
        let document = FogDocument(walls: [Wall(from: MapPoint(x: 100, y: 200),
                                                to: MapPoint(x: 340, y: 200))])
        let decoded = try roundTrip(document)
        XCTAssertEqual(decoded, document)
    }

    func testFileNamesItsUnits() throws {
        // The file outlives the app that wrote it. A reader opening it in a text editor
        // must not have to guess whether 340 is pixels, inches or squares — Walls are in
        // image pixels while Light radii are in Grid squares, and confusing the two
        // silently misplaces everything.
        let document = FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 340, y: 0))])
        let json = String(data: try JSONEncoder().encode(document), encoding: .utf8)!
        XCTAssertTrue(json.contains("imagePixels"), "units missing from \(json)")
    }

    func testCoordinatesAreNamedNotPositional() throws {
        // Naming the unit is only half of it. Encoded as a bare CGPoint the pair is
        // [340,0] — a reader knows they are pixels and must still guess which is x.
        let document = FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0),
                                                to: MapPoint(x: 340, y: 12))])
        let json = String(data: try JSONEncoder().encode(document), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"x\":340"), "x not named in \(json)")
        XCTAssertTrue(json.contains("\"y\":12"), "y not named in \(json)")
    }

    func testRoundTripPreservesLightsAndPawns() throws {
        let document = FogDocument(
            walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))],
            lights: [Light(at: MapPoint(x: 50, y: 50), brightSquares: 4)],
            pawns: [Pawn(at: MapPoint(x: 10, y: 10), label: "Vex", colorHex: "#C81E1E",
                         brightSquares: 6)]
        )
        XCTAssertEqual(try roundTrip(document), document)
    }

    func testDimRadiusDefaultsToTwiceBright() {
        // The 5e convention every light source is written in — "bright 20 ft, dim for
        // an additional 20". A torch is entered as one number, not two.
        XCTAssertEqual(Light(at: MapPoint(x: 0, y: 0), brightSquares: 4).dimSquares, 8)
    }

    func testDimRadiusCanBeSetIndependently() {
        // Legal and meaningful: a sharp-edged source with no falloff band.
        XCTAssertEqual(Light(at: MapPoint(x: 0, y: 0), brightSquares: 4, dimSquares: 0).dimSquares, 0)
    }

    func testALightIsOnWhenPlaced() {
        // Placing a Light and seeing nothing happen would read as a bug.
        XCTAssertTrue(Light(at: MapPoint(x: 0, y: 0), brightSquares: 4).isOn)
    }

    // MARK: Helpers

    private func roundTrip(_ document: FogDocument) throws -> FogDocument {
        let data = try JSONEncoder().encode(document)
        return try JSONDecoder().decode(FogDocument.self, from: data)
    }
}
