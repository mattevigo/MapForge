import XCTest
@testable import MapForge

/// The Combat Log's on-disk vocabulary.
///
/// Everything here is a format commitment: files written today must be readable by every
/// later version, because ADR-0008 makes the Log the state rather than a record of it.
final class CombatLogFormatTests: XCTestCase {
    private let grog = UUID()

    private func roundTrip(_ change: Change) throws -> Change {
        try JSONDecoder().decode(Change.self, from: JSONEncoder().encode(change))
    }

    func testAHitPointChangeCarriesBothBeforeAndAfter() throws {
        // Never a delta: a fold of deltas cannot be corrected without recomputing
        // everything downstream, and a fold of before/after pairs can.
        let change = Change.hpChanged(combatantID: grog, from: 14, to: 9)
        XCTAssertEqual(try roundTrip(change), change)
    }

    func testAChangeIsTaggedByTypeInTheJSON() throws {
        // A DM opens this file and reads it. An externally tagged enum is the shape that
        // reads as English; Swift's default for enums with payloads is not.
        let data = try JSONEncoder().encode(Change.hpChanged(combatantID: grog, from: 14, to: 9))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "hpChanged")
        XCTAssertEqual(json["from"] as? Int, 14)
        XCTAssertEqual(json["to"] as? Int, 9)
    }

    func testEveryChangeRoundTrips() throws {
        // One assertion per case, so a new case added without a codec is caught here
        // rather than by a DM whose Log will not open.
        let changes: [Change] = [
            .moved(combatantID: grog,
                   from: MapPoint(x: 100, y: 200),
                   to: MapPoint(x: 340, y: 200),
                   distanceSquares: 4.8),
            .hpChanged(combatantID: grog, from: 14, to: 9),
            .hpChanged(combatantID: grog, from: nil, to: 26),
            .tempHPChanged(combatantID: grog, from: 0, to: 5),
            .maxHPChanged(combatantID: grog, from: nil, to: 32),
            .acChanged(combatantID: grog, from: 10, to: 17),
            .conditionAdded(combatantID: grog, condition: .prone),
            .conditionRemoved(combatantID: grog, condition: .prone),
            .exhaustionChanged(combatantID: grog, from: 0, to: 2),
            .concentrationChanged(combatantID: grog, isConcentrating: true),
            .noteAdded(combatantID: grog, text: "shoved the ogre into the pit"),
            .initiativeChanged(combatantID: grog, from: 14, to: 18),
            .orderChanged(order: [grog, UUID()]),
            .combatantJoined(combatantID: grog, name: "Grog", kind: .player,
                             initiative: 18, block: StatBlock(currentHP: 26, maxHP: 26)),
            .combatantRemoved(combatantID: grog),
        ]
        for change in changes {
            XCTAssertEqual(try roundTrip(change), change, "\(change) did not survive the round trip")
        }
    }

    func testAnUnknownChangeTypeDecodesAsUnrecognised() throws {
        // A Log written by a later version must not be unreadable by this one: losing a
        // whole session because one line mentions something new is the worst possible
        // failure for a file whose purpose is to be kept.
        let json = Data(#"{"type":"polymorphedInto","combatantID":"\#(grog.uuidString)"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Change.self, from: json), .unrecognised)
    }

    func testATurnLineCarriesItsRoundAndItsCombatant() throws {
        // The shape the whole format is built around: one line per Turn, saying whose it
        // was, which Round it was, and everything that happened during it.
        let line = LogLine.turn(round: 2,
                                combatantID: grog,
                                changes: [.hpChanged(combatantID: grog, from: 14, to: 9)],
                                endedAt: Date(timeIntervalSince1970: 1_757_600_000))
        let decoded = try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(decoded, line)
    }

    func testEveryLineKindRoundTrips() throws {
        let at = Date(timeIntervalSince1970: 1_757_600_000)
        let lines: [LogLine] = [
            .encounterStarted(startedAt: at, order: [grog], combatants: [
                Combatant(id: grog, name: "Grog", kind: .player, initiative: 18,
                          block: StatBlock(currentHP: 26, maxHP: 26)),
            ]),
            .turn(round: 1, combatantID: grog, changes: [], endedAt: at),
            .correction(targetRound: 1, targetCombatantID: grog,
                        changes: [.noteAdded(combatantID: grog, text: "forgot the poison")],
                        recordedAt: at),
            .encounterEnded(endedAt: at),
        ]
        for line in lines {
            let decoded = try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line))
            XCTAssertEqual(decoded, line, "\(line) did not survive the round trip")
        }
    }
}
