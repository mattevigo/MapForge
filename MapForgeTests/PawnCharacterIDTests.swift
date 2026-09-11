import XCTest
@testable import MapForge

/// A Pawn remembers which Character Stamped it — advisorily, and for one purpose only: the
/// roster's placed-count. See `docs/adr/0007-characters-are-stamped-not-linked.md`.
final class PawnCharacterIDTests: XCTestCase {
    private func makePawn(characterID: UUID? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: "Thorin", colorHex: "#C81E1E",
             brightSquares: 6, characterID: characterID)
    }

    func testAHandPlacedPawnRemembersNoCharacter() {
        // Clicking the Map to place a Pawn is untouched by this feature.
        XCTAssertNil(makePawn().characterID)
    }

    func testTheCharacterSurvivesTheFogFile() throws {
        let pawn = makePawn(characterID: UUID())
        let document = FogDocument(pawns: [pawn])
        let decoded = try JSONDecoder().decode(FogDocument.self,
                                               from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
    }

    func testAFileWithoutTheKeyDecodes() throws {
        // Every .fog.json written before Parties existed. The field is additive: an older
        // file must load exactly as it did, which is the guarantee the hand-written Codable
        // exists to provide.
        let json = Data("""
        {
          "version": 2,
          "walls": [], "lights": [],
          "pawns": [{
            "id": "\(UUID().uuidString)",
            "label": "Vex",
            "colorHex": "#C81E1E",
            "kind": "player",
            "light": {
              "id": "\(UUID().uuidString)",
              "at": {"imagePixels": {"x": 10, "y": 10}},
              "brightSquares": 6, "dimSquares": 7, "isOn": true
            }
          }]
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(FogDocument.self, from: json)
        XCTAssertEqual(decoded.pawns.count, 1)
        XCTAssertNil(decoded.pawns[0].characterID)
    }

    func testAHandPlacedPawnWritesNoCharacterKey() throws {
        // Unlike isHidden and isBig, this key is omitted when absent. A DM who has never
        // defined a Party should see no new noise in their map files, and a nil written as
        // `null` would be exactly that.
        let data = try JSONEncoder().encode(makePawn())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object, "the Pawn did not encode as an object")
        XCTAssertNil(object?["characterID"])
    }

    func testTheCharacterDoesNotChangeHowAPawnLights() {
        // The field is advisory: nothing about lighting or discovery may read it. A Stamped
        // Pawn and a hand-placed one with the same sight are the same Pawn to every other
        // part of the app.
        let stamped = makePawn(characterID: UUID())
        let handPlaced = makePawn()
        XCTAssertEqual(stamped.light.brightSquares, handPlaced.light.brightSquares)
        XCTAssertEqual(stamped.light.dimSquares, handPlaced.light.dimSquares)
        XCTAssertEqual(stamped.isDiscovered, handPlaced.isDiscovered)
        XCTAssertEqual(stamped.squaresAcross, handPlaced.squaresAcross)
    }

    func testTwoPawnsDifferingOnlyInCharacterAreNotEqual() {
        // Equality is the app's "has this changed" question, and a re-Stamp from a different
        // Character is a real change. Stated so the advisory-ness above is not mistaken for
        // the field being invisible to Equatable too.
        var stamped = makePawn(characterID: UUID())
        stamped.id = makePawn().id
        XCTAssertNotEqual(stamped.characterID, makePawn().characterID)
    }
}
