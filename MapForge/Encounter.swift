import Foundation

/// The live fight: who is in it, whose Turn it is, and what has happened this Turn but is
/// not yet on disk.
///
/// A value type, mutated through `EncounterControl` so that every change also produces the
/// `LogLine`s that record it. Nothing here writes a file — `AppState` does that with what
/// the control functions hand back.
struct Encounter: Equatable {
    /// The sequence Combatants take Turns in. Settled at the start by sorting on
    /// Initiative and from then on the DM's to rearrange: ties are broken by the person
    /// running the table, not by a rule.
    var order: [UUID] = []
    var round = 1
    /// Whose Turn it is, as an index into `order`.
    var activeIndex = 0
    /// Listed but taking no Turns.
    var removed: Set<UUID> = []

    var blocks: [UUID: StatBlock] = [:]
    var names: [UUID: String] = [:]
    var kinds: [UUID: PawnKind] = [:]
    var initiatives: [UUID: Int] = [:]

    /// This Turn's Changes, not yet written. ADR-0008's write-behind buffer: durability
    /// lags reality by at most one Turn, which is what "saved at the end of the turn"
    /// already meant.
    var pendingChanges: [Change] = []

    /// How many ended Turns back the correction cursor is, or nil when live.
    /// See `docs/adr/0010-corrections-are-appended-never-edited.md`.
    var correctionCursor: Int?

    /// Every Turn that has ended, oldest first — what the correction cursor walks.
    var endedTurns: [TurnRef] = []

    /// One Turn, named by the Round it happened in and who took it. A Combatant acts at
    /// most once per Round, so the pair identifies a Turn.
    struct TurnRef: Equatable {
        var round: Int
        var combatantID: UUID
    }

    var activeCombatantID: UUID? {
        guard order.indices.contains(activeIndex) else { return nil }
        return order[activeIndex]
    }

    /// The Turn the correction cursor is on, or nil when live.
    var correctionTarget: TurnRef? {
        guard let correctionCursor,
              endedTurns.indices.contains(endedTurns.count - 1 - correctionCursor) else {
            return nil
        }
        return endedTurns[endedTurns.count - 1 - correctionCursor]
    }

    var isCorrecting: Bool { correctionTarget != nil }
}

/// The rules of running a fight.
///
/// Every operation returns the `LogLine`s it produced, so a caller cannot change an
/// Encounter without also getting the record of it. That is ADR-0008's consequence made
/// structural: a field the UI writes directly is a field the Log does not know about.
enum EncounterControl {
    /// A Pawn about to become a Combatant.
    struct Entrant: Equatable {
        var id: UUID
        var name: String
        var kind: PawnKind
        var block: StatBlock
    }

    /// Rolls for everyone, settles the Order, and opens the Log.
    ///
    /// Treasure is filtered out: it has nothing to do on its turn. Players are rolled for
    /// alongside Creatures, because overtyping a number the players call out is faster
    /// than typing into an empty field.
    static func start<G: RandomNumberGenerator>(
        _ entrants: [Entrant],
        at date: Date = Date(),
        using generator: inout G
    ) -> (encounter: Encounter, lines: [LogLine]) {
        var encounter = Encounter()
        var combatants: [Combatant] = []

        for entrant in entrants where entrant.kind != .treasure {
            let initiative = InitiativeRoll.roll(bonus: entrant.block.initiativeBonus,
                                                 using: &generator)
            encounter.blocks[entrant.id] = entrant.block
            encounter.names[entrant.id] = entrant.name
            encounter.kinds[entrant.id] = entrant.kind
            encounter.initiatives[entrant.id] = initiative
            combatants.append(Combatant(id: entrant.id, name: entrant.name,
                                        kind: entrant.kind, initiative: initiative,
                                        block: entrant.block))
        }

        // Sorted once, here, and recorded. Ties keep whatever order this produces and the
        // DM rearranges by hand — ADR-0008 needs the Order to be data, because two
        // Combatants on 14 cannot be re-sorted reproducibly.
        encounter.order = combatants
            .sorted { $0.initiative > $1.initiative }
            .map(\.id)

        return (encounter, [.encounterStarted(startedAt: date,
                                              order: encounter.order,
                                              combatants: combatants)])
    }

