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

    // MARK: The Grid (version 2)

    func testRoundTripPreservesTheGrid() throws {
        // The Grid lives here now (ADR 0003): Light radii are in Grid squares, so the
        // file already carried a measurement whose unit it did not define.
        let document = FogDocument(squaresWide: 24,
                                   lights: [Light(at: MapPoint(x: 50, y: 50), brightSquares: 4)])
        XCTAssertEqual(try roundTrip(document), document)
    }

    func testAnUndeclaredGridIsNil() {
        // One optional carries both facts — the value and whether the DM ever asserted
        // it. Two fields could contradict each other.
        XCTAssertNil(FogDocument().squaresWide)
    }

    func testAVersionOneFileDecodesWithNoGrid() throws {
        // Every .fog.json already written beside a Map is version 1. None may be
        // invalidated: they simply load without a Grid, which is today's behaviour.
        let json = Data("""
        {
          "version": 1,
          "walls": [{"from": {"imagePixels": {"x": 0, "y": 0}},
                     "to": {"imagePixels": {"x": 100, "y": 0}}, "id": "\(UUID().uuidString)"}],
          "lights": [],
          "pawns": []
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(FogDocument.self, from: json)
        XCTAssertNil(decoded.squaresWide, "a version 1 file conjured a Grid")
        XCTAssertEqual(decoded.walls.count, 1, "the Walls did not survive")
    }

    func testTheDocumentDeclaresVersionTwo() throws {
        let json = String(data: try JSONEncoder().encode(FogDocument()), encoding: .utf8)!
        XCTAssertEqual(FogDocument().version, 2)
        XCTAssertTrue(json.contains("\"version\":2"), "version missing from \(json)")
    }

    func testAGridAloneIsNotAnEmptyDocument() {
        // isEmpty drives file deletion. A DM who fits the Grid and stops must get it
        // back — the case that matters most on a fresh Map.
        XCTAssertFalse(FogDocument(squaresWide: 24).isEmpty)
    }

    func testNoGridAndNoFogIsEmpty() {
        // Still true, or MapForge litters the map folder with files for Maps nobody
        // authored.
        XCTAssertTrue(FogDocument().isEmpty)
    }

    func testAVersionOneFileIsRewrittenAsVersionTwo() throws {
        // `version` is decoded, so echoing it back would write "version": 1 alongside the
        // version 2 `squaresWide` key — a file that lies about its own format. Every
        // .fog.json already beside a Map takes this path the first time a Grid is fitted.
        var loaded = FogDocument()
        loaded.version = 1
        loaded.squaresWide = 24

        let json = String(data: try JSONEncoder().encode(loaded), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"version\":2"),
                      "a version 1 document was rewritten as version 1: \(json)")
        XCTAssertEqual(try roundTrip(loaded).version, 2)
    }

    // MARK: Helpers

    private func roundTrip(_ document: FogDocument) throws -> FogDocument {
        let data = try JSONEncoder().encode(document)
        return try JSONDecoder().decode(FogDocument.self, from: data)
    }
}
