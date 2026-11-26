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
    ///
    /// A Pawn that shares its Character's numbers (`sharedCharacter(of:)`) reads its current
    /// and temporary hit points and its exhaustion from the Character, and the rest from its
    /// own block (ADR-0037) — outside a fight. A Combatant's numbers are the Encounter's
    /// (ADR-0008), and its own block follows the fold, so it is read as it stands.
    func statBlock(for pawn: Pawn.ID) -> StatBlock {
        let own = statsDocument.blocks[pawn] ?? StatBlock()
        guard encounter?.blocks[pawn] == nil, let shared = sharedCharacter(of: pawn)
        else { return own }
        return shared.character.sharedNumbers(over: own, maxHP: shared.note.maxHP)
    }

    /// Writes a Pawn's numbers directly.
    ///
    /// For prep, before any fight: there is no Log open then, so there is nothing to
    /// record into. **Not** the path for changing a number mid-Encounter — that is
    /// `recordChange`, and the difference is the whole of ADR-0008.
    ///
    /// A Pawn that shares its Character's numbers writes them to the Character, so every
    /// other Pawn of it, on this Map and every other, shows them at once — and to its own
    /// block too, which is what it keeps if the Character is deleted (ADR-0037). What it moved
    /// of them is recorded in the Session Log, here, because this is the one door every such
    /// edit comes through; a Creature's or a no-note Player's edit is not.
    func setStatBlock(_ block: StatBlock, for pawn: Pawn.ID) {
        statsDocument.blocks[pawn] = block
        statsAutosave.schedule(statsDocument)
        guard encounter?.blocks[pawn] == nil, let shared = sharedCharacter(of: pawn) else { return }
        // What the Pawn showed until now: the Character's numbers, as they stand before the
        // share below moves them.
        let shown = shared.character.sharedNumbers(over: block, maxHP: shared.note.maxHP)
        share(block, with: shared.character, note: shared.note)
        if let moved = CharacterNumbersMoved(of: shared.character, from: shown, to: block),
           let onMap = fog.pawns.first(where: { $0.id == pawn }) {
            recordSessionCharacterChange(moved, through: onMap)
        }
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
    /// Does **not** re-sort the Order by itself: a DM Tabbing down the column types every
    /// number first, and a row that jumped on each Tab would take the next field with it.
    /// `sortOrderByInitiative` is the settling step, and Return is what calls it.
    func setInitiative(_ initiative: Int, for pawn: Pawn.ID) {
        guard let current = encounter?.initiative(of: pawn), current != initiative else { return }
        recordChange(.initiativeChanged(combatantID: pawn, from: current, to: initiative))
    }

    /// Settles the Order by Initiative, keeping ties as the DM left them. Records the new
    /// Order when it moved anyone and nothing when it did not.
    func sortOrderByInitiative() {
        guard var live = encounter else { return }
        write(EncounterControl.sortByInitiative(in: &live))
        encounter = live
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

    // MARK: The Health Bar

    /// A Pawn's Stat Block as it stands right now: the fight's copy while one runs, folded
    /// from the Log, and the one beside the Map otherwise — `keepingHealthBarSetting` either
    /// way. What a screen drawing a Health Bar reads.
    func liveStatBlock(for pawn: Pawn.ID) -> StatBlock {
        guard let folded = encounter?.blocks[pawn] else { return statBlock(for: pawn) }
        return keepingHealthBarSetting(folded, for: pawn)
    }

    /// A block folded from the Combat Log, with whether the table sees its Health Bar taken
    /// from beside the Map instead.
    ///
    /// The one place that owns this rule. The Log is authoritative over the numbers during a
    /// fight (ADR-0008) but not over this setting: changing it is not a Change (ADR-0036), so
    /// the Log holds only what it was when the Pawn joined, and a bar the DM withheld
    /// mid-fight would come back the moment anything trusted the fight's copy of it.
    private func keepingHealthBarSetting(_ folded: StatBlock, for pawn: Pawn.ID) -> StatBlock {
        var block = folded
        block.showsHealthBarToPlayers = statBlock(for: pawn).showsHealthBarToPlayers
        return block
    }

    /// Shows or withholds one Pawn's Health Bar at the table, for good (ADR-0036).
    ///
    /// Straight to `stats.json`, never through the Log, during a fight as outside one: it is
    /// not a Change — whether the table could see a bar is not something that happened in
    /// the fight — so neither the Combat Log nor the Session Log hears of it.
    func setShowsHealthBarToPlayers(_ shows: Bool, for pawn: Pawn.ID) {
        var block = statBlock(for: pawn)
        guard block.showsHealthBarToPlayers != shows else { return }
        block.showsHealthBarToPlayers = shows
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
        session == nil
            ? String(localized: "Start a Session first — an Encounter is part of an evening.") : nil
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
        recordPawnMove(id: id, from: origin)
    }

    /// A drag of the whole **Selection** has ended: on disk once, then each Pawn's move
    /// recorded exactly as `commitPawnMove` records a drag of that Pawn alone.
    ///
    /// The same recording, not a copy of it, so a Line or a Change written here cannot drift
    /// from one written by a single drag — a Selection is a way of acting, not a thing in
    /// the record, and the DM Realm import reads the Logs without knowing it exists. No
    /// combined "the Selection moved" record, and nothing for a Light, whose move the Logs
    /// never record (`commitLightMove`). The flush is once for the lot: the moves all landed
    /// in the same document.
    func commitSelectionMove(_ move: SelectionMove) {
        flushPendingFogWrites()
        for member in move.pawns {
            recordPawnMove(id: member.id, from: member.origin)
        }
    }

    /// One Pawn's completed move into whichever Log is live — nothing when it ended where it
    /// began. The record `commitPawnMove` and `commitSelectionMove` share.
    private func recordPawnMove(id: Pawn.ID, from origin: MapPoint) {
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
    /// `Measurement` does. The Distance Unit turns it into metres or feet for display.
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
    /// Character's block its own. It takes the Monster's Face here too, by the rule becoming
    /// a Monster follows: a Face the DM cut by hand, inherited from the sibling, is kept.
    ///
    /// A Treasure that arrives already an Item takes the Item's Face here by the same rule.
    /// It has no numbers to stamp.
    ///
    /// `showingHealthBar` false places it with its Health Bar withheld from the table — what
    /// `AddPlacement` passes on from the last of its Kind. After the stamp, which keeps it,
    /// and before the join, so the fight's snapshot agrees.
    func addPawnToMap(_ pawn: Pawn, showingHealthBar: Bool = true) {
        var pawn = pawn
        if let monster = bestiary.monster(named: pawn.monsterName),
           statsDocument.blocks[pawn.id] == nil {
            setStatBlock(MonsterStamp.statBlock(from: monster, over: StatBlock()), for: pawn.id)
        }
        setShowsHealthBarToPlayers(showingHealthBar, for: pawn.id)
        // Fresh from the Monster or the Item, as its numbers are, never copied from a sibling.
        pawn.face = definitionFace(over: pawn.face, becoming: pawn.monsterName, or: pawn.itemName)
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
    ///
    /// A break is also when the Characters can move: opening another Map is what pauses a
    /// fight, and Durga can be healed on it. So the fight comes back agreeing with them
    /// (`reconcileWithCharacters`) — after the fog, which says who shares, has been read.
    func resumeEncounter(forMapAt url: URL) {
        encounter = nil
        let reader = CombatLogReader()
        guard let newest = reader.newestLogURL(forMapAt: url),
              let lines = try? reader.read(at: newest),
              !lines.isEmpty,
              !CombatLogFold.fold(lines).hasEnded else { return }

        encounter = Encounter(resuming: lines)
        logWriter = try? CombatLogWriter(reopening: newest)
        reconcileWithCharacters()
    }

    /// Records, in the Turn the fight resumes on, whatever happened to its Players'
    /// Characters while it was paused: for each sharing Combatant, a Change from the folded
    /// current hit points, temporary hit points or exhaustion to its Character's, for each
    /// that differs. Nothing when none does.
    ///
    /// The Character wins (ADR-0037): letting the Log win would silently undo the DM's heal,
    /// and refusing edits to a Character in a paused fight would block the DM over a fight
    /// nobody was running. Recorded rather than overwritten, so the fold and the Character
    /// agree and the Log says what happened. Ordinary Changes in the live Turn, never
    /// Corrections: a fight resumes live, and the heal happened now, not in a past Turn.
    private func reconcileWithCharacters() {
        guard let resumed = encounter, !resumed.isCorrecting else { return }
        for (id, folded) in resumed.blocks.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let shared = sharedCharacter(of: id) else { continue }
            let theirs = shared.character.sharedNumbers(over: folded, maxHP: shared.note.maxHP)
            for change in Self.changes(for: id, from: folded, to: theirs) {
                recordChange(change)
            }
        }
    }

    // MARK: The Characters a fight shares numbers with

    /// Hands each sharing Combatant's current and temporary hit points and exhaustion to its
    /// Character, wherever the fold moved them between `old` and `new` — a live Change, a
    /// Correction, or a Change to someone else during another Combatant's Turn alike, since
    /// all of them are a move of the fold (ADR-0037). The Log stays authoritative; the
    /// Character follows it as it moves rather than when the fight stops, because a fight
    /// can be paused instead, and every other Map would show Durga unhurt meanwhile.
    ///
    /// Only for a Combatant the fight already held: one joining brings its Character's
    /// numbers in through the join snapshot, so there is nothing to hand back, and a fight
    /// being resumed says what its Characters are only after `reconcileWithCharacters`. Never
    /// anything else of the block: Conditions, concentration, armour class, maximum hit
    /// points and initiative belong to the Pawn and the fight it is in.
    func shareFoldedNumbers(from old: Encounter?, to new: Encounter?) {
        guard let old, let new else { return }
        let before = old.blocks
        for (id, folded) in new.blocks {
            guard let previous = before[id],
                  previous.currentHP != folded.currentHP
                    || previous.temporaryHP != folded.temporaryHP
                    || previous.exhaustion != folded.exhaustion,
                  let shared = sharedCharacter(of: id) else { continue }
            share(folded, with: shared.character, note: shared.note)
        }
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
    /// the fight, so next week's Encounter starts where this one left off — the numbers, not
    /// the Health Bar setting (`keepingHealthBarSetting`).
    private func syncStatsFromEncounter(_ live: Encounter) {
        for (id, folded) in live.blocks {
            let block = keepingHealthBarSetting(folded, for: id)
            guard statsDocument.blocks[id] != block else { continue }
            statsDocument.blocks[id] = block
        }
        statsAutosave.schedule(statsDocument)
    }
}
