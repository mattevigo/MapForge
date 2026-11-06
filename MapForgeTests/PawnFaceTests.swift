import XCTest
@testable import MapForge

/// A Pawn's Face as the fog file records it: which kept cut, and where it came from.
/// See `docs/adr/0028-a-face-is-a-cut-kept-in-the-workspace.md`.
final class PawnFaceTests: XCTestCase {
    private func makePawn(face: PawnFace? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: "1", colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, face: face)
    }

    func testTheFaceSurvivesTheFogFile() throws {
        let face = PawnFace(file: "3F2504E0-4F89-11D3-9A0C-0305E82C3301.png", origin: .hand)
        let document = FogDocument(pawns: [makePawn(face: face)])

        let decoded = try JSONDecoder().decode(FogDocument.self,
                                               from: JSONEncoder().encode(document))

        XCTAssertEqual(decoded.pawns.first?.face, face)
    }

    func testTheFileSaysWhichCutAndThatItWasCutByHand() throws {
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makePawn(face: PawnFace(file: "a.png", origin: .hand))))
            as? [String: Any]

        let face = object?["face"] as? [String: Any]
        XCTAssertEqual(face?["file"] as? String, "a.png")
        XCTAssertEqual(face?["from"] as? String, "hand")
    }

    func testAFaceAnItemGaveSaysSoAndSurvivesTheFogFile() throws {
        let face = PawnFace(file: "b.png", origin: .item)
        let encoded = try JSONEncoder().encode(makePawn(face: face))

        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual((object?["face"] as? [String: Any])?["from"] as? String, "item")
        XCTAssertEqual(try JSONDecoder().decode(Pawn.self, from: encoded).face, face)
    }

    func testAPawnWithoutAFaceWritesNoKey() throws {
        // A DM who never gives a Pawn a Face sees no trace of the feature in their map files.
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makePawn())) as? [String: Any]

        XCTAssertNotNil(object)
        XCTAssertNil(object?["face"])
    }

    func testAFileWithoutTheKeyDecodes() throws {
        // Every .fog.json written before Faces existed.
        let json = Data("""
        {
          "version": 2, "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)", "label": "1", "colorHex": "#C81E1E",
            "kind": "creature",
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 6, "dimSquares": 7, "isOn": true
            }
          }]
        }
        """.utf8)

        XCTAssertNil(try JSONDecoder().decode(FogDocument.self, from: json).pawns[0].face)
    }

    func testTheColourIsKeptUnderTheFace() throws {
        // Covered, not replaced: removing the Face shows the colour the Pawn always had.
        let pawn = makePawn(face: PawnFace(file: "a.png", origin: .hand))

        let decoded = try JSONDecoder().decode(Pawn.self, from: JSONEncoder().encode(pawn))

        XCTAssertEqual(decoded.colorHex, "#C81E1E")
    }
}
