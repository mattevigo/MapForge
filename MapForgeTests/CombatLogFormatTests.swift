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
            .savingThrow(combatantID: grog, ability: .dexterity,
                         roll: Roll(d20: 16, modifier: 5, difficultyClass: 15)),
            .savingThrow(combatantID: grog, ability: .wisdom,
                         roll: Roll(d20: 3, modifier: -1)),
            .abilityCheck(combatantID: grog, skill: .stealth,
                          roll: Roll(d20: 12, modifier: 7, difficultyClass: 15)),
            .abilityCheck(combatantID: grog, skill: .perception,
                          roll: Roll(d20: 20, modifier: 0)),
        ]
        for change in changes {
            XCTAssertEqual(try roundTrip(change), change, "\(change) did not survive the round trip")
        }
    }

    // MARK: Rolls

    /// The `Roll` is written flat rather than nested, because a DM opens this file and
    /// reads it: `"d20": 16, "modifier": 5` on the line itself, not under a sub-object.
    func testARollIsWrittenFlatAndTaggedByType() throws {
        let change = Change.savingThrow(combatantID: grog, ability: .dexterity,
                                        roll: Roll(d20: 16, modifier: 5, difficultyClass: 15))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(change)) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "savingThrow")
        XCTAssertEqual(json["ability"] as? String, "dexterity")
        XCTAssertEqual(json["d20"] as? Int, 16)
        XCTAssertEqual(json["modifier"] as? Int, 5)
        XCTAssertEqual(json["difficultyClass"] as? Int, 15)
    }

    /// Success is `d20 + modifier >= DC`, computed on read. A stored derivable fact is the
    /// drift ADR-0008 was written against.
    func testARollNeverStoresItsVerdict() throws {
        let change = Change.abilityCheck(combatantID: grog, skill: .stealth,
                                         roll: Roll(d20: 12, modifier: 7, difficultyClass: 15))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(change)) as? [String: Any])

        XCTAssertNil(json["succeeded"], "the verdict is derived and must never be written")
        XCTAssertNil(json["total"], "the total is derived and must never be written")
    }

    /// An Ability Check stores its Skill and not its Ability: the Skill implies it, and a
    /// stored copy would let a Log disagree with itself.
    func testAnAbilityCheckStoresItsSkillAndNotItsAbility() throws {
        let change = Change.abilityCheck(combatantID: grog, skill: .stealth,
                                         roll: Roll(d20: 12, modifier: 7))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(change)) as? [String: Any])

        XCTAssertEqual(json["skill"] as? String, "stealth")
        XCTAssertNil(json["ability"], "the Ability is derived from the Skill, never stored")
    }

    /// Absent rather than null: a Roll with no Difficulty Class has no key for one, so the
    /// line reads as what it is — a number recorded before anyone decided what it beat.
    func testARollWithoutADifficultyClassOmitsTheKey() throws {
        let change = Change.savingThrow(combatantID: grog, ability: .constitution,
                                        roll: Roll(d20: 11, modifier: 2))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(change)) as? [String: Any])

        XCTAssertNil(json["difficultyClass"])
        XCTAssertEqual(try roundTrip(change), change)
    }

    /// A Roll names the Combatant it is about, like every other targeted Change.
    func testARollNamesItsCombatant() {
        XCTAssertEqual(
            Change.savingThrow(combatantID: grog, ability: .dexterity,
                               roll: Roll(d20: 16, modifier: 5)).combatantID, grog)
        XCTAssertEqual(
            Change.abilityCheck(combatantID: grog, skill: .stealth,
                                roll: Roll(d20: 12, modifier: 7)).combatantID, grog)
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
