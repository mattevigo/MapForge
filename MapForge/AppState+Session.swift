import Foundation

/// The Session reaching disk: the evening's own log, and the hand-off to and from the Combat
/// Log when a fight starts inside it.
///
/// Mirrors `AppState+Combat.swift`: the rules live in `SessionControl` and this file owns the
/// file handle and the published state.
@MainActor
extension AppState {

    /// The file the running Session is appending to, for tests and diagnostics.
    var sessionLogURL: URL? { sessionWriter?.url }

    /// The Map a line names: a path relative to the Workspace root, never an absolute one.
    ///
    /// Relative because the Workspace travels and the machine does not (ADR-0012) — an
    /// absolute path in a Log is a path that rots the moment the folder opens on another Mac.
    /// A path rather than a bare file name because resolving an Encounter's Combat Log goes
    /// through this field, and two `dungeon.png` in different folders are one name (ADR-0016).
    ///
    /// A Map outside the Workspace has no relative path to give and keeps its file name.
    private var sessionMapName: String? {
        guard let mapURL else { return nil }
        guard let workspace else { return mapURL.lastPathComponent }
        return SessionMapPath.relative(from: mapURL, to: workspace)
    }

    // MARK: Starting and stopping

    /// Begins the evening. Refused without a Workspace — there is nowhere to write, the same
    /// refusal `startEncounter` makes for a missing Map.
    func startSession() {
        guard let workspace, session == nil else { return }
        // One `Date()`, not three: the file is named for when the Session started, and two
        // reads either side of a second boundary would name it for a time its own opening
        // line disagrees with.
        let now = Date()
        guard let writer = try? SessionLogWriter(in: workspace, startedAt: now) else { return }
        sessionWriter = writer
        let (started, lines) = SessionControl.start(at: now)
        session = started
        writeSession(lines)
    }

    /// Ends the evening. Writes the closing line whether or not a fight is running: a DM who
    /// stops mid-fight has still stopped.
    func stopSession() {
        guard var live = session else { return }
        writeSession(SessionControl.stop(&live, at: Date()))
        session = nil
        closeSessionLog()
    }

    /// Brings back an evening that was running when the app last quit.
    ///
    /// Falls out of the format as `resumeEncounter` does: the newest Log with no
    /// `sessionEnded` line is an evening still going. An unterminated file is honest — it
    /// records what was known — and inventing an end line for a DM whose laptop slept would
    /// put a lie in the Log.
    func resumeSession(in workspace: Workspace) {
        session = nil
        closeSessionLog()
        let reader = SessionLogReader()
        guard let newest = reader.newestLogURL(in: workspace),
              let lines = try? reader.read(at: newest),
              let resumed = SessionFold.fold(lines) else { return }

        session = resumed
        sessionWriter = try? SessionLogWriter(reopening: newest)
    }

    // MARK: Recording

    /// Appends a Comment to the Session Log.
    ///
    /// `pawnID` is what the DM had selected when they typed, recorded beside the text rather
    /// than as a subject — a Comment is about the moment, not about anybody. **Nothing passes
    /// one yet**: the Live View has no Pawn selection, and the Combat tab's row selection is
    /// meaningful only during a fight, which is exactly when the Comment Bar is disabled. The
    /// parameter stays because the line format carries the field and `CONTEXT.md` describes
    /// it; wiring it needs a Live View selection this app does not have.
    ///
    /// Silent during a fight: `SessionControl` drops it, so no caller needs an `if` about
    /// Encounters.
    func addComment(_ text: String, pawnID: Pawn.ID? = nil) {
        guard var live = session else { return }
        writeSession(SessionControl.comment(text, map: sessionMapName, pawnID: pawnID,
                                            at: Date(), in: &live))
        session = live
    }

    /// Records a completed drag into the Session Log.
    ///
    /// Called from `commitPawnMove` alongside the Combat Log's own record. Whether this
    /// writes anything is `SessionControl`'s decision, not this call site's.
    func recordSessionMove(pawn: Pawn, from origin: MapPoint, distanceSquares: CGFloat) {
        guard var live = session else { return }
        writeSession(SessionControl.pawnMoved(pawnID: pawn.id, label: pawn.label,
                                              map: sessionMapName,
                                              from: origin, to: pawn.at,
                                              distanceSquares: distanceSquares,
                                              at: Date(), in: &live))
        session = live
    }

    /// Records a Roll into the Session Log.
    ///
    /// Called alongside the Combat Log's own record, exactly as `recordSessionMove` is.
    /// Whether this writes anything is `SessionControl`'s decision, not this call site's.
    func recordSessionRoll(pawn: Pawn, ability: Ability, roll: Roll) {
        guard var live = session else { return }
        writeSession(SessionControl.savingThrow(pawnID: pawn.id, label: pawn.label,
                                                map: sessionMapName,
                                                ability: ability, roll: roll,
                                                at: Date(), in: &live))
        session = live
    }

    func recordSessionRoll(pawn: Pawn, skill: Skill, roll: Roll) {
        guard var live = session else { return }
        writeSession(SessionControl.abilityCheck(pawnID: pawn.id, label: pawn.label,
                                                 map: sessionMapName,
                                                 skill: skill, roll: roll,
                                                 at: Date(), in: &live))
        session = live
    }

    // MARK: The hand-off

    /// Hands recording to the Combat Log and writes the pointer naming it.
    ///
    /// Called from `startEncounter` *after* the Combat Log is open, so the pointer names a
    /// file that exists. A no-op with no Session running.
    func noteEncounterStarted(logFile: String) {
        guard var live = session else { return }
        writeSession(SessionControl.encounterStarted(map: sessionMapName, logFile: logFile,
                                                     at: Date(), in: &live))
        session = live
    }

    /// Takes recording back. Called from `stopEncounter` *before* the Combat Log is closed.
    func noteEncounterEnded() {
        guard var live = session else { return }
        writeSession(SessionControl.encounterEnded(map: sessionMapName, at: Date(), in: &live))
        session = live
    }

    // MARK: Writing

    /// Appends immediately, never debounced — the durability the Combat Log already has.
    private func writeSession(_ lines: [SessionLine]) {
        guard !lines.isEmpty, let sessionWriter else { return }
        for line in lines { try? sessionWriter.append(line) }
        // An open Log View re-reads on this. See `sessionLineCount`.
        noteSessionLineWritten()
    }

    private func closeSessionLog() {
        try? sessionWriter?.close()
        sessionWriter = nil
    }
}
