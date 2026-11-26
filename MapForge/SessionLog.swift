import CoreGraphics
import Foundation

/// One line of a Session Log: the record of an evening at the table.
///
/// The file is JSONL — one of these per line, appended and never rewritten — which is the
/// Combat Log's discipline and deliberately *not* its vocabulary. `Change` is keyed on
/// `combatantID` throughout and a Pawn moving outside a fight has no Combatant; `LogLine` is
/// shaped around Rounds and Turns, which a Session has neither of. See
/// `docs/adr/0014-the-session-log-falls-silent-during-an-encounter.md`.
///
/// Encoded externally tagged — `{"line": "comment", …}` — for the reason `LogLine` is: a DM
/// opens this file and reads it.
enum SessionLine: Equatable {
    /// Opens the file.
    case sessionStarted(startedAt: Date)

    /// A line of the DM's own text.
    ///
    /// Carries no target, unlike every `Change`. `pawnID` is what the DM had selected when
    /// they typed, recorded *beside* the text rather than as a subject: a later reader can
    /// see what was being looked at without the Comment claiming to be about it.
    case comment(text: String, map: String?, pawnID: UUID?, at: Date)

    /// A completed drag. `label` is a snapshot, as `Combatant` snapshots a name: a line read
    /// next year must name the Pawn without the fog file it came from.
    case pawnMoved(pawnID: UUID, label: String, map: String?,
                   from: MapPoint, to: MapPoint, distanceSquares: CGFloat, at: Date)

    /// A d20 recorded outside a fight.
    ///
    /// Unlike `comment`'s `pawnID`, this one **is** the subject: a Roll is unambiguously
    /// about the Pawn that made it. `label` is a snapshot for the reason `pawnMoved`'s is.
    /// See `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
    case savingThrow(pawnID: UUID, label: String, map: String?,
                     ability: Ability, roll: Roll, at: Date)
    case abilityCheck(pawnID: UUID, label: String, map: String?,
                      skill: Skill, roll: Roll, at: Date)

    /// The pointer that opens a hole in this file. `logFile` names the Combat Log that holds
    /// what happened next — the Session Log records nothing until `encounterEnded`.
    case encounterStarted(map: String?, logFile: String, at: Date)
    case encounterEnded(map: String?, at: Date)
    case sessionEnded(endedAt: Date)

    /// One edit gesture, outside a fight, that moved a Character's current hit points,
    /// temporary hit points or exhaustion — made through one of the Pawns sharing them
    /// (ADR-0037). "Hit 7" is one Line, and so is changing hit points and exhaustion together.
    ///
    /// Recorded because a hero's wounds now outlive the Map they were taken on, and the
    /// evening's story includes the cleric healing her in the street. A Creature's numbers
    /// changed outside a fight are not: they are the Map's, not the evening's.
    ///
    /// On disk, flat, **with only the numbers that moved** — the keys a DM Realm import reads:
    ///
    ///     {"line": "characterChanged", "characterID": "<uuid>", "name": "Durga",
    ///      "pawnID": "<uuid>", "label": "Durga", "map": "town/street.png",
    ///      "currentHP": {"from": 12, "to": 19}, "exhaustion": {"from": 2, "to": 1},
    ///      "at": "2026-11-26T20:15:00Z"}
    ///
    /// - `characterID`, `name`: the Character, its name a snapshot as `label` is.
    /// - `pawnID`, `label`: the Pawn the edit was made through, `label` a snapshot.
    /// - `map`: the Map it was made on, as every other Line names one; absent with none.
    /// - `currentHP`, `temporaryHP`, `exhaustion`: each `{"from", "to"}`, before and after,
    ///   never a delta; absent when that number did not move. `currentHP`'s `from` or `to`
    ///   is `null` for hit points never recorded — a note with no maximum — never 0.
    case characterChanged(CharacterNumbersMoved, pawnID: UUID, label: String, map: String?,
                          at: Date)

    /// One Long Rest granted to a Party, with each Character it changed.
    ///
    /// No Map: a rest is taken in the roster, not on any Map. On disk:
    ///
    ///     {"line": "longRest", "partyID": "<uuid>", "partyName": "Eroi",
    ///      "characters": [
    ///        {"characterID": "<uuid>", "name": "Durga", "currentHP": {"from": 19, "to": 48}},
    ///        {"characterID": "<uuid>", "name": "Ayla", "exhaustion": {"from": 2, "to": 1}}],
    ///      "at": "2026-11-26T23:40:00Z"}
    ///
    /// - `partyID`, `partyName`: the Party rested, its name a snapshot.
    /// - `characters`: only the Characters the rest changed, in the Party's order, each with
    ///   the same keys a `characterChanged` Line gives a Character: `characterID`, `name`, and
    ///   `currentHP`, `temporaryHP`, `exhaustion` only for the numbers that moved.
    case longRest(partyID: UUID, partyName: String, characters: [CharacterNumbersMoved], at: Date)