    /// Ends the current Turn and advances, or returns to live play when the correction
    /// cursor is away from it.
    ///
    /// The same button, two meanings — ADR-0010. Ending a Turn while correcting is
    /// refused rather than reinterpreted: the DM returns to live first.
    @discardableResult
    static func next(_ encounter: inout Encounter, at date: Date = Date()) -> [LogLine] {
        if encounter.correctionCursor != nil {
            advanceCursorTowardsLive(&encounter)
            return []
        }
        guard let active = encounter.activeCombatantID else { return [] }

        let line = LogLine.turn(round: encounter.round,
                                combatantID: active,
                                changes: encounter.pendingChanges,
                                endedAt: date)
        encounter.endedTurns.append(.init(round: encounter.round, combatantID: active))
        encounter.pendingChanges = []
        advanceActiveIndex(&encounter)
        return [line]
    }

    /// Walks the correction cursor back one ended Turn.
    static func previous(_ encounter: inout Encounter) {
        guard !encounter.endedTurns.isEmpty else { return }
        let next = (encounter.correctionCursor ?? -1) + 1
        encounter.correctionCursor = min(next, encounter.endedTurns.count - 1)
    }

    /// Records a Change: buffered into the current Turn when live, or written immediately
    /// as a Correction when the cursor is on a past Turn.
    ///
    /// Movement is refused while correcting — where a Pawn stands is the Map's truth and
    /// cannot retroactively be elsewhere.
    @discardableResult
    static func record(_ change: Change,
                       in encounter: inout Encounter,
                       at date: Date = Date()) -> [LogLine] {
        if let target = encounter.correctionTarget {
            if case .moved = change { return [] }
            var changes = [change]
            changes.append(contentsOf: consequences(of: change, in: &encounter))
            for change in changes { applyToState(change, in: &encounter) }
            return [.correction(targetRound: target.round,
                                targetCombatantID: target.combatantID,
                                changes: changes,
                                recordedAt: date)]
        }

        encounter.pendingChanges.append(change)
        applyToState(change, in: &encounter)
        for consequence in consequences(of: change, in: &encounter) {
            encounter.pendingChanges.append(consequence)
            applyToState(consequence, in: &encounter)
        }
        return []
    }

    /// Adds a Combatant mid-fight — a summon, or a Character stamped while the fight runs.
    @discardableResult
    static func join<G: RandomNumberGenerator>(_ entrant: Entrant,
                                               in encounter: inout Encounter,
                                               using generator: inout G) -> [LogLine] {
        guard entrant.kind != .treasure else { return [] }
        let initiative = InitiativeRoll.roll(bonus: entrant.block.initiativeBonus,
                                             using: &generator)
        encounter.blocks[entrant.id] = entrant.block
        encounter.names[entrant.id] = entrant.name
        encounter.kinds[entrant.id] = entrant.kind
        encounter.initiatives[entrant.id] = initiative

        // Never before the active index: a summon that rolled above the Combatant whose
        // Turn is already running would otherwise act twice in its first Round.
        let earliest = encounter.activeIndex + 1
        var insertion = earliest
        while insertion < encounter.order.count,
              (encounter.initiatives[encounter.order[insertion]] ?? Int.min) > initiative {
            insertion += 1
        }
        encounter.order.insert(entrant.id, at: insertion)

        let joined = Change.combatantJoined(combatantID: entrant.id, name: entrant.name,
                                            kind: entrant.kind, initiative: initiative,
                                            block: entrant.block)
        encounter.pendingChanges.append(joined)
        encounter.pendingChanges.append(.orderChanged(order: encounter.order))
        return []
    }

    /// Takes a Combatant out of the rotation. It stays in the Order: the Log already names
    /// it, and a monster that died in Round 2 is part of what happened.
    @discardableResult
    static func remove(_ combatantID: UUID, in encounter: inout Encounter) -> [LogLine] {
        guard encounter.order.contains(combatantID) else { return [] }
        encounter.removed.insert(combatantID)
        encounter.pendingChanges.append(.combatantRemoved(combatantID: combatantID))
        return []
    }

    /// Moves a Combatant in the Order and records the whole new sequence.
    @discardableResult
    static func reorder(from source: Int, to destination: Int,
                        in encounter: inout Encounter) -> [LogLine] {
        guard encounter.order.indices.contains(source),
              (0...encounter.order.count).contains(destination) else { return [] }
        let active = encounter.activeCombatantID
        let moved = encounter.order.remove(at: source)
        encounter.order.insert(moved, at: destination > source ? destination - 1 : destination)
        // The Turn in progress belongs to whoever was taking it, wherever they now sit.
        if let active, let index = encounter.order.firstIndex(of: active) {
            encounter.activeIndex = index
        }
        encounter.pendingChanges.append(.orderChanged(order: encounter.order))
        return []
    }

