import Foundation

/// The Encounter where it meets the rest of the app.
///
/// Kept apart from `AppState.swift` because combat changes for different reasons than
/// presentation does, and because everything here obeys one rule the rest of the app does
/// not: a number only moves by recording a `Change`. See
/// `docs/adr/0008-combat-is-an-append-only-turn-log.md`.
@MainActor
extension AppState {
    // MARK: Stat Blocks

    /// A Pawn's combat numbers, or the defaults if the DM has not filled them in.
    ///
    /// Never optional at the call site: a Creature stamped and not yet given hit points is
    /// AC 10 with none, which the tracker flags rather than refuses.
    func statBlock(for pawn: Pawn.ID) -> StatBlock {
        statsDocument.blocks[pawn] ?? StatBlock()
    }

    /// Writes a Pawn's numbers directly.
    ///
    /// For prep, before any fight: there is no Log open then, so there is nothing to
    /// record into. **Not** the path for changing a number mid-Encounter — that is
    /// `recordChange`, and the difference is the whole of ADR-0008.
    func setStatBlock(_ block: StatBlock, for pawn: Pawn.ID) {
        statsDocument.blocks[pawn] = block
        statsAutosave.schedule(statsDocument)
    }

    func loadStats(forMapAt url: URL) {
        statsDocument = statsStore.load(forMapAt: url) ?? StatsDocument()
        statsLoadFailure = statsStore.lastLoadFailure
    }

    func flushPendingStatWrites() {
        statsAutosave.flush()
    }

    // MARK: Running a fight

    /// Rolls Initiative for every Player and Creature on the Map and opens a Combat Log.
    ///
    /// Does nothing when there is nobody to fight: an empty tracker would be worse than
    /// no tracker.
    func startEncounter() {
        guard let mapURL, encounter == nil else { return }
        let entrants = fog.pawns
            .filter { $0.kind != .treasure }
            .map { EncounterControl.Entrant(id: $0.id, name: $0.label, kind: $0.kind,
                                            block: statBlock(for: $0.id)) }
        guard !entrants.isEmpty else { return }

        var generator = SystemRandomNumberGenerator()
        let started = EncounterControl.start(entrants, using: &generator)
        openLog(forMapAt: mapURL)
        encounter = started.encounter
        write(started.lines)
    }

    /// Ends the Turn in progress, or walks the correction cursor back towards live play.
    func endTurn() {
        guard var live = encounter else { return }
        write(EncounterControl.next(&live))
        encounter = live
    }

    /// Walks the correction cursor back one ended Turn.
    func stepBackForCorrection() {
        guard var live = encounter else { return }
        EncounterControl.previous(&live)
        encounter = live
    }

    /// Records one Change into the Turn in progress, or against the Turn the correction
    /// cursor is on.
    ///
    /// The only way a combat number moves. Anything that writes a `StatBlock` directly
    /// during a fight is a number the Log does not know about, which is the bug ADR-0008
    /// exists to make structurally impossible.
    func recordChange(_ change: Change) {
        guard var live = encounter else { return }
        write(EncounterControl.record(change, in: &live))
        encounter = live
        // The Stat Blocks on disk follow the fold, so a fight's damage survives the
        // Encounter that did it — stopping is not a rest.
        syncStatsFromEncounter(live)
    }

    func reorderCombatant(from source: Int, to destination: Int) {
        guard var live = encounter else { return }
        write(EncounterControl.reorder(from: source, to: destination, in: &live))
        encounter = live
    }

    /// Re-rolls every Initiative. The Round is untouched — it is a fact about history.
    func rerollInitiative() {
        guard var live = encounter else { return }
        var generator = SystemRandomNumberGenerator()
        write(EncounterControl.rerollInitiative(in: &live, using: &generator))
        encounter = live
    }

    /// Adds a Combatant to a fight already running — a summon, or a Character Stamped
    /// mid-Encounter.
    func joinEncounter(_ pawn: Pawn) {
        guard var live = encounter, pawn.kind != .treasure else { return }
        var generator = SystemRandomNumberGenerator()
        let entrant = EncounterControl.Entrant(id: pawn.id, name: pawn.label,
                                               kind: pawn.kind,
                                               block: statBlock(for: pawn.id))
        write(EncounterControl.join(entrant, in: &live, using: &generator))
        encounter = live
    }

    /// Takes a Combatant out of the rotation. It stays listed: the Log already names it.
    func removeFromEncounter(_ pawn: Pawn.ID) {
        guard var live = encounter else { return }
        write(EncounterControl.remove(pawn, in: &live))
        encounter = live
    }

    /// Ends the fight. Nobody is healed and no Condition is cleared — a fight ending is
    /// not a rest.
    func stopEncounter() {
        guard var live = encounter else { return }
        write(EncounterControl.stop(&live, at: Date()))
        syncStatsFromEncounter(live)
        flushPendingStatWrites()
        encounter = nil
        closeLog()
    }

    /// Brings back a fight that was running when the Map was last closed.
    ///
    /// Falls out of the format for free: the newest Log with no `encounterEnded` line is a
    /// fight still going, and folding it gives the Round, the Order and every hit point.
    /// A DM closing a laptop mid-fight is taking a break, and inventing an end line for
    /// them would put a lie in the Log.
    func resumeEncounter(forMapAt url: URL) {
        encounter = nil
        let reader = CombatLogReader()
        guard let newest = reader.newestLogURL(forMapAt: url),
              let lines = try? reader.read(at: newest),
              !lines.isEmpty,
              !CombatLogFold.fold(lines).hasEnded else { return }

        encounter = Encounter(resuming: lines)
        logWriter = try? CombatLogWriter(reopening: newest)
    }

    // MARK: Writing

    private func openLog(forMapAt url: URL) {
        logWriter = try? CombatLogWriter(forMapAt: url, startedAt: Date())
    }

    private func closeLog() {
        try? logWriter?.close()
        logWriter = nil
    }

    /// Appends to the Combat Log immediately. Never debounced: a Turn ending is the
    /// durability boundary the whole format rests on.
    private func write(_ lines: [LogLine]) {
        guard !lines.isEmpty, let logWriter else { return }
        for line in lines { try? logWriter.append(line) }
    }

    /// Copies the folded Stat Blocks onto the ones that live beside the Map.
    ///
    /// The Log stays authoritative during a fight; this is what makes its result outlive
    /// the fight, so next week's Encounter starts where this one left off.
    private func syncStatsFromEncounter(_ live: Encounter) {
        for (id, block) in live.blocks where statsDocument.blocks[id] != block {
            statsDocument.blocks[id] = block
        }
        statsAutosave.schedule(statsDocument)
    }
}
