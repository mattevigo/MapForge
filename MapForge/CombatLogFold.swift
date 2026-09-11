import Foundation

/// An Encounter as its Combat Log describes it.
///
/// Not stored anywhere: this is what `CombatLogFold.fold` produces, and it is the only
/// place the tracker's numbers come from. See
/// `docs/adr/0008-combat-is-an-append-only-turn-log.md`.
struct EncounterState: Equatable {
    /// The sequence Combatants take Turns in — recorded, never recomputed, because two
    /// Combatants on 14 would sort arbitrarily and a replay could not reproduce the table.
    var order: [UUID] = []
    var round = 1
    var blocks: [UUID: StatBlock] = [:]
    /// Listed but taking no Turns. A monster that died in Round 2 is part of what happened.
    var removed: Set<UUID> = []
    var hasEnded = false

    /// Names and kinds as the Log recorded them, so a Combatant can be described long
    /// after its Pawn is gone.
    fileprivate var names: [UUID: String] = [:]
    fileprivate var kinds: [UUID: PawnKind] = [:]
    fileprivate var initiatives: [UUID: Int] = [:]

    func name(of combatant: UUID) -> String? { names[combatant] }
    func kind(of combatant: UUID) -> PawnKind? { kinds[combatant] }
    func initiative(of combatant: UUID) -> Int? { initiatives[combatant] }

    /// The Combatants still taking Turns, in Order.
    var active: [UUID] { order.filter { !removed.contains($0) } }
}

/// Reads a Combat Log back as the state it describes.
///
/// A pure function over `[LogLine]`: no file access, no `AppState`, no clock — the shape
/// `Visibility` and `ScaleMath` already have, and the reason this can be tested exhaustively
/// while the UI cannot.
enum CombatLogFold {
    /// Every line applied in the order it happened, which is **not** the order it was
    /// written: a Correction amends the Turn it targets, so it lands there rather than at
    /// the end of the file. That is the whole difference between an append-only Log and a
    /// mutable one, and it is why a DM can fix Round 1 from Round 4 without the file lying.
    static func fold(_ lines: [LogLine]) -> EncounterState {
        var state = EncounterState()

        // Corrections gathered by the Turn they target, so each can be applied in place.
        // Keyed by round and Combatant, which together name a Turn — a Combatant acts at
        // most once per Round.
        var corrections: [TurnKey: [Change]] = [:]
        for line in lines {
            guard case let .correction(targetRound, targetCombatantID, changes, _) = line else {
                continue
            }
            corrections[TurnKey(round: targetRound, combatantID: targetCombatantID),
                        default: []].append(contentsOf: changes)
        }

        for line in lines {
            switch line {
            case let .encounterStarted(_, order, combatants):
                state.order = order
                for combatant in combatants {
                    state.blocks[combatant.id] = combatant.block
                    state.names[combatant.id] = combatant.name
                    state.kinds[combatant.id] = combatant.kind
                    state.initiatives[combatant.id] = combatant.initiative
                }

            case let .turn(round, combatantID, changes, _):
                state.round = round
                for change in changes { apply(change, to: &state) }
                // The Turn's own Changes first, then anything amending it — a Correction
                // is what the DM wishes had happened during this Turn, and it has to beat
                // what they recorded at the time.
                let key = TurnKey(round: round, combatantID: combatantID)
                for change in corrections[key] ?? [] { apply(change, to: &state) }

            case .correction:
                // Already applied above, at the Turn it targets. A Correction naming a
                // Turn that never happened is ignored rather than fatal: a hand-edited
                // file must not cost a DM the rest of the fight.
                continue

            case .encounterEnded:
                state.hasEnded = true
            }
        }
        return state
    }

    private struct TurnKey: Hashable {
        var round: Int
        var combatantID: UUID
    }

    private static func apply(_ change: Change, to state: inout EncounterState) {
        switch change {
        case let .hpChanged(id, _, to):
            state.blocks[id, default: StatBlock()].currentHP = to
        case let .tempHPChanged(id, _, to):
            state.blocks[id, default: StatBlock()].temporaryHP = to
        case let .maxHPChanged(id, _, to):
            state.blocks[id, default: StatBlock()].maxHP = to
        case let .acChanged(id, _, to):
            state.blocks[id, default: StatBlock()].armorClass = to
        case let .conditionAdded(id, condition):
            state.blocks[id, default: StatBlock()].conditions.insert(condition)
        case let .conditionRemoved(id, condition):
            state.blocks[id, default: StatBlock()].conditions.remove(condition)
        case let .exhaustionChanged(id, _, to):
            state.blocks[id, default: StatBlock()].exhaustion = to
        case let .concentrationChanged(id, isConcentrating):
            state.blocks[id, default: StatBlock()].isConcentrating = isConcentrating
        case let .initiativeChanged(id, _, to):
            state.initiatives[id] = to
        case let .orderChanged(order):
            state.order = order
        case let .combatantJoined(id, name, kind, initiative, block):
            state.blocks[id] = block
            state.names[id] = name
            state.kinds[id] = kind
            state.initiatives[id] = initiative
            if !state.order.contains(id) { state.order.append(id) }
        case let .combatantRemoved(id):
            state.removed.insert(id)
        case .moved, .noteAdded:
            // Recorded for the record, not for the state: where a Pawn stands is the
            // Map's own truth, and a note is something to read rather than something the
            // tracker shows a number for.
            break
        case .unrecognised:
            // Written by a later version. Skipped so the rest of the Log still reads.
            break
        }
    }
}