    /// A line this version does not understand, read from a Log a later version wrote.
    ///
    /// Kept rather than dropped for the reason `Change.unrecognised` is kept: losing a whole
    /// evening because one line mentions something new is the worst possible failure for a
    /// file whose entire purpose is to be kept.
    case unrecognised
}

/// One number as something moved it: before and after, never a delta — the rule every Log
/// keeps (ADR-0008).
struct Moved<Value: Codable & Equatable>: Codable, Equatable {
    var from: Value
    var to: Value
}

/// What one gesture did to one Character's shared numbers: before and after for each of its
/// current hit points, temporary hit points and exhaustion that moved, nil for each that did
/// not (ADR-0037). The hit points are the ones a Pawn shows — the note's maximum while the
/// Character is at full — not the roster's nil, which means "at full" only beside a note.
struct CharacterNumbersMoved: Codable, Equatable {
    var characterID: UUID
    /// A snapshot, as a Pawn's `label` is: a Line read next year names the Character without
    /// the roster it came from.
    var name: String
    /// `Int?` inside: hit points never recorded — a note with no maximum — are not 0.
    var currentHP: Moved<Int?>?
    var temporaryHP: Moved<Int>?
    var exhaustion: Moved<Int>?

    init(characterID: UUID, name: String, currentHP: Moved<Int?>? = nil,
         temporaryHP: Moved<Int>? = nil, exhaustion: Moved<Int>? = nil) {
        self.characterID = characterID
        self.name = name
        self.currentHP = currentHP
        self.temporaryHP = temporaryHP
        self.exhaustion = exhaustion
    }

    /// What moved of `character`'s shared numbers between two Stat Blocks showing them — or
    /// nil, when none of the three did, which is no Line at all.
    init?(of character: PartyCharacter, from before: StatBlock, to after: StatBlock) {
        self.init(characterID: character.id, name: character.name)
        if before.currentHP != after.currentHP {
            currentHP = Moved(from: before.currentHP, to: after.currentHP)
        }
        if before.temporaryHP != after.temporaryHP {
            temporaryHP = Moved(from: before.temporaryHP, to: after.temporaryHP)
        }
        if before.exhaustion != after.exhaustion {
            exhaustion = Moved(from: before.exhaustion, to: after.exhaustion)
        }
        guard currentHP != nil || temporaryHP != nil || exhaustion != nil else { return nil }
    }

    /// The flat half, shared by both Lines that carry one: a `characterChanged` writes it
    /// beside its own keys, a `longRest` writes one object of it per Character.
    fileprivate enum CodingKeys: String, CodingKey {
        case characterID, name, currentHP, temporaryHP, exhaustion
    }
}