    /// Re-rolls every Initiative and re-sorts.
    ///
    /// The Round is untouched: it is a fact about history, and resetting it would make the
    /// Log lie. The confirmation this deserves belongs to the UI; by here it has happened.
    @discardableResult
    static func rerollInitiative<G: RandomNumberGenerator>(
        in encounter: inout Encounter,
        using generator: inout G
    ) -> [LogLine] {
        let active = encounter.activeCombatantID
        for id in encounter.order {
            let bonus = encounter.blocks[id]?.initiativeBonus ?? 0
            let previous = encounter.initiatives[id] ?? 0
            let rolled = InitiativeRoll.roll(bonus: bonus, using: &generator)
            encounter.initiatives[id] = rolled
            encounter.pendingChanges.append(
                .initiativeChanged(combatantID: id, from: previous, to: rolled))
        }
        encounter.order.sort {
            (encounter.initiatives[$0] ?? 0) > (encounter.initiatives[$1] ?? 0)
        }
        if let active, let index = encounter.order.firstIndex(of: active) {
            encounter.activeIndex = index
        }
        encounter.pendingChanges.append(.orderChanged(order: encounter.order))
        return []
    }

    /// Flushes the Turn in progress and closes the Log.
    static func stop(_ encounter: inout Encounter, at date: Date = Date()) -> [LogLine] {
        encounter.correctionCursor = nil
        var lines = next(&encounter, at: date)
        lines.append(.encounterEnded(endedAt: date))
        return lines
    }

    // MARK: - Rules that fire on their own

    /// What a Change drags along with it.
    ///
    /// Only one rule so far: at 0 hit points a Combatant falls Unconscious and stops
    /// concentrating. Unconditional in the rules for Players and Creatures alike, and the
    /// thing a DM most reliably forgets. Here rather than in the editor so it holds
    /// whichever code path changed the number.
    private static func consequences(of change: Change,
                                     in encounter: inout Encounter) -> [Change] {
        guard case let .hpChanged(id, _, to) = change, let to, to <= 0 else { return [] }
        var consequences: [Change] = []
        let block = encounter.blocks[id] ?? StatBlock()
        if !block.conditions.contains(.unconscious) {
            consequences.append(.conditionAdded(combatantID: id, condition: .unconscious))
        }
        if block.isConcentrating {
            consequences.append(.concentrationChanged(combatantID: id, isConcentrating: false))
        }
        return consequences
    }

    // MARK: - Keeping the live state in step with the Log

    /// Applies a Change to the Encounter's own copy of the state.
    ///
    /// Deliberately the same rules as `CombatLogFold.apply`, so that folding a Log gives
    /// what the tracker was showing — the invariant
    /// `testAWholeFightFoldsBackToWhatTheTrackerShows` holds down.
    private static func applyToState(_ change: Change, in encounter: inout Encounter) {
        switch change {
        case let .hpChanged(id, _, to):
            encounter.blocks[id, default: StatBlock()].currentHP = to
        case let .tempHPChanged(id, _, to):
            encounter.blocks[id, default: StatBlock()].temporaryHP = to
        case let .maxHPChanged(id, _, to):
            encounter.blocks[id, default: StatBlock()].maxHP = to
        case let .acChanged(id, _, to):
            encounter.blocks[id, default: StatBlock()].armorClass = to
        case let .conditionAdded(id, condition):
            encounter.blocks[id, default: StatBlock()].conditions.insert(condition)
        case let .conditionRemoved(id, condition):
            encounter.blocks[id, default: StatBlock()].conditions.remove(condition)
        case let .exhaustionChanged(id, _, to):
            encounter.blocks[id, default: StatBlock()].exhaustion = to
        case let .concentrationChanged(id, isConcentrating):
            encounter.blocks[id, default: StatBlock()].isConcentrating = isConcentrating
        case let .initiativeChanged(id, _, to):
            encounter.initiatives[id] = to
        case let .orderChanged(order):
            encounter.order = order
        case let .combatantRemoved(id):
            encounter.removed.insert(id)
        case .combatantJoined, .moved, .noteAdded, .unrecognised:
            break
        }
    }

    private static func advanceActiveIndex(_ encounter: inout Encounter) {
        guard !encounter.order.isEmpty else { return }
        // Every Combatant may have been removed; stop rather than spin.
        for _ in 0..<encounter.order.count {
            encounter.activeIndex += 1
            if encounter.activeIndex >= encounter.order.count {
                encounter.activeIndex = 0
                encounter.round += 1
            }
            if !encounter.removed.contains(encounter.order[encounter.activeIndex]) { return }
        }
    }

    private static func advanceCursorTowardsLive(_ encounter: inout Encounter) {
        guard let cursor = encounter.correctionCursor else { return }
        encounter.correctionCursor = cursor == 0 ? nil : cursor - 1
    }
}
