import XCTest
@testable import MapForge

/// A Creature remembers which Monster it was — advisorily, by name. See
/// `docs/adr/0020-monsters-are-read-from-the-dms-notes.md`.
final class PawnMonsterNameTests: XCTestCase {
    private func makePawn(monsterName: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: "GG1", colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, monsterName: monsterName)
    }

    func testTheMonsterSurvivesTheFogFile() throws {
        let document = FogDocument(pawns: [makePawn(monsterName: "Gnoll Guerriero")])
        let decoded = try JSONDecoder().decode(FogDocument.self,
                                               from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.pawns.first?.monsterName, "Gnoll Guerriero")
    }

    func testAFileWithoutTheKeyDecodes() throws {
        // Every .fog.json written before the Bestiary existed.
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
        XCTAssertNil(try JSONDecoder().decode(FogDocument.self, from: json).pawns[0].monsterName)
    }

    func testAPawnThatIsNoMonsterWritesNoKey() throws {
        // As `characterID` is: a DM with no Bestiary sees no trace of it in their map files.
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makePawn())) as? [String: Any]
        XCTAssertNotNil(object)
        XCTAssertNil(object?["monsterName"])
    }

    func testTheNameIsReadableInTheFile() throws {
        // A name rather than an ID: the fog file is one a DM opens, and "Gnoll Guerriero" is
        // something they can read where a UUID nobody can resolve is not.
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makePawn(monsterName: "Gnoll Guerriero"))) as? [String: Any]
        XCTAssertEqual(object?["monsterName"] as? String, "Gnoll Guerriero")
    }
}
