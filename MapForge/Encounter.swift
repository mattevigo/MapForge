import Foundation

/// The live fight: who is in it, whose Turn it is, and what has happened this Turn but is
/// not yet on disk.
///
/// A value type, mutated through `EncounterControl` so that every change also produces the
/// `LogLine`s that record it. Nothing here writes a file — `AppState` does that with what
/// the control functions hand back.
struct Encounter: Equatable {
    /// Every line already written to the Combat Log, oldest first.
    ///
    /// Together with `pendingChanges` this is the **only** state: hit points, the Order,
    /// Conditions and the Round are all derived from it by `CombatLogFold`, never stored
    /// alongside it. ADR-0008 rejects a live model kept in step with a record, because
    /// "a state model and a record of how that state was reached are two things that must
    /// agree forever, with nothing forcing them to" — and a test that detects drift is not
    /// the same as a structure that cannot drift.
    private(set) var lines: [LogLine] = []

    /// This Turn's Changes, not yet written. ADR-0008's write-behind buffer: durability
    /// lags reality by at most one Turn, which is what "saved at the end of the turn"
    /// already meant. Folded along with `lines`, so the tracker shows them immediately.
    private(set) var pendingChanges: [Change] = []

    /// The Turn the correction cursor is on, or nil when live. A `TurnRef` rather than a
    /// count of Turns back, so nothing has to do arithmetic against `endedTurns.count`.
    /// See `docs/adr/0010-corrections-are-appended-never-edited.md`.
    private(set) var correctionTarget: TurnRef?

    /// One Turn, named by the Round it happened in and who took it. A Combatant acts at
    /// most once per Round, so the pair identifies a Turn.
    struct TurnRef: Equatable {
        var round: Int
        var combatantID: UUID
    }

    /// The fight as its Log describes it, including the Turn in progress.
    ///
    /// Computed on demand rather than cached: correctness first, and a fold over one
    /// session's Turns is a few hundred small operations. If profiling ever says
    /// otherwise, cache the fold of `lines` and re-fold only `pendingChanges` onto it —
    /// the shape that stays honest, unlike a second mutable copy.
    var state: EncounterState {
        CombatLogFold.fold(lines, pending: pendingChanges)
    }

    var order: [UUID] { state.order }
    var round: Int { state.round }
    var blocks: [UUID: StatBlock] { state.blocks }
    var benched: Set<UUID> { state.benched }

    func initiative(of combatant: UUID) -> Int? { state.initiative(of: combatant) }
    func name(of combatant: UUID) -> String? { state.name(of: combatant) }
    func kind(of combatant: UUID) -> PawnKind? { state.kind(of: combatant) }

    var activeCombatantID: UUID? { state.activeCombatantID }

    /// Every Turn that has ended, oldest first — what the correction cursor walks.
    var endedTurns: [TurnRef] {
        lines.compactMap { line in
            guard case let .turn(round, combatantID, _, _) = line else { return nil }
            return TurnRef(round: round, combatantID: combatantID)
        }
    }

    var isCorrecting: Bool { correctionTarget != nil }

    init() {}

    /// Picks up a fight that was still running when its Map was last closed.
    ///
    /// Takes the Log and nothing else, because the Log is everything: the Round, the
    /// Order, whose Turn it is and every hit point all come back out of the fold. This is
    /// the payoff ADR-0008 was chosen for, and it is one line of work.
    init(resuming lines: [LogLine]) {
        self.lines = lines
    }

    fileprivate mutating func append(_ line: LogLine) { lines.append(line) }
    fileprivate mutating func buffer(_ change: Change) { pendingChanges.append(change) }
    fileprivate mutating func clearBuffer() { pendingChanges = [] }
    fileprivate mutating func setCorrectionTarget(_ target: TurnRef?) {
        correctionTarget = target
    }
}

