import CoreGraphics
import Foundation

/// One row of the Log View: the evening flattened into things a DM reads, in the order they
/// happened.
///
/// Deliberately flat rather than a tree of Rounds holding Turns holding Changes. The view is a
/// `ScrollView` over a `ForEach` and nothing else, and the indentation that makes the grouping
/// visible is a property of the row rather than a shape the view has to walk. A tree would put
/// the ordering rules in two places — here and in the view's traversal — and ADR-0016's whole
/// point is that the order is decided once.
enum LogRow: Equatable {
    case sessionStarted(at: Date)
    case sessionEnded(at: Date)
    case comment(text: String, at: Date)
    case pawnMoved(label: String, distanceSquares: CGFloat, at: Date)

    /// The Map changed. Synthetic: nothing records a switch, so this is inferred from two
    /// consecutive Lines disagreeing about their Map. See ADR-0016.
    case mapSeparator(path: String)

    case encounterStarted(map: String?, isLive: Bool)
    case encounterEnded

    /// The pointer resolved to nothing. Drawn rather than skipped: a fight that silently
    /// vanishes leaves a gap nobody can see.
    case encounterUnreadable(map: String?, logFile: String)

    case roundHeading(round: Int)
    case turn(combatantName: String)
    case change(Change, combatantName: String)

    case correction(targetRound: Int, targetCombatantName: String)
    case correctionChange(Change, combatantName: String)

    /// A Correction naming a Turn that is not in the file. `CombatLogFold` ignores these,
    /// which is right for computing state and wrong for reading history.
    case orphanCorrection(targetRound: Int)

    /// Whose Turn it is right now, at the foot of a live fight.
    ///
    /// The Turns above it are the ones that have *ended* — a Turn writes its line when it is
    /// over — so without this the Combatant currently acting is the one person the log does
    /// not mention.
    case liveTurn(round: Int, combatantName: String)

    /// A Line this version cannot read, or one that would not parse at all. Position is the
    /// only fact it has left — `SessionLine.unrecognised` keeps no timestamp.
    case unreadableLine

    // Deliberately not `Identifiable`. The log is rebuilt wholesale on every append and rows
    // are never diffed across reads, so the view identifies them by position —
    // `ForEach(Array(rows.enumerated()), id: \.offset)` — and an id on the row itself would
    // be a second answer to a question the view has already answered.
}

/// How deep a row sits: Rounds hold Turns, Turns hold Changes.
///
/// A property of the row rather than a shape the view walks, so the grouping and the order are
/// decided in the same pass.
extension LogRow {
    var indent: Int {
        switch self {
        case .turn, .liveTurn, .correction, .orphanCorrection: 1
        case .change, .correctionChange: 2
        default: 0
        }
    }
}

/// Reads an evening: a Session Log, and the Combat Logs it points at, as one list of rows.
///
/// The rules are ADR-0016's. File order throughout, no timestamp is ever compared, each
/// Encounter's Turns spliced into the hole its pointer marks — and Corrections moved beneath
/// the Turn they target, which is the one deliberate departure and the thing ADR-0010 bought
/// append-only Corrections for.
struct LogViewModel {
    private let combatReader: CombatLogReader
    private let sessionReader: SessionLogReader
    private let fileManager: FileManager

    init(sessionReader: SessionLogReader = SessionLogReader(),
         combatReader: CombatLogReader = CombatLogReader(),
         fileManager: FileManager = .default) {
        self.sessionReader = sessionReader
        self.combatReader = combatReader
        self.fileManager = fileManager
    }