extension SessionLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case line, startedAt, endedAt, at, text, map, pawnID, label
        case from, to, distanceSquares, logFile
        // A Roll, written flat: a DM opens this file and reads it.
        case ability, skill, d20, modifier, difficultyClass
        // A Long Rest's. A `characterChanged`'s Character is read through its own keys.
        case partyID, partyName, characters
    }

    private enum Kind: String {
        case sessionStarted, comment, pawnMoved, encounterStarted, encounterEnded, sessionEnded
        case savingThrow, abilityCheck
        case characterChanged, longRest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .line)
        guard let kind = Kind(rawValue: raw) else {
            self = .unrecognised
            return
        }
        let map = try container.decodeIfPresent(String.self, forKey: .map)

        switch kind {
        case .sessionStarted:
            self = .sessionStarted(startedAt: try container.decode(Date.self, forKey: .startedAt))
        case .comment:
            self = .comment(text: try container.decode(String.self, forKey: .text),
                            map: map,
                            pawnID: try container.decodeIfPresent(UUID.self, forKey: .pawnID),
                            at: try container.decode(Date.self, forKey: .at))
        case .pawnMoved:
            self = .pawnMoved(
                pawnID: try container.decode(UUID.self, forKey: .pawnID),
                label: try container.decode(String.self, forKey: .label),
                map: map,
                from: try container.decode(MapPoint.self, forKey: .from),
                to: try container.decode(MapPoint.self, forKey: .to),
                distanceSquares: try container.decode(CGFloat.self, forKey: .distanceSquares),
                at: try container.decode(Date.self, forKey: .at))
        case .savingThrow:
            self = .savingThrow(
                pawnID: try container.decode(UUID.self, forKey: .pawnID),
                label: try container.decode(String.self, forKey: .label),
                map: map,
                ability: try container.decode(Ability.self, forKey: .ability),
                roll: try Self.decodeRoll(from: container),
                at: try container.decode(Date.self, forKey: .at))
        case .abilityCheck:
            self = .abilityCheck(
                pawnID: try container.decode(UUID.self, forKey: .pawnID),
                label: try container.decode(String.self, forKey: .label),
                map: map,
                skill: try container.decode(Skill.self, forKey: .skill),
                roll: try Self.decodeRoll(from: container),
                at: try container.decode(Date.self, forKey: .at))
        case .encounterStarted:
            self = .encounterStarted(map: map,
                                     logFile: try container.decode(String.self, forKey: .logFile),
                                     at: try container.decode(Date.self, forKey: .at))
        case .encounterEnded:
            self = .encounterEnded(map: map, at: try container.decode(Date.self, forKey: .at))
        case .sessionEnded:
            self = .sessionEnded(endedAt: try container.decode(Date.self, forKey: .endedAt))
        case .characterChanged:
            // The Character's keys sit beside the Line's own, so it is read from the same
            // object rather than a nested one.
            self = .characterChanged(try CharacterNumbersMoved(from: decoder),
                                     pawnID: try container.decode(UUID.self, forKey: .pawnID),
                                     label: try container.decode(String.self, forKey: .label),
                                     map: map,
                                     at: try container.decode(Date.self, forKey: .at))
        case .longRest:
            self = .longRest(
                partyID: try container.decode(UUID.self, forKey: .partyID),
                partyName: try container.decode(String.self, forKey: .partyName),
                characters: try container.decode([CharacterNumbersMoved].self,
                                                 forKey: .characters),
                at: try container.decode(Date.self, forKey: .at))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sessionStarted(startedAt):
            try container.encode(Kind.sessionStarted.rawValue, forKey: .line)
            try container.encode(startedAt, forKey: .startedAt)
        case let .comment(text, map, pawnID, at):
            try container.encode(Kind.comment.rawValue, forKey: .line)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(map, forKey: .map)
            try container.encodeIfPresent(pawnID, forKey: .pawnID)
            try container.encode(at, forKey: .at)
        case let .pawnMoved(pawnID, label, map, from, to, distanceSquares, at):
            try container.encode(Kind.pawnMoved.rawValue, forKey: .line)
            try container.encode(pawnID, forKey: .pawnID)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(map, forKey: .map)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(distanceSquares, forKey: .distanceSquares)
            try container.encode(at, forKey: .at)
        case let .savingThrow(pawnID, label, map, ability, roll, at):
            try container.encode(Kind.savingThrow.rawValue, forKey: .line)
            try container.encode(pawnID, forKey: .pawnID)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(map, forKey: .map)
            try container.encode(ability, forKey: .ability)
            try Self.encode(roll, into: &container)
            try container.encode(at, forKey: .at)
        case let .abilityCheck(pawnID, label, map, skill, roll, at):
            try container.encode(Kind.abilityCheck.rawValue, forKey: .line)
            try container.encode(pawnID, forKey: .pawnID)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(map, forKey: .map)
            // The Skill only: its Ability is derived, and a stored copy could disagree.
            try container.encode(skill, forKey: .skill)
            try Self.encode(roll, into: &container)
            try container.encode(at, forKey: .at)
        case let .encounterStarted(map, logFile, at):
            try container.encode(Kind.encounterStarted.rawValue, forKey: .line)
            try container.encodeIfPresent(map, forKey: .map)
            try container.encode(logFile, forKey: .logFile)
            try container.encode(at, forKey: .at)
        case let .encounterEnded(map, at):
            try container.encode(Kind.encounterEnded.rawValue, forKey: .line)
            try container.encodeIfPresent(map, forKey: .map)
            try container.encode(at, forKey: .at)
        case let .sessionEnded(endedAt):
            try container.encode(Kind.sessionEnded.rawValue, forKey: .line)
            try container.encode(endedAt, forKey: .endedAt)
        case let .characterChanged(numbers, pawnID, label, map, at):
            try container.encode(Kind.characterChanged.rawValue, forKey: .line)
            // Flat, into the same object: one Character, so nothing to nest it for.
            try numbers.encode(to: encoder)
            try container.encode(pawnID, forKey: .pawnID)
            try container.encode(label, forKey: .label)
            try container.encodeIfPresent(map, forKey: .map)
            try container.encode(at, forKey: .at)
        case let .longRest(partyID, partyName, characters, at):
            try container.encode(Kind.longRest.rawValue, forKey: .line)
            try container.encode(partyID, forKey: .partyID)
            try container.encode(partyName, forKey: .partyName)
            try container.encode(characters, forKey: .characters)
            try container.encode(at, forKey: .at)
        case .unrecognised:
            throw EncodingError.invalidValue(self, .init(
                codingPath: container.codingPath,
                debugDescription: "an unrecognised line is read-only and is never written back"))
        }
    }

    /// The flat half of a Roll. `succeeded` and `total` are derived and never on disk.
    private static func decodeRoll(
        from container: KeyedDecodingContainer<CodingKeys>) throws -> Roll {
        Roll(d20: try container.decode(Int.self, forKey: .d20),
             modifier: try container.decode(Int.self, forKey: .modifier),
             difficultyClass: try container.decodeIfPresent(Int.self, forKey: .difficultyClass))
    }

    private static func encode(_ roll: Roll,
                               into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(roll.d20, forKey: .d20)
        try container.encode(roll.modifier, forKey: .modifier)
        // Absent rather than null when the DM did not set one.
        try container.encodeIfPresent(roll.difficultyClass, forKey: .difficultyClass)
    }
}