/// The rules of running a fight.
///
/// Every operation returns the `LogLine`s it produced and changes the `Encounter` only by
/// recording a `Change`. That is ADR-0008's consequence made structural rather than
/// remembered: there is no way to move a number without the Log learning about it, because
/// the numbers are only ever read back out of the Log.
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
        let combatants = entrants
            .filter { $0.kind != .treasure }
            .map { entrant in
                Combatant(id: entrant.id, name: entrant.name, kind: entrant.kind,
                          initiative: InitiativeRoll.roll(bonus: entrant.block.initiativeBonus,
                                                          using: &generator),
                          block: entrant.block)
            }

        // Sorted once, here, and recorded. Ties keep whatever order this produces and the
        // DM rearranges by hand — ADR-0008 needs the Order to be data, because two
        // Combatants on 14 cannot be re-sorted reproducibly.
        let order = combatants.sorted { $0.initiative > $1.initiative }.map(\.id)

        var encounter = Encounter()
        let line = LogLine.encounterStarted(startedAt: date, order: order,
                                            combatants: combatants)
        encounter.append(line)
        return (encounter, [line])
    }

    /// Ends the current Turn and advances, or walks the correction cursor back towards
    /// live play when it is away from it.
    ///
    /// The same button, two meanings — ADR-0010. Ending a Turn while correcting is
    /// refused rather than reinterpreted: the DM returns to live first.
    @discardableResult
    static func next(_ encounter: inout Encounter, at date: Date = Date()) -> [LogLine] {
        if encounter.isCorrecting {
            moveCursorTowardsLive(&encounter)
            return []
        }
        guard let active = encounter.activeCombatantID else { return [] }

        let line = LogLine.turn(round: encounter.round,
                                combatantID: active,
                                changes: encounter.pendingChanges,
                                endedAt: date)
        encounter.append(line)
        encounter.clearBuffer()
        return [line]
    }

    /// Walks the correction cursor back one ended Turn.
    static func previous(_ encounter: inout Encounter) {
        let turns = encounter.endedTurns
        guard !turns.isEmpty else { return }
        guard let current = encounter.correctionTarget else {
            encounter.setCorrectionTarget(turns.last)
            return
        }
        guard let index = turns.lastIndex(of: current), index > 0 else { return }
        encounter.setCorrectionTarget(turns[index - 1])
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
        var changes = [change]
        changes.append(contentsOf: consequences(of: change, in: encounter))

        guard let target = encounter.correctionTarget else {
            for change in changes { encounter.buffer(change) }
            return []
        }

        // A movement cannot be corrected: where a Pawn stands is the Map's truth and cannot
        // retroactively have been elsewhere. A Roll cannot either, for the mirror reason —
        // it is a record of something that happened *now*, at the table, and filing it
        // against a Turn three Rounds ago would put it permanently in the wrong Round of an
        // append-only file.
        switch change {
        case .moved, .savingThrow, .abilityCheck: return []
        default: break
        }
        let line = LogLine.correction(targetRound: target.round,
                                      targetCombatantID: target.combatantID,
                                      changes: changes,
                                      recordedAt: date)
        encounter.append(line)
        return [line]
    }

    /// Adds a Combatant mid-fight — a summon, or a Character stamped while the fight runs.
    @discardableResult
    static func join<G: RandomNumberGenerator>(_ entrant: Entrant,
                                               in encounter: inout Encounter,
                                               using generator: inout G) -> [LogLine] {
        guard entrant.kind != .treasure else { return [] }
        let initiative = InitiativeRoll.roll(bonus: entrant.block.initiativeBonus,
                                             using: &generator)
        let state = encounter.state

        // Never before the active index: a Combatant that rolled above the one whose Turn
        // is already running would otherwise act twice in its first Round. Past that, it
        // sits where its Initiative earns — a summon is not sent to the back of the Order
        // for arriving.
        var insertion = state.activeIndex + 1
        while insertion < state.order.count,
              (state.initiative(of: state.order[insertion]) ?? Int.min) > initiative {
            insertion += 1
        }
        var order = state.order
        order.insert(entrant.id, at: min(insertion, order.count))

        return record([
            .combatantJoined(combatantID: entrant.id, name: entrant.name, kind: entrant.kind,
                             initiative: initiative, block: entrant.block),
            .orderChanged(order: order),
        ], in: &encounter)
    }

    /// Takes a Combatant out of the Order and onto the bench.
    ///
    /// Not a deletion: its name and numbers stay, so the Log can still describe it and the
    /// DM can still heal it before sending it back. See `CONTEXT.md`, **Benched**.
    @discardableResult
    static func bench(_ combatantID: UUID, in encounter: inout Encounter) -> [LogLine] {
        guard encounter.order.contains(combatantID) else { return [] }
        return record([.combatantRemoved(combatantID: combatantID)], in: &encounter)
    }

    /// Returns a Benched Pawn to the Order, rolling Initiative afresh.
    ///
    /// Exactly a join, and deliberately so: a Creature that has spent three Rounds off the
    /// Order has no claim on the number it rolled before, and the DM would have to correct
    /// a stale one by hand. Its hit points and Conditions come back untouched — the bench
    /// is not a rest.
    @discardableResult
    static func unbench<G: RandomNumberGenerator>(_ combatantID: UUID,
                                                  in encounter: inout Encounter,
                                                  using generator: inout G) -> [LogLine] {
        guard encounter.benched.contains(combatantID) else { return [] }
        let state = encounter.state
        let entrant = Entrant(id: combatantID,
                              name: state.name(of: combatantID) ?? "?",
                              kind: state.kind(of: combatantID) ?? .creature,
                              block: state.blocks[combatantID] ?? StatBlock())
        return join(entrant, in: &encounter, using: &generator)
    }

    /// Moves a Combatant in the Order and records the whole new sequence.
    @discardableResult
    static func reorder(from source: Int, to destination: Int,
                        in encounter: inout Encounter) -> [LogLine] {
        var order = encounter.order
        guard order.indices.contains(source),
              (0...order.count).contains(destination) else { return [] }
        let moved = order.remove(at: source)
        order.insert(moved, at: destination > source ? destination - 1 : destination)
        return record([.orderChanged(order: order)], in: &encounter)
    }

    /// Settles the Order by Initiative and records it — what Return does in the Initiative
    /// column once the players have called their numbers out.
    ///
    /// **Stable**: two Combatants on the same number keep the order they are already in, so
    /// a tie the DM has broken by dragging stays broken. Only a row whose number is out of
    /// place moves. Nothing is written when the Order is already settled — a Return over an
    /// unchanged column must not put an `orderChanged` in the Log.
    ///
    /// Recorded as the whole new Order, as `reorder` records a drag: ADR-0008 forbids the
    /// fold recomputing it, so the sort happens once, here, and goes to disk.
    @discardableResult
    static func sortByInitiative(in encounter: inout Encounter) -> [LogLine] {
        let state = encounter.state
        // An explicit index tiebreak rather than trusting `sort` to be stable: the Order is
        // data the Log replays, and "stable in practice" is not a guarantee it can rest on.
        let sorted = state.order.enumerated()
            .sorted { a, b in
                let ia = state.initiative(of: a.element) ?? Int.min
                let ib = state.initiative(of: b.element) ?? Int.min
                return ia != ib ? ia > ib : a.offset < b.offset
            }
            .map(\.element)
        guard sorted != state.order else { return [] }
        return record([.orderChanged(order: sorted)], in: &encounter)
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
        let state = encounter.state
        var changes: [Change] = []
        var rolled: [UUID: Int] = [:]

        for id in state.order {
            let bonus = state.blocks[id]?.initiativeBonus ?? 0
            let initiative = InitiativeRoll.roll(bonus: bonus, using: &generator)
            rolled[id] = initiative
            changes.append(.initiativeChanged(combatantID: id,
                                              from: state.initiative(of: id) ?? 0,
                                              to: initiative))
        }
        changes.append(.orderChanged(
            order: state.order.sorted { (rolled[$0] ?? 0) > (rolled[$1] ?? 0) }))
        return record(changes, in: &encounter)
    }

    /// Flushes the Turn in progress and closes the Log.
    ///
    /// Refused while correcting, as `next` is: stopping a fight from a past Turn would end
    /// it on a state the DM is not looking at.
    static func stop(_ encounter: inout Encounter, at date: Date = Date()) -> [LogLine] {
        guard !encounter.isCorrecting else { return [] }
        // Only flush a Turn that has something in it — a fight stopped the instant a Turn
        // began should not leave an empty Turn line behind.
        var lines = encounter.pendingChanges.isEmpty ? [] : next(&encounter, at: date)
        let ended = LogLine.encounterEnded(endedAt: date)
        encounter.append(ended)
        lines.append(ended)
        return lines
    }

    // MARK: - Recording

    /// Records several Changes as one step, so a join or a re-roll cannot half-happen.
    @discardableResult
    private static func record(_ changes: [Change],
                               in encounter: inout Encounter,
                               at date: Date = Date()) -> [LogLine] {
        var lines: [LogLine] = []
        for change in changes { lines += record(change, in: &encounter, at: date) }
        return lines
    }

    /// What a Change drags along with it.
    ///
    /// Only one rule so far: at 0 hit points a Combatant falls Unconscious and stops
    /// concentrating. Unconditional in the rules for Players and Creatures alike, and the
    /// thing a DM most reliably forgets. Here rather than in the editor so it holds
    /// whichever code path changes the number.
    private static func consequences(of change: Change, in encounter: Encounter) -> [Change] {
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

    private static func moveCursorTowardsLive(_ encounter: inout Encounter) {
        let turns = encounter.endedTurns
        guard let current = encounter.correctionTarget,
              let index = turns.lastIndex(of: current) else { return }
        // Past the last ended Turn is live play again, which is how Next doubles as
        // "return to live".
        encounter.setCorrectionTarget(index + 1 < turns.count ? turns[index + 1] : nil)
    }
}
