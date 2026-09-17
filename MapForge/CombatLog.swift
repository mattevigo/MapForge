import CoreGraphics
import Foundation

/// One Combatant as the Combat Log remembers it.
///
/// A **snapshot**, carried in the line that opens an Encounter and in every
/// `combatantJoined` Change, so a Log read years later can name a Combatant whose Pawn is
/// long gone. Not a live type: the tracker's current state is a fold over the Log, and this
/// is only ever the starting point of one.
struct Combatant: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: PawnKind
    var initiative: Int
    var block: StatBlock
}

/// One recorded mutation during a Turn.
///
/// Every value change carries the value **before and after**, never a delta. A fold of
/// deltas cannot be corrected without recomputing everything downstream; a fold of
/// before/after pairs can, which is what makes a Correction possible at all. See
/// `docs/adr/0008-combat-is-an-append-only-turn-log.md`.
///
/// Encoded externally tagged — `{"type": "hpChanged", …}` — because a DM opens this file
/// and reads it, and Swift's default shape for an enum with payloads does not read as
/// anything.
enum Change: Equatable {
    case moved(combatantID: UUID, from: MapPoint, to: MapPoint, distanceSquares: CGFloat)
    case hpChanged(combatantID: UUID, from: Int?, to: Int?)
    case tempHPChanged(combatantID: UUID, from: Int, to: Int)
    case maxHPChanged(combatantID: UUID, from: Int?, to: Int?)
    case acChanged(combatantID: UUID, from: Int, to: Int)
    case conditionAdded(combatantID: UUID, condition: Condition)
    case conditionRemoved(combatantID: UUID, condition: Condition)
    case exhaustionChanged(combatantID: UUID, from: Int, to: Int)
    case concentrationChanged(combatantID: UUID, isConcentrating: Bool)
    case noteAdded(combatantID: UUID, text: String)
    case initiativeChanged(combatantID: UUID, from: Int, to: Int)
    /// Carries no combatant: it is about the Order itself. The whole new Order, because
    /// ADR-0008 forbids recomputing it — two Combatants on 14 would sort arbitrarily and a
    /// replay could not reproduce what the table saw.
    case orderChanged(order: [UUID])
    case combatantJoined(combatantID: UUID, name: String, kind: PawnKind,
                         initiative: Int, block: StatBlock)
    case combatantRemoved(combatantID: UUID)

    /// A d20 recorded at the table. Changes nothing — the fold skips it, as it skips
    /// `.moved` and `.noteAdded` — and is here rather than in `LogLine` because `Change`
    /// is the vocabulary an older build can read past. See
    /// `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
    case savingThrow(combatantID: UUID, ability: Ability, roll: Roll)
    case abilityCheck(combatantID: UUID, skill: Skill, roll: Roll)

    /// A Change this version does not understand, read from a Log a later version wrote.
    ///
    /// Kept as a case rather than thrown away silently so the fold can count what it
    /// skipped and the file's line count still means something. Losing a whole session
    /// because one line mentions something new is the worst possible failure for a file
    /// whose entire purpose is to be kept.
    case unrecognised

    /// The Combatant a Change is about, where it is about one.
    var combatantID: UUID? {
        switch self {
        case let .moved(id, _, _, _),
             let .hpChanged(id, _, _),
             let .tempHPChanged(id, _, _),
             let .maxHPChanged(id, _, _),
             let .acChanged(id, _, _),
             let .conditionAdded(id, _),
             let .conditionRemoved(id, _),
             let .exhaustionChanged(id, _, _),
             let .concentrationChanged(id, _),
             let .noteAdded(id, _),
             let .initiativeChanged(id, _, _),
             let .combatantJoined(id, _, _, _, _),
             let .combatantRemoved(id),
             let .savingThrow(id, _, _),
             let .abilityCheck(id, _, _):
            return id
        case .orderChanged, .unrecognised:
            return nil
        }
    }
}