    /// The evening as rows.
    ///
    /// `liveEncounterLines` is the running fight's lines, which the Encounter holds in memory
    /// and has not necessarily flushed. Passing them is what lets a Turn appear the moment it
    /// ends rather than at the next read of the file.
    func rows(sessionLogAt url: URL,
              workspace: Workspace,
              liveEncounterLines: [LogLine] = []) -> [LogRow] {
        let lines = (try? sessionReader.read(at: url)) ?? []
        let liveIndex = Self.unclosedEncounterIndex(in: lines)
        var rows: [LogRow] = []
        var currentMap: String?
        var hasSeenMap = false

        for (index, line) in lines.enumerated() {
            // A Map change is inferred, never recorded. The first Line establishes the Map
            // rather than announcing it: a separator above the opening line would be a change
            // from nothing.
            if let map = line.map {
                if hasSeenMap, currentMap != map { rows.append(.mapSeparator(path: map)) }
                currentMap = map
                hasSeenMap = true
            }

            switch line {
            case let .sessionStarted(at):
                rows.append(.sessionStarted(at: at))
            case let .sessionEnded(at):
                rows.append(.sessionEnded(at: at))
            case let .comment(text, _, _, at):
                rows.append(.comment(text: text, at: at))
            case let .pawnMoved(_, label, _, _, _, distance, at):
                rows.append(.pawnMoved(label: label, distanceSquares: distance, at: at))
            case let .encounterStarted(map, logFile, _):
                // The live fight is the one pointer nothing closes: the Session Log falls
                // silent for a fight's whole extent (ADR-0014), so a pointer with no close
                // after it is the fight happening now.
                let isLive = !liveEncounterLines.isEmpty && index == liveIndex
                rows.append(contentsOf: encounterRows(map: map, logFile: logFile,
                                                      workspace: workspace,
                                                      liveLines: isLive ? liveEncounterLines : []))
            case .encounterEnded:
                rows.append(.encounterEnded)
            case .unrecognised:
                rows.append(.unreadableLine)
            }
        }
        return rows
    }

    /// The pointer no `encounterEnded` closes, if there is one.
    ///
    /// Walked forwards once, tracking the open pointer and clearing it on each close, rather
    /// than asking of each pointer "is there any close after me" — that question answers
    /// correctly only for a file whose opens and closes alternate perfectly, and says
    /// "finished" for every pointer the moment a stray close appears anywhere later.
    private static func unclosedEncounterIndex(in lines: [SessionLine]) -> Int? {
        var open: Int?
        for (index, line) in lines.enumerated() {
            switch line {
            case .encounterStarted: open = index
            case .encounterEnded: open = nil
            default: continue
            }
        }
        return open
    }

    /// One fight: its pointer row, then its Turns, then whatever closes it.
    private func encounterRows(map: String?, logFile: String, workspace: Workspace,
                               liveLines: [LogLine]) -> [LogRow] {
        // A live fight is read from memory: its last Turn may not be on disk yet, and the
        // Encounter is the authority on a fight still running.
        if !liveLines.isEmpty {
            return [.encounterStarted(map: map, isLive: true)]
                + Self.combatRows(liveLines)
                + Self.liveTurnRow(liveLines)
        }
        guard let mapURL = SessionMapPath.resolve(map, in: workspace) else {
            return [.encounterUnreadable(map: map, logFile: logFile)]
        }
        let logURL = StatsStore.combatDirectory(forMapAt: mapURL).appendingPathComponent(logFile)
        // Missing or unparseable is unreadable; **empty is not**. A fight the DM stopped
        // before anyone took a Turn wrote a real file with nothing in it, and reporting that
        // as an error would be the silent drop this view exists to avoid, wearing a warning's
        // clothes.
        guard fileManager.fileExists(atPath: logURL.path),
              let lines = try? combatReader.read(at: logURL) else {
            return [.encounterUnreadable(map: map, logFile: logFile)]
        }
        return [.encounterStarted(map: map, isLive: false)] + Self.combatRows(lines)
    }

    /// Whose Turn it is, for a fight still running.
    ///
    /// Folded from the same lines the rows came from rather than read off the `Encounter`:
    /// the fold is what decides whose Turn it is everywhere else in this app, and a second
    /// answer computed differently would be a second truth.
    static func liveTurnRow(_ lines: [LogLine]) -> [LogRow] {
        let state = CombatLogFold.fold(lines)
        guard !state.hasEnded, let active = state.activeCombatantID else { return [] }
        return [.liveTurn(round: state.round,
                          combatantName: state.name(of: active) ?? "Unknown combatant")]
    }

