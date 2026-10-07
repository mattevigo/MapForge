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
            String(localized: "\(combatantName) — HP \(number(from)) → \(number(to))")
        case let .tempHPChanged(_, from, to):
            String(localized: "\(combatantName) — temp HP \(from) → \(to)")
        case let .maxHPChanged(_, from, to):
            String(localized: "\(combatantName) — max HP \(number(from)) → \(number(to))")
        case let .acChanged(_, from, to):
            String(localized: "\(combatantName) — AC \(from) → \(to)")
        case let .initiativeBonusChanged(_, from, to):
            String(localized: "\(combatantName) — initiative bonus \(signed(from)) → \(signed(to))")
        case let .conditionAdded(_, condition):
            String(localized: "\(combatantName) — \(condition.title) applied")
        case let .conditionRemoved(_, condition):
            String(localized: "\(combatantName) — \(condition.title) removed")
        case let .exhaustionChanged(_, from, to):
            String(localized: "\(combatantName) — exhaustion \(from) → \(to)")
        case let .concentrationChanged(_, isConcentrating):
            isConcentrating
                ? String(localized: "\(combatantName) — concentrating")
                : String(localized: "\(combatantName) — concentration ended")
        case let .noteAdded(_, text):
            String(localized: "\(combatantName) — \(text)")
        case let .moved(_, _, _, distanceSquares):
            String(localized: "\(combatantName) — moved \(unit.format(squares: distanceSquares))")
        case let .initiativeChanged(_, from, to):
            String(localized: "\(combatantName) — initiative \(from) → \(to)")
        case let .combatantJoined(_, name, _, initiative, _):
            String(localized: "\(name) joined, initiative \(initiative)")
        case .combatantRemoved:
            String(localized: "\(combatantName) — removed from the Order")
        case .orderChanged:
            // A list of UUIDs. Fourteen names is a wall, and the fact that matters is that
            // the DM rearranged the Order.
            String(localized: "Order changed")
        // The Roll's own snapshot, not the resolved `combatantName`: a Pawn that never
        // joined the Order resolves to nothing, and its own line is the only thing that
        // knows who rolled.
        case let .savingThrow(_, name, ability, roll):
            String(localized: "\(name) — \(ability.abbreviation) save \(describe(roll))")
        case let .abilityCheck(_, name, skill, roll):
            String(localized: "\(name) — \(skill.title) (\(skill.ability.abbreviation)) \(describe(roll))")
        case .unrecognised:
            String(localized: "A change this version cannot read")
        }
    }

    /// A Roll's numbers: the total, the arithmetic that produced it, and the verdict where
    /// there is a Difficulty Class to have one.
    ///
    /// The arithmetic is shown because the die is the part the table remembers — "21" alone
    /// loses the 16 that everyone watched land.
    static func describe(_ roll: Roll) -> String {
        let total = "\(roll.total) (\(arithmetic(of: roll)))"
        guard let difficultyClass = roll.difficultyClass else { return total }
        // `succeeded` is non-nil exactly when there is a DC. Whole sentences rather than
        // fragments appended, because a translation cannot reorder a fragment.
        return roll.succeeded == true
            ? String(localized: "\(total) vs DC \(difficultyClass) — succeeded")
            : String(localized: "\(total) vs DC \(difficultyClass) — failed")
    }

    /// Just the sum that produced the total — "16 + 5", or "9 - 1" for a negative Modifier,
    /// which is the shape a DM would have said out loud. The Roll sheet shows this beside a
    /// large total, where the Log shows it in parentheses after one.
    static func arithmetic(of roll: Roll) -> String {
        roll.modifier < 0
            ? "\(roll.d20) - \(abs(roll.modifier))"
            : "\(roll.d20) + \(roll.modifier)"
    }

    /// A hit point total that may be unset. "—", never "0": a Pawn with no hit points recorded
    /// is not a Pawn at zero, and reading one as the other is the difference between a
    /// monster nobody has statted and a dead one.
    private static func number(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    /// A bonus as a DM writes one: "+2", "−1", "+0". A true minus rather than a hyphen, as
    /// their own notes use.
    private static func signed(_ value: Int) -> String {
        value < 0 ? "−\(-value)" : "+\(value)"
    }

    /// A Session Line, or a row that heads a group.
    static func describe(_ row: LogRow, unit: DistanceUnit = .current) -> String {
        switch row {
        // The time is drawn in its own column by every row that carries one, so these say
        // only what happened. Embedding it here too printed it twice on the one row that
        // named it in both places.
        case .sessionStarted:
            String(localized: "Session started")
        case .sessionEnded:
            String(localized: "Session ended")
        case let .comment(text, _):
            text
        case let .pawnMoved(label, distanceSquares, _):
            String(localized: "\(label) moved \(unit.format(squares: distanceSquares))")
        case let .savingThrow(label, ability, roll, _):
            // The same wording the Combat Log's own row uses, so a Roll reads identically
            // on either side of an Encounter's splice.
            String(localized: "\(label) — \(ability.abbreviation) save \(describe(roll))")
        case let .abilityCheck(label, skill, roll, _):
            String(localized: "\(label) — \(skill.title) (\(skill.ability.abbreviation)) \(describe(roll))")
        case let .mapSeparator(path):
            (path as NSString).lastPathComponent
        case let .encounterStarted(map, isLive):
            isLive ? String(localized: "Encounter in progress")
                : String(localized: "Encounter on \(mapName(map))")
        case .encounterEnded:
            String(localized: "Encounter ended")
        case let .encounterUnreadable(map, logFile):
            String(localized: "This Encounter's Combat Log could not be read — \(mapName(map)), \(logFile)")
        case let .roundHeading(round):
            String(localized: "Round \(round)")
        case let .turn(combatantName):
            combatantName
        case let .change(change, combatantName):
            describe(change, combatantName: combatantName, unit: unit)
        case let .correction(targetRound, targetCombatantName):
            String(localized: "Correction to Round \(targetRound) — \(targetCombatantName)")
        case let .correctionChange(change, combatantName):
            describe(change, combatantName: combatantName, unit: unit)
        case let .orphanCorrection(targetRound):
            String(localized: "Correction to Round \(targetRound), whose Turn is not in this log")
        case let .liveTurn(round, combatantName):
            String(localized: "Round \(round) — \(combatantName)'s turn now")
        case .unreadableLine:
            String(localized: "A line this version cannot read")
        }
    }

    private static func mapName(_ map: String?) -> String {
        guard let map, !map.isEmpty else { return String(localized: "no Map") }
        return (map as NSString).lastPathComponent
    }
}
