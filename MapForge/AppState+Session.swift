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

    /// The Map name a line carries: the file name, never a path. The Workspace travels and
    /// the machine does not (ADR-0012), so an absolute path in a Log is a path that rots.
    private var sessionMapName: String? { mapURL?.lastPathComponent }

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
    }

    private func closeSessionLog() {
        try? sessionWriter?.close()
        sessionWriter = nil
    }
}