extension Change: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, combatantID, from, to, distanceSquares, condition
        case isConcentrating, text, order, name, kind, initiative, block
        // A Roll, written flat: a DM opens this file and reads it.
        case ability, skill, d20, modifier, difficultyClass
    }

    private enum Kind: String {
        case moved, hpChanged, tempHPChanged, maxHPChanged, acChanged
        case conditionAdded, conditionRemoved, exhaustionChanged, concentrationChanged
        case noteAdded, initiativeChanged, orderChanged, combatantJoined, combatantRemoved
        case savingThrow, abilityCheck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: raw) else {
            self = .unrecognised
            return
        }
        let combatantID = try container.decodeIfPresent(UUID.self, forKey: .combatantID)
        func requiredID() throws -> UUID {
            guard let combatantID else {
                throw DecodingError.keyNotFound(CodingKeys.combatantID, .init(
                    codingPath: container.codingPath,
                    debugDescription: "\(raw) must name the Combatant it is about"))
            }
            return combatantID
        }

        switch kind {
        case .moved:
            self = .moved(combatantID: try requiredID(),
                          from: try container.decode(MapPoint.self, forKey: .from),
                          to: try container.decode(MapPoint.self, forKey: .to),
                          distanceSquares: try container.decode(CGFloat.self,
                                                                forKey: .distanceSquares))
        case .hpChanged:
            self = .hpChanged(combatantID: try requiredID(),
                              from: try container.decodeIfPresent(Int.self, forKey: .from),
                              to: try container.decodeIfPresent(Int.self, forKey: .to))
        case .tempHPChanged:
            self = .tempHPChanged(combatantID: try requiredID(),
                                  from: try container.decode(Int.self, forKey: .from),
                                  to: try container.decode(Int.self, forKey: .to))
        case .maxHPChanged:
            self = .maxHPChanged(combatantID: try requiredID(),
                                 from: try container.decodeIfPresent(Int.self, forKey: .from),
                                 to: try container.decodeIfPresent(Int.self, forKey: .to))
        case .acChanged:
            self = .acChanged(combatantID: try requiredID(),
                              from: try container.decode(Int.self, forKey: .from),
                              to: try container.decode(Int.self, forKey: .to))
        case .conditionAdded:
            self = .conditionAdded(combatantID: try requiredID(),
                                   condition: try container.decode(Condition.self,
                                                                   forKey: .condition))
        case .conditionRemoved:
            self = .conditionRemoved(combatantID: try requiredID(),
                                     condition: try container.decode(Condition.self,
                                                                     forKey: .condition))
        case .exhaustionChanged:
            self = .exhaustionChanged(combatantID: try requiredID(),
                                      from: try container.decode(Int.self, forKey: .from),
                                      to: try container.decode(Int.self, forKey: .to))
        case .concentrationChanged:
            self = .concentrationChanged(combatantID: try requiredID(),
                                         isConcentrating: try container.decode(
                                            Bool.self, forKey: .isConcentrating))
        case .noteAdded:
            self = .noteAdded(combatantID: try requiredID(),
                              text: try container.decode(String.self, forKey: .text))
        case .initiativeChanged:
            self = .initiativeChanged(combatantID: try requiredID(),
                                      from: try container.decode(Int.self, forKey: .from),
                                      to: try container.decode(Int.self, forKey: .to))
        case .orderChanged:
            self = .orderChanged(order: try container.decode([UUID].self, forKey: .order))
        case .combatantJoined:
            self = .combatantJoined(combatantID: try requiredID(),
                                    name: try container.decode(String.self, forKey: .name),
                                    kind: try container.decode(PawnKind.self, forKey: .kind),
                                    initiative: try container.decode(Int.self, forKey: .initiative),
                                    block: try container.decode(StatBlock.self, forKey: .block))
        case .combatantRemoved:
            self = .combatantRemoved(combatantID: try requiredID())
        case .savingThrow:
            self = .savingThrow(combatantID: try requiredID(),
                                ability: try container.decode(Ability.self, forKey: .ability),
                                roll: try Self.decodeRoll(from: container))
        case .abilityCheck:
            self = .abilityCheck(combatantID: try requiredID(),
                                 skill: try container.decode(Skill.self, forKey: .skill),
                                 roll: try Self.decodeRoll(from: container))
        }
    }

    /// The flat half of a Roll. `succeeded` and `total` are derived and never on disk.
    private static func decodeRoll(
        from container: KeyedDecodingContainer<CodingKeys>) throws -> Roll {
        Roll(d20: try container.decode(Int.self, forKey: .d20),
             modifier: try container.decode(Int.self, forKey: .modifier),
             difficultyClass: try container.decodeIfPresent(Int.self, forKey: .difficultyClass))
    }

    private static func encode(_ roll: Roll,
                               into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(roll.d20, forKey: .d20)
        try container.encode(roll.modifier, forKey: .modifier)
        // Absent rather than null when the DM did not set one.
        try container.encodeIfPresent(roll.difficultyClass, forKey: .difficultyClass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .moved(id, from, to, distance):
            try container.encode(Kind.moved.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(distance, forKey: .distanceSquares)
        case let .hpChanged(id, from, to):
            try container.encode(Kind.hpChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encodeIfPresent(from, forKey: .from)
            try container.encodeIfPresent(to, forKey: .to)
        case let .tempHPChanged(id, from, to):
            try container.encode(Kind.tempHPChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .maxHPChanged(id, from, to):
            try container.encode(Kind.maxHPChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encodeIfPresent(from, forKey: .from)
            try container.encodeIfPresent(to, forKey: .to)
        case let .acChanged(id, from, to):
            try container.encode(Kind.acChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .conditionAdded(id, condition):
            try container.encode(Kind.conditionAdded.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(condition, forKey: .condition)
        case let .conditionRemoved(id, condition):
            try container.encode(Kind.conditionRemoved.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(condition, forKey: .condition)
        case let .exhaustionChanged(id, from, to):
            try container.encode(Kind.exhaustionChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .concentrationChanged(id, isConcentrating):
            try container.encode(Kind.concentrationChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(isConcentrating, forKey: .isConcentrating)
        case let .noteAdded(id, text):
            try container.encode(Kind.noteAdded.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(text, forKey: .text)
        case let .initiativeChanged(id, from, to):
            try container.encode(Kind.initiativeChanged.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .orderChanged(order):
            try container.encode(Kind.orderChanged.rawValue, forKey: .type)
            try container.encode(order, forKey: .order)
        case let .combatantJoined(id, name, kind, initiative, block):
            try container.encode(Kind.combatantJoined.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(name, forKey: .name)
            try container.encode(kind, forKey: .kind)
            try container.encode(initiative, forKey: .initiative)
            try container.encode(block, forKey: .block)
        case let .combatantRemoved(id):
            try container.encode(Kind.combatantRemoved.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
        case let .savingThrow(id, ability, roll):
            try container.encode(Kind.savingThrow.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            try container.encode(ability, forKey: .ability)
            try Self.encode(roll, into: &container)
        case let .abilityCheck(id, skill, roll):
            try container.encode(Kind.abilityCheck.rawValue, forKey: .type)
            try container.encode(id, forKey: .combatantID)
            // The Skill only: its Ability is derived, and a stored copy could disagree.
            try container.encode(skill, forKey: .skill)
            try Self.encode(roll, into: &container)
        case .unrecognised:
            // Re-encoding a Change this version never understood would either invent a
            // type or drop the line's meaning. The reader keeps such a Change in memory;
            // nothing writes one back, because a Log is only ever appended to.
            throw EncodingError.invalidValue(self, .init(
                codingPath: container.codingPath,
                debugDescription: "an unrecognised Change is read-only and is never written back"))
        }
    }
}

/// One line of a Combat Log.
///
/// The file is JSONL — one of these per line, appended and never rewritten. A Turn's line
/// is written when the Turn ends; a Correction is a new line naming the Turn it amends,
/// which is what keeps the file append-only while still letting a DM fix Round 2 from
/// Round 4. See `docs/adr/0010-corrections-are-appended-never-edited.md`.
enum LogLine: Equatable {
    /// Opens the file. Carries the settled Order and a snapshot of every Combatant, so
    /// this line alone reconstructs the state the fight began in.
    case encounterStarted(startedAt: Date, order: [UUID], combatants: [Combatant])
    case turn(round: Int, combatantID: UUID, changes: [Change], endedAt: Date)
    case correction(targetRound: Int, targetCombatantID: UUID,
                    changes: [Change], recordedAt: Date)
    case encounterEnded(endedAt: Date)
}

extension LogLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case line, startedAt, endedAt, recordedAt, order, combatants
        case round, combatantID, changes, targetRound, targetCombatantID
    }

    private enum Kind: String, Codable {
        case encounterStarted, turn, correction, encounterEnded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .line) {
        case .encounterStarted:
            self = .encounterStarted(
                startedAt: try container.decode(Date.self, forKey: .startedAt),
                order: try container.decode([UUID].self, forKey: .order),
                combatants: try container.decode([Combatant].self, forKey: .combatants))
        case .turn:
            self = .turn(round: try container.decode(Int.self, forKey: .round),
                         combatantID: try container.decode(UUID.self, forKey: .combatantID),
                         changes: try container.decode([Change].self, forKey: .changes),
                         endedAt: try container.decode(Date.self, forKey: .endedAt))
        case .correction:
            self = .correction(
                targetRound: try container.decode(Int.self, forKey: .targetRound),
                targetCombatantID: try container.decode(UUID.self, forKey: .targetCombatantID),
                changes: try container.decode([Change].self, forKey: .changes),
                recordedAt: try container.decode(Date.self, forKey: .recordedAt))
        case .encounterEnded:
            self = .encounterEnded(endedAt: try container.decode(Date.self, forKey: .endedAt))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .encounterStarted(startedAt, order, combatants):
            try container.encode(Kind.encounterStarted, forKey: .line)
            try container.encode(startedAt, forKey: .startedAt)
            try container.encode(order, forKey: .order)
            try container.encode(combatants, forKey: .combatants)
        case let .turn(round, combatantID, changes, endedAt):
            try container.encode(Kind.turn, forKey: .line)
            try container.encode(round, forKey: .round)
            try container.encode(combatantID, forKey: .combatantID)
            try container.encode(changes, forKey: .changes)
            try container.encode(endedAt, forKey: .endedAt)
        case let .correction(targetRound, targetCombatantID, changes, recordedAt):
            try container.encode(Kind.correction, forKey: .line)
            try container.encode(targetRound, forKey: .targetRound)
            try container.encode(targetCombatantID, forKey: .targetCombatantID)
            try container.encode(changes, forKey: .changes)
            try container.encode(recordedAt, forKey: .recordedAt)
        case let .encounterEnded(endedAt):
            try container.encode(Kind.encounterEnded, forKey: .line)
            try container.encode(endedAt, forKey: .endedAt)
        }
    }
}