/// Shared naming for the JSONL files in a Workspace's sessions folder.
///
/// Mirrors `CombatLogFile` rather than sharing with it: the two formats keep the same
/// discipline on purpose and are free to diverge, which a shared type would prevent.
enum SessionLogFile {
    static let fileExtension = "jsonl"

    /// `.mapforge/sessions/` — a Session belongs to the Workspace, not to any Map, because an
    /// evening outlives the Map it happens to begin on. See ADR-0015.
    static func directory(in workspace: Workspace) -> URL {
        workspace.supportDirectory.appendingPathComponent("sessions")
    }

    /// `2026-09-16T190000Z.jsonl` — sortable as text, unique to the second, and legible.
    /// Colons are avoided: legal in a POSIX filename and a lifetime of trouble elsewhere.
    static func name(startedAt date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.string(from: date)).\(fileExtension)"
    }

    /// Deliberately not pretty-printed: a newline inside an object would split it across two
    /// lines and the format would stop meaning anything. `.sortedKeys` keeps a line stable
    /// between runs, and `.withoutEscapingSlashes` keeps a DM's Comment readable.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Appends lines to one Session's Log.
///
/// Append-only, one line per call, flushed on every call — the Combat Log's durability
/// boundary applied to an evening. Nothing here is debounced and nothing is ever read back
/// and rewritten.
final class SessionLogWriter {
    /// The file this writer appends to. One per Session, named for when it started.
    let url: URL

    private let handle: FileHandle

    init(in workspace: Workspace, startedAt: Date = Date(),
         fileManager: FileManager = .default) throws {
        let directory = SessionLogFile.directory(in: workspace)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(SessionLogFile.name(startedAt: startedAt))
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    /// Reopens an existing Log to append to it — the writer a resumed evening needs.
    init(reopening url: URL) throws {
        self.url = url
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    deinit { try? handle.close() }

    /// Appends one line and flushes it. A crash after this returns has lost nothing.
    func append(_ line: SessionLine) throws {
        var data = try SessionLogFile.encoder().encode(line)
        data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func close() throws {
        try handle.close()
    }
}

/// Reads a Session Log back.
struct SessionLogReader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Every line of a Log, in the order they were written.
    ///
    /// A truncated or malformed final line is dropped, not an error: refusing to open the
    /// file would lose a whole evening to save the last line of it. An absent file reads as
    /// no lines.
    func read(at url: URL) throws -> [SessionLine] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = SessionLogFile.decoder()
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(SessionLine.self, from: Data($0.utf8)) }
    }

    /// Every Session run out of a Workspace, oldest first. The filenames sort as text
    /// because `SessionLogFile.name` is built so they do.
    func logURLs(in workspace: Workspace) -> [URL] {
        let directory = SessionLogFile.directory(in: workspace)
        let contents = (try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == SessionLogFile.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The most recent Session — the one to resume if it never ended.
    func newestLogURL(in workspace: Workspace) -> URL? {
        logURLs(in: workspace).last
    }
}
