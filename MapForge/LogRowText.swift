import CoreGraphics
import Foundation

/// The words a Log row shows.
///
/// Separated from `LogViewModel` because ordering and phrasing are different questions, and
/// from the view because a sentence is testable and a `Text` is not.
///
/// Every value change reads **before → after**, never a delta. ADR-0008 refused to store a
/// delta, and the view that draws a Correction beside the Turn it amends cannot be the one
/// that invents one: "took 7 damage" is unfalsifiable next to a Correction, where "HP 22 → 15"
/// says exactly what is being corrected.
enum LogRowText {

    /// A time as a DM reads it mid-evening: the hour, not the date. The date is the Session's,
    /// and a Session is one evening.
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Held rather than built per call, unlike `SessionLogFile.name`'s: that one runs once per
    /// file, this one runs once per visible row and the whole log rebuilds on every append.
    ///
    /// The POSIX locale is what makes `HH` mean 24-hour. Without it a DM whose Mac is set to
    /// a 12-hour region gets "09:15" for both breakfast and the middle of the session.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// One `Change`, named for the Combatant it targets.
    static func describe(_ change: Change, combatantName: String,
                         unit: DistanceUnit = .current) -> String {
        switch change {
        case let .hpChanged(_, from, to):
            "\(combatantName) — HP \(number(from)) → \(number(to))"
        case let .tempHPChanged(_, from, to):
            "\(combatantName) — temp HP \(from) → \(to)"
        case let .maxHPChanged(_, from, to):
            "\(combatantName) — max HP \(number(from)) → \(number(to))"
        case let .acChanged(_, from, to):
            "\(combatantName) — AC \(from) → \(to)"
        case let .conditionAdded(_, condition):
            "\(combatantName) — \(condition.title) applied"
        case let .conditionRemoved(_, condition):
            "\(combatantName) — \(condition.title) removed"
        case let .exhaustionChanged(_, from, to):
            "\(combatantName) — exhaustion \(from) → \(to)"
        case let .concentrationChanged(_, isConcentrating):
            isConcentrating
                ? "\(combatantName) — concentrating"
                : "\(combatantName) — concentration ended"
        case let .noteAdded(_, text):
            "\(combatantName) — \(text)"
        case let .moved(_, _, _, distanceSquares):
            "\(combatantName) — moved \(unit.format(squares: distanceSquares))"
        case let .initiativeChanged(_, from, to):
            "\(combatantName) — initiative \(from) → \(to)"
        case let .combatantJoined(_, name, _, initiative, _):
            "\(name) joined, initiative \(initiative)"
        case .combatantRemoved:
            "\(combatantName) — removed from the Order"
        case .orderChanged:
            // A list of UUIDs. Fourteen names is a wall, and the fact that matters is that
            // the DM rearranged the Order.
            "Order changed"
        case .unrecognised:
            "A change this version cannot read"
        }
    }

    /// A hit point total that may be unset. "—", never "0": a Pawn with no hit points recorded
    /// is not a Pawn at zero, and reading one as the other is the difference between a
    /// monster nobody has statted and a dead one.
    private static func number(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    /// A Session Line, or a row that heads a group.
    static func describe(_ row: LogRow, unit: DistanceUnit = .current) -> String {
        switch row {
        // The time is drawn in its own column by every row that carries one, so these say
        // only what happened. Embedding it here too printed it twice on the one row that
        // named it in both places.
        case .sessionStarted:
            "Session started"
        case .sessionEnded:
            "Session ended"
        case let .comment(text, _):
            text
        case let .pawnMoved(label, distanceSquares, _):
            "\(label) moved \(unit.format(squares: distanceSquares))"
        case let .mapSeparator(path):
            (path as NSString).lastPathComponent
        case let .encounterStarted(map, isLive):
            isLive ? "Encounter in progress" : "Encounter on \(mapName(map))"
        case .encounterEnded:
            "Encounter ended"
        case let .encounterUnreadable(map, logFile):
            "This fight's log could not be read — \(mapName(map)), \(logFile)"
        case let .roundHeading(round):
            "Round \(round)"
        case let .turn(combatantName):
            combatantName
        case let .change(change, combatantName):
            describe(change, combatantName: combatantName, unit: unit)
        case let .correction(targetRound, targetCombatantName):
            "Correction to Round \(targetRound) — \(targetCombatantName)"
        case let .correctionChange(change, combatantName):
            describe(change, combatantName: combatantName, unit: unit)
        case let .orphanCorrection(targetRound):
            "Correction to Round \(targetRound), whose Turn is not in this log"
        case let .liveTurn(round, combatantName):
            "Round \(round) — \(combatantName)'s turn now"
        case .unreadableLine:
            "A line this version cannot read"
        }
    }

    private static func mapName(_ map: String?) -> String {
        guard let map, !map.isEmpty else { return "no Map" }
        return (map as NSString).lastPathComponent
    }
}
