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
    /// On the Map but out of the Order — see `CONTEXT.md`, **Benched**.
    ///
    /// Held apart from `order` rather than as a flag within it, because a Benched Pawn is
    /// not in the Order at all: it takes no Turns, it is listed separately, and it returns
    /// by rolling afresh. Its name and numbers stay in `blocks` and `names`, so the Log can
    /// still describe a Creature that died three Rounds ago.
    var benched: Set<UUID> = []
    var hasEnded = false

    /// Whose Turn it is, as an index into `order`.
    ///
    /// Derived like everything else: the Turn *after* the last one written. A Log ending
    /// on the final Combatant of a Round resumes at the first Combatant of the next one,
    /// which is why the Round cannot simply be read off the last Turn line.
    var activeIndex = 0

    var activeCombatantID: UUID? {
        guard order.indices.contains(activeIndex) else { return nil }
        return order[activeIndex]
    }

    /// Names and kinds as the Log recorded them, so a Combatant can be described long
    /// after its Pawn is gone.
    fileprivate var names: [UUID: String] = [:]
    fileprivate var kinds: [UUID: PawnKind] = [:]
    fileprivate var initiatives: [UUID: Int] = [:]

    func name(of combatant: UUID) -> String? { names[combatant] }
    func kind(of combatant: UUID) -> PawnKind? { kinds[combatant] }
    func initiative(of combatant: UUID) -> Int? { initiatives[combatant] }

    /// The Combatants taking Turns, in Order. Benched Pawns are not among them — they are
    /// not in `order` at all.
    var active: [UUID] { order }
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
    /// - Parameter pending: the current Turn's Changes, not yet written to a line. Folded
    ///   after everything in `lines` so the tracker shows them the moment they happen,
    ///   without a second mutable copy of the state to keep in step. They do not advance
    ///   the Turn: the Turn they belong to has not ended.
    static func fold(_ lines: [LogLine], pending: [Change] = []) -> EncounterState {
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
                // what they recorded at the time. A *later* Turn touching the same field
                // still wins, because a Change's `to` is the number the DM saw and is
                // never reinterpreted as a delta.
                let key = TurnKey(round: round, combatantID: combatantID)
                for change in corrections[key] ?? [] { apply(change, to: &state) }
                // The fight is now waiting on whoever comes next, which may be in the
                // following Round. Reading the Round off the last Turn line instead would
                // resume a DM one Round behind the table.
                advance(&state, from: combatantID)

            case .correction:
                // Already applied above, at the Turn it targets. A Correction naming a
                // Turn that never happened is ignored rather than fatal: a hand-edited
                // file must not cost a DM the rest of the fight.
                continue

            case .encounterEnded:
                state.hasEnded = true
            }
        }
        for change in pending { apply(change, to: &state) }
        return state
    }

    private struct TurnKey: Hashable {
        var round: Int
        var combatantID: UUID
    }

    /// Moves to the Turn after `combatantID`'s, wrapping into the next Round.
    ///
    /// Takes the Combatant rather than trusting `activeIndex`, because the Order can have
    /// been rearranged — or the Combatant Benched out of it — during the very Turn that
    /// just ended.
    private static func advance(_ state: inout EncounterState, from combatantID: UUID) {
        guard !state.order.isEmpty else { return }
        guard let index = state.order.firstIndex(of: combatantID) else {
            // Benched during its own Turn: it is gone from the Order, so whoever now holds
            // its old position acts next. The index cannot be trusted to name them, but it
            // is where the fight continues from.
            state.activeIndex = min(state.activeIndex, state.order.count - 1)
            return
        }
        let next = index + 1
        if next >= state.order.count {
            state.activeIndex = 0
            state.round += 1
        } else {
            state.activeIndex = next
        }
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
        case let .initiativeBonusChanged(id, _, to):
            // The bonus only. The rolled Initiative is the Encounter's and does not move:
            // changing a bonus does not by itself move anyone.
            state.blocks[id, default: StatBlock()].initiativeBonus = to
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
            // Also how a Benched Pawn returns: it is a join, with the same rules and a
            // fresh roll. The snapshot carries whatever hit points it had, so returning
            // after three Rounds on the bench is not a reset.
            state.blocks[id] = block
            state.names[id] = name
            state.kinds[id] = kind
            state.initiatives[id] = initiative
            state.benched.remove(id)
            if !state.order.contains(id) { state.order.append(id) }
        case let .combatantRemoved(id):
            // The wire name is older than the concept: on disk this has always meant "out
            // of the Order", which is what Benched now names. Kept as written so Logs
            // already beside a DM's Maps still read.
            state.benched.insert(id)
            state.order.removeAll { $0 == id }
        case .moved, .noteAdded, .savingThrow, .abilityCheck:
            // Recorded for the record, not for the state: where a Pawn stands is the
            // Map's own truth, a note is something to read rather than something the
            // tracker shows a number for, and a Roll changes nothing at all — the app
            // records what the dice showed and never applies what it implies.
            break
        case .unrecognised:
            // Written by a later version. Skipped so the rest of the Log still reads.
            break
        }
    }
}