    /// A Combat Log as rows: Rounds grouping Turns, Turns grouping Changes, Corrections drawn
    /// beneath the Turn they name.
    static func combatRows(_ lines: [LogLine]) -> [LogRow] {
        let names = CombatantNames(lines)

        // Gathered first so a Correction can be drawn under its Turn in one pass. Keyed as the
        // fold keys them, so the two agree about what a Correction targets.
        var corrections: [TurnKey: [(round: Int, changes: [Change])]] = [:]
        for case let .correction(round, combatantID, changes, _) in lines {
            corrections[TurnKey(round: round, combatantID: combatantID), default: []]
                .append((round, changes))
        }

        var rows: [LogRow] = []
        var round: Int?
        var targeted: Set<TurnKey> = []

        for line in lines {
            switch line {
            case .encounterStarted:
                continue
            case let .turn(turnRound, combatantID, changes, _):
                if round != turnRound {
                    rows.append(.roundHeading(round: turnRound))
                    round = turnRound
                }
                let name = names.name(of: combatantID)
                // An empty Turn still appears: a run of them is the answer to "when did the
                // ogre stop doing anything", and hiding them makes the Round's count wrong.
                rows.append(.turn(combatantName: name))
                rows.append(contentsOf: changes.map { .change($0, combatantName: names.name(of: $0.combatantID)) })

                let key = TurnKey(round: turnRound, combatantID: combatantID)
                for correction in corrections[key] ?? [] {
                    rows.append(.correction(targetRound: correction.round,
                                            targetCombatantName: name))
                    rows.append(contentsOf: correction.changes.map {
                        .correctionChange($0, combatantName: names.name(of: $0.combatantID))
                    })
                }
                targeted.insert(key)
            case let .correction(round, combatantID, _, _):
                // Drawn where the file put it only when its Turn never arrives. A Correction
                // whose Turn exists was already drawn beneath it.
                if !targeted.contains(TurnKey(round: round, combatantID: combatantID)) {
                    rows.append(.orphanCorrection(targetRound: round))
                }
            case .encounterEnded:
                continue
            }
        }
        return rows
    }

    /// How a Turn is addressed, and how a Correction names the Turn it amends.
    private struct TurnKey: Hashable {
        let round: Int
        let combatantID: UUID
    }
}

/// Every name a Combat Log knows, from its opening snapshot and from whoever joined later.
///
/// A Turn carries a `combatantID` and no name — the names are on `encounterStarted`'s snapshot
/// and on each `combatantJoined`. An ID that resolves to nothing is named as unknown rather
/// than blank: a row with no name reads as a bug, and a fight whose roster was written by a
/// later version should still be legible.
struct CombatantNames {
    private var names: [UUID: String] = [:]

    init(_ lines: [LogLine]) {
        for line in lines {
            switch line {
            case let .encounterStarted(_, _, combatants):
                for combatant in combatants { names[combatant.id] = combatant.name }
            case let .turn(_, _, changes, _), let .correction(_, _, changes, _):
                for case let .combatantJoined(id, name, _, _, _) in changes { names[id] = name }
            case .encounterEnded:
                continue
            }
        }
    }

    func name(of id: UUID?) -> String {
        guard let id else { return "—" }
        return names[id] ?? "Unknown combatant"
    }
}

private extension SessionLine {
    /// The Map this Line names, or nil for the Lines that name none.
    ///
    /// Doubly optional at the source — a Line may carry no Map, and three Lines have no Map
    /// field at all — which is flattened here because a Map separator wants one question
    /// answered: does this Line say what Map it happened on?
    var map: String? {
        switch self {
        case let .comment(_, map, _, _): map
        case let .pawnMoved(_, _, map, _, _, _, _): map
        case let .encounterStarted(map, _, _): map
        case let .encounterEnded(map, _): map
        case .sessionStarted, .sessionEnded, .unrecognised: nil
        }
    }
}
