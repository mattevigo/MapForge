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

    /// Edits a Pawn's numbers, whichever way is correct right now.
    ///
    /// The panel's single door, so no view has to know the rule: during an Encounter each
    /// field that actually moved becomes a `Change` in the Turn — or a Correction, if the
    /// cursor is on a past one — and outside a fight the block is written straight to
    /// `stats.json`, because there is no Log to record into.
    ///
    /// Takes a mutating closure rather than a finished block, so the diff is computed here
    /// and a caller cannot hand over a block built from stale values.
    func editStatBlock(for pawn: Pawn.ID, _ edit: (inout StatBlock) -> Void) {
        let before = encounter?.blocks[pawn] ?? statBlock(for: pawn)
        var after = before
        edit(&after)
        guard after != before else { return }

        // Straight to `stats.json` outside a fight — and for a bystander during one. A Pawn
        // the Encounter holds no block for is not in it: recording its numbers into the Log
        // would have the fold invent a fresh block for it, which `syncStatsFromEncounter`
        // then writes over the real one, rostering it and stripping its Conditions.
        guard let encounter, encounter.blocks[pawn] != nil else {
            setStatBlock(after, for: pawn)
            return
        }
        for change in Self.changes(for: pawn, from: before, to: after) {
            recordChange(change)
        }
    }

    /// Overtypes a Combatant's Initiative — what a DM does as the players call theirs out.
    ///
    /// Does **not** re-sort the Order: ties are the DM's to break, so a number and a
    /// position are allowed to disagree until they drag the row.
    func setInitiative(_ initiative: Int, for pawn: Pawn.ID) {
        guard let current = encounter?.initiative(of: pawn), current != initiative else { return }
        recordChange(.initiativeChanged(combatantID: pawn, from: current, to: initiative))
    }

    /// Records a quick note against the Combatant whose Turn it is.
    ///
    /// About the *active* Combatant, not the selected one — the panel labels the box with
    /// that name so there is no ambiguity. While correcting it lands on the Turn under the
    /// cursor, which is how a note reaches a Turn that has already ended.
    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encounter else { return }
        let subject = encounter.correctionTarget?.combatantID ?? encounter.activeCombatantID
        guard let subject else { return }
        recordChange(.noteAdded(combatantID: subject, text: trimmed))
    }

    /// One `Change` per field that actually moved.
    ///
    /// Field by field rather than a single "the block changed" event, because the Log is
    /// meant to be read: "poisoned, then 14 to 9" is what happened, and a block-shaped
    /// diff would say only that something did.
    static func changes(for pawn: Pawn.ID,
                        from before: StatBlock,
                        to after: StatBlock) -> [Change] {
        var changes: [Change] = []
        if before.currentHP != after.currentHP {
            changes.append(.hpChanged(combatantID: pawn, from: before.currentHP, to: after.currentHP))
        }
        if before.maxHP != after.maxHP {
            changes.append(.maxHPChanged(combatantID: pawn, from: before.maxHP, to: after.maxHP))
        }
        if before.temporaryHP != after.temporaryHP {
            changes.append(.tempHPChanged(combatantID: pawn,
                                          from: before.temporaryHP, to: after.temporaryHP))
        }
        if before.armorClass != after.armorClass {
            changes.append(.acChanged(combatantID: pawn,
                                      from: before.armorClass, to: after.armorClass))
        }
        if before.initiativeBonus != after.initiativeBonus {
            changes.append(.initiativeBonusChanged(combatantID: pawn,
                                                   from: before.initiativeBonus,
                                                   to: after.initiativeBonus))
        }
        if before.exhaustion != after.exhaustion {
            changes.append(.exhaustionChanged(combatantID: pawn,
                                              from: before.exhaustion, to: after.exhaustion))
        }
        if before.isConcentrating != after.isConcentrating {
            changes.append(.concentrationChanged(combatantID: pawn,
                                                 isConcentrating: after.isConcentrating))
        }
        // Sorted so a Log reads the same way twice: a Set has no order, and two runs of the
        // same edit would otherwise write their Conditions in whatever order hashing gave.
        for condition in after.conditions.subtracting(before.conditions).sorted(by: { $0.rawValue < $1.rawValue }) {
            changes.append(.conditionAdded(combatantID: pawn, condition: condition))
        }
        for condition in before.conditions.subtracting(after.conditions).sorted(by: { $0.rawValue < $1.rawValue }) {
            changes.append(.conditionRemoved(combatantID: pawn, condition: condition))
        }
        return changes
    }

    func loadStats(forMapAt url: URL) {
        statsDocument = statsStore.load(forMapAt: url) ?? StatsDocument()
        statsLoadFailure = statsStore.lastLoadFailure
    }

    func flushPendingStatWrites() {
        statsAutosave.flush()
    }

    // MARK: Running a fight

    // MARK: The roster

    /// Whether a Pawn rolls when the next fight starts. See `StatBlock.isInCombat`.
    func isInCombat(_ pawn: Pawn.ID) -> Bool {
        statBlock(for: pawn).isInCombat
    }

    /// Puts a Pawn in or out of the next fight.
    ///
    /// Straight to `stats.json`, never through the Log: a roster is prep, decided before a
    /// fight rather than during one, and there is nothing open to record it into.
    func setInCombat(_ isInCombat: Bool, for pawn: Pawn.ID) {
        var block = statBlock(for: pawn)
        guard block.isInCombat != isInCombat else { return }
        block.isInCombat = isInCombat
        setStatBlock(block, for: pawn)
    }

    /// Pawns on the Map that are not taking Turns: left off the roster, Benched during the
    /// fight, or Treasure. What the tracker lists under the Order.
    var notInCombat: Set<Pawn.ID> {
        let onMap = Set(fog.pawns.map(\.id))
        guard let encounter else {
            return Set(fog.pawns.filter { !isInCombat($0.id) || $0.kind == .treasure }.map(\.id))
        }
        return encounter.benched.union(onMap.subtracting(Set(encounter.order)))
    }

    /// Why a fight cannot start right now, in words for the DM — or nil when it can.
    ///
    /// Said rather than only enforced: a Play button that is merely grey leaves a DM
    /// wondering what they forgot, five minutes before the players arrive.
    var encounterRefusal: String? {
        session == nil ? "Start a Session first — a fight is part of an evening." : nil
    }

    /// Rolls Initiative for every rostered Player and Creature on the Map and opens a
    /// Combat Log.
    ///
    /// Does nothing when there is nobody to fight: an empty tracker would be worse than
    /// no tracker. A Pawn left off the roster is not refused so much as not asked — it
    /// stays on the Map, is listed as not in combat, and the same button that returns a
    /// Benched Pawn will bring it in.
    ///
    /// Refused before the evening has started: an Encounter is one fight *of* a Session
    /// (`CONTEXT.md`), and one started without would leave a Combat Log no Session Log
    /// points at — a fight the Log View could never show. About starting only: a fight
    /// resumed from its Log, or one whose Session the DM stopped mid-fight, carries on.
    func startEncounter() {
        guard let mapURL, encounter == nil, encounterRefusal == nil else { return }
        let entrants = fog.pawns
            .filter { $0.kind != .treasure && isInCombat($0.id) }
            .map { EncounterControl.Entrant(id: $0.id, name: $0.label, kind: $0.kind,
                                            block: statBlock(for: $0.id)) }
        guard !entrants.isEmpty else { return }

        var generator = SystemRandomNumberGenerator()
        let started = EncounterControl.start(entrants, using: &generator)
        openLog(forMapAt: mapURL)
        encounter = started.encounter
        write(started.lines)
        // After the Log is open, so the Session's pointer names a file that exists.
        if let logFile = logWriter?.url.lastPathComponent {
            noteEncounterStarted(logFile: logFile)
        }
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

    // MARK: The Map

    /// Records a completed drag.
    ///
    /// Called from the end of the gesture, never from its updates: one Change per drag, not
    /// one per frame. The DM's hand-wobble on the way is not domain data — the decision is
    /// where they let go, and three drags in a Turn is the honest record of "moved,
    /// attacked, moved back".
    ///
    /// The Pawn has already moved by the time this is called, and moves whether or not it
    /// is recorded: outside a fight, and while the correction cursor is on a past Turn,
    /// nothing is written. Where a Pawn stands is the Map's own truth.
    /// Two independent records, and never both: the Combat Log takes the drag while a fight
    /// runs, and the Session Log takes it the rest of the evening. Which one writes is not
    /// decided here — `SessionControl` drops the line while an Encounter is running, so this
    /// call site needs no `if` about fights. See ADR-0014.
    func commitPawnMove(id: Pawn.ID, from origin: MapPoint) {
        flushPendingFogWrites()
        guard let pawn = fog.pawns.first(where: { $0.id == id }),
              pawn.at != origin else { return }
        let distance = distanceInSquares(from: origin, to: pawn.at)
        if encounter != nil {
            recordChange(.moved(combatantID: id,
                                from: origin,
                                to: pawn.at,
                                distanceSquares: distance))
        }
        recordSessionMove(pawn: pawn, from: origin, distanceSquares: distance)
    }

    // MARK: Rolls

    /// Records a d20 the DM took at the table.
    ///
    /// Two independent records, and never both, exactly as `commitPawnMove` is: the Combat
    /// Log takes the Roll while a fight runs and the Session Log takes it the rest of the
    /// evening. Which one writes is not decided here — `SessionControl` drops the line while
    /// an Encounter is running, so this call site needs no `if` about fights. See ADR-0014.
    ///
    /// The Pawn need not be a Combatant: a save against the dragon's breath is made by
    /// whoever the breath reached, and the NPC in the corner rolls without ever joining the
    /// Order. A Roll is about the Pawn, not about whose Turn it is.
    ///
    /// Nothing here touches a Stat Block. A Roll changes nothing — what a failed save
    /// implies is the DM's to apply. See
    /// `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
    func recordRoll(pawn: Pawn, ability: Ability, roll: Roll) {
        if encounter != nil {
            recordChange(.savingThrow(combatantID: pawn.id, name: pawn.label,
                                      ability: ability, roll: roll))
        }
        recordSessionRoll(pawn: pawn, ability: ability, roll: roll)
    }

    func recordRoll(pawn: Pawn, skill: Skill, roll: Roll) {
        if encounter != nil {
            recordChange(.abilityCheck(combatantID: pawn.id, name: pawn.label,
                                       skill: skill, roll: roll))
        }
        recordSessionRoll(pawn: pawn, skill: skill, roll: roll)
    }

    /// Straight-line distance in Grid squares — the unit distances are *stored* in, as
    /// `Measurement` does. Metres are what `DistanceUnit` turns it into for display.
    private func distanceInSquares(from: MapPoint, to: MapPoint) -> CGFloat {
        guard let map = mapScale, map.imagePixelSize.width > 0, squaresWide > 0 else { return 0 }
        let pixelsPerSquare = map.imagePixelSize.width / CGFloat(squaresWide)
        guard pixelsPerSquare > 0 else { return 0 }
        return hypot(to.x - from.x, to.y - from.y) / pixelsPerSquare
    }

    /// Puts a Pawn on the Map, and into the fight if one is running.
    ///
    /// A summon, or a Character Stamped mid-Encounter, joins at its rolled Initiative with
    /// no prompt — it is what a DM wants almost every time, and removing it from the
    /// tracker is one click if not.
    ///
    /// A Creature that arrives already a Monster — `AddPlacement` giving the second gnoll
    /// the first one's — is stamped here, afresh and at full hit points, and **before** it
    /// joins: joining rolls Initiative from the Stat Block's bonus and snapshots the block
    /// into the Log. Never over numbers that already exist, which is what keeps a Stamped
    /// Character's block its own.
    func addPawnToMap(_ pawn: Pawn) {
        if statsDocument.blocks[pawn.id] == nil,
           let monster = bestiary.monster(named: pawn.monsterName) {
            setStatBlock(MonsterStamp.statBlock(from: monster, over: StatBlock()), for: pawn.id)
        }
        fog.pawns.append(pawn)
        flushPendingFogWrites()
        joinEncounter(pawn)
    }

    /// Takes a Pawn off the Map, and onto the bench if a fight is running.
    ///
    /// Benched rather than forgotten: the Log already names it, and its Stat Block outlives
    /// the token so the record has something to describe. A Pawn deleted from the Map
    /// cannot be un-benched, having nowhere to stand — the bench keeps it visible in the
    /// tracker for the rest of the fight, which is what a DM wants of a monster that died.
    func removePawnFromMap(_ id: Pawn.ID) {
        benchCombatant(id)
        fog.pawns.removeAll { $0.id == id }
        flushPendingFogWrites()
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

    /// Takes a Combatant out of the Order and onto the bench.
    func benchCombatant(_ pawn: Pawn.ID) {
        guard var live = encounter else { return }
        write(EncounterControl.bench(pawn, in: &live))
        encounter = live
    }

    /// Puts a Benched Pawn into the Order, rolling Initiative afresh.
    ///
    /// Also the way in for a Pawn that was never a Combatant — one placed since the fight
    /// began, or one the DM has only just decided is part of it. Both are joins; the
    /// difference is only whether the Log has met it before.
    func unbenchCombatant(_ pawn: Pawn.ID) {
        guard var live = encounter else { return }
        var generator = SystemRandomNumberGenerator()
        if live.benched.contains(pawn) {
            write(EncounterControl.unbench(pawn, in: &live, using: &generator))
        } else if let onMap = fog.pawns.first(where: { $0.id == pawn }) {
            let entrant = EncounterControl.Entrant(id: onMap.id, name: onMap.label,
                                                   kind: onMap.kind,
                                                   block: statBlock(for: onMap.id))
            write(EncounterControl.join(entrant, in: &live, using: &generator))
        }
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
        // Before the Log is closed: the Session reads the Map's name while it is still open.
        noteEncounterEnded()
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
