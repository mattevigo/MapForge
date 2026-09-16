import CoreGraphics
import Foundation

/// One evening at the table: the thing an Encounter happens inside.
///
/// A value, not a manager. What a gesture does to it lives in `SessionControl`, so every rule
/// is testable without a disk or a window — the shape `Encounter`/`EncounterControl` already
/// has.
struct Session: Equatable {
    let startedAt: Date

    /// True between `encounterStarted` and `encounterEnded`: the Session Log is silent.
    ///
    /// The whole of ADR-0014 as one Bool, and the single place the rule lives. No caller
    /// needs to remember it, because `SessionControl` refuses to produce a line while it is
    /// set.
    private(set) var isRecordingSuspended: Bool

    init(startedAt: Date, isRecordingSuspended: Bool = false) {
        self.startedAt = startedAt
        self.isRecordingSuspended = isRecordingSuspended
    }

    fileprivate mutating func suspendRecording() { isRecordingSuspended = true }
    fileprivate mutating func resumeRecording() { isRecordingSuspended = false }
}

/// What each gesture does to a Session, and what it writes.
///
/// Every function returns the lines to append rather than appending them: the rules are then
/// a pure function of the gesture and the state, and the file handle is somebody else's
/// problem. `AppState` is that somebody.
enum SessionControl {

    static func start(at date: Date) -> (Session, [SessionLine]) {
        (Session(startedAt: date), [.sessionStarted(startedAt: date)])
    }

    /// A line of the DM's own text. Trimmed, and dropped when empty — the rule
    /// `AppState.addNote` already applies to a Turn note.
    static func comment(_ text: String, map: String?, pawnID: UUID?,
                        at date: Date, in session: inout Session) -> [SessionLine] {
        guard !session.isRecordingSuspended else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [.comment(text: trimmed, map: map, pawnID: pawnID, at: date)]
    }

    /// A completed drag. Silent during a fight, where the Combat Log records the same drag
    /// as a `Change` — the rule that keeps exactly one recorder live at any instant.
    static func pawnMoved(pawnID: UUID, label: String, map: String?,
                          from: MapPoint, to: MapPoint, distanceSquares: CGFloat,
                          at date: Date, in session: inout Session) -> [SessionLine] {
        guard !session.isRecordingSuspended else { return [] }
        return [.pawnMoved(pawnID: pawnID, label: label, map: map, from: from, to: to,
                           distanceSquares: distanceSquares, at: date)]
    }

    /// Hands recording over to the Combat Log.
    ///
    /// The pointer line is written *even though* this call sets the flag: it is what makes
    /// the hole in the file legible, naming the file that holds what happened next.
    static func encounterStarted(map: String?, logFile: String, at date: Date,
                                 in session: inout Session) -> [SessionLine] {
        // Two fights cannot nest, but a double call must not write two pointers.
        guard !session.isRecordingSuspended else { return [] }
        session.suspendRecording()
        return [.encounterStarted(map: map, logFile: logFile, at: date)]
    }

    /// Takes recording back. The resume line is what lets a fold tell "silent" from "ended".
    static func encounterEnded(map: String?, at date: Date,
                               in session: inout Session) -> [SessionLine] {
        guard session.isRecordingSuspended else { return [] }
        session.resumeRecording()
        return [.encounterEnded(map: map, at: date)]
    }

    /// Ends the evening, fight or no fight. The Combat Log's own end line is not this file's
    /// business — a DM who stops while suspended has still stopped.
    ///
    /// The suspension flag is left as it stands rather than cleared. An ended Session is
    /// discarded by its caller, so clearing it would change nothing anybody reads; what it
    /// would do is hand a caller who inspects the returned value an un-suspended Session
    /// that was mid-fight when it ended.
    static func stop(_ session: inout Session, at date: Date) -> [SessionLine] {
        [.sessionEnded(endedAt: date)]
    }
}

/// The minimum fold needed to pick an evening back up.
///
/// Not a full replay — there is no state in a Session Log beyond "is it still running, and is
/// it mid-fight". Everything else in the file is a record for a human to read, which is the
/// same trade ADR-0008 made for the Combat Log.
enum SessionFold {
    /// The Session a file describes, or nil if it ended or never began.
    static func fold(_ lines: [SessionLine]) -> Session? {
        var session: Session?
        for line in lines {
            switch line {
            case let .sessionStarted(startedAt):
                session = Session(startedAt: startedAt)
            case .sessionEnded:
                return nil
            case .encounterStarted:
                session?.suspendRecording()
            case .encounterEnded:
                session?.resumeRecording()
            case .comment, .pawnMoved, .unrecognised:
                // Records, not state. An unrecognised line must never end the evening.
                break
            }
        }
        return session
    }
}
