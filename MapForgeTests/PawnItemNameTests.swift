import XCTest
@testable import MapForge

/// A Treasure remembers which Item it was — advisorily, by name, as a Creature remembers its
/// Monster. See `docs/adr/0031-an-item-says-so-in-its-frontmatter.md`.
final class PawnItemNameTests: XCTestCase {
    private func makePawn(itemName: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: "Bo1", colorHex: "#D4A017",
             brightSquares: 0, kind: .treasure, itemName: itemName)
    }

    func testTheItemSurvivesTheFogFile() throws {
        let document = FogDocument(pawns: [makePawn(itemName: "Borsa")])
        let decoded = try JSONDecoder().decode(FogDocument.self,
                                               from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.pawns.first?.itemName, "Borsa")
    }

    func testAFileWithoutTheKeyDecodes() throws {
        // Every .fog.json written before the Treasury existed.
        let json = Data("""
        {
          "version": 2, "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)", "label": "1", "colorHex": "#D4A017",
            "kind": "treasure",
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 0, "dimSquares": 1, "isOn": true
            }
          }]
        }
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(FogDocument.self, from: json).pawns[0].itemName)
    }

    func testAPawnThatIsNoItemWritesNoKey() throws {
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makePawn())) as? [String: Any]
        XCTAssertNotNil(object)
        XCTAssertNil(object?["itemName"])
    }

    func testTheNameIsReadableInTheFile() throws {
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makePawn(itemName: "Borsa"))) as? [String: Any]
        XCTAssertEqual(object?["itemName"] as? String, "Borsa")
    }
}
