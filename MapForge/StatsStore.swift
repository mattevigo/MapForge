import Foundation

/// Every Stat Block on one Map, keyed by the Pawn it belongs to.
///
/// Keyed rather than held on `Pawn` so the record outlives the token: a Creature deleted
/// from the Map mid-Encounter leaves its numbers behind, and the Combat Log that names it
/// still has something to describe. See
/// `docs/adr/0009-combat-state-lives-outside-the-fog-document.md`.
struct StatsDocument: Codable, Equatable {
    static let current = 1

    var version = current
    var blocks: [UUID: StatBlock] = [:]

    var isEmpty: Bool { blocks.isEmpty }

    init(version: Int = StatsDocument.current, blocks: [UUID: StatBlock] = [:]) {
        self.version = version
        self.blocks = blocks
    }

    /// One Pawn's numbers on disk. `[UUID: StatBlock]` encodes by default as an unkeyed
    /// array of alternating keys and values — valid JSON that no DM can read or hand-edit,
    /// which defeats the reason this is JSON at all.
    private struct Entry: Codable {
        var pawnID: UUID
        var block: StatBlock
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.current
        let entries = try container.decodeIfPresent([Entry].self, forKey: .blocks) ?? []
        blocks = Dictionary(uniqueKeysWithValues: entries.map { ($0.pawnID, $0.block) })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Stamp the current version rather than echoing what was read, as
        // `FogDocument.encode(to:)` does — this file will outlive its first shape.
        try container.encode(Self.current, forKey: .version)
        // Sorted so a DM who version-controls their maps gets meaningful diffs rather
        // than a reshuffle every time the dictionary rehashes.
        let entries = blocks
            .map { Entry(pawnID: $0.key, block: $0.value) }
            .sorted { $0.pawnID.uuidString < $1.pawnID.uuidString }
        try container.encode(entries, forKey: .blocks)
    }
}

/// Reads and writes a Map's Stat Blocks as `<map>.combat/stats.json`.
///
/// Follows `FogStore`'s rules exactly, because they protect the same thing: work a DM
/// typed once and must never lose. A missing file is normal, an unreadable file is
/// reported and left untouched, and an empty document deletes rather than writes.
///
/// Unlike `FogStore` it must create its own directory, as `PartyStore` does.
final class StatsStore {
    /// Thrown when a stats file exists but cannot be read. Deliberately not swallowed:
    /// the alternative is a DM who reopens a Map, sees no hit points, retypes them, and
    /// overwrites the file that would have recovered them.
    struct UnreadableFile: Error {
        let url: URL
        let underlying: Error
    }

    private let fileManager: FileManager

    /// The last failure from `load`, for the UI to surface. Read after a nil return.
    private(set) var lastLoadFailure: UnreadableFile?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// `/maps/dungeon.png` → `/maps/dungeon.combat/`. One folder per Map, holding the
    /// Stat Blocks and every Encounter's Combat Log, so a map directory does not grow
    /// four files per image and deleting a Map's combat history is one gesture.
    static func combatDirectory(forMapAt mapURL: URL) -> URL {
        mapURL.deletingPathExtension().appendingPathExtension("combat")
    }

    static func statsURL(forMapAt mapURL: URL) -> URL {
        combatDirectory(forMapAt: mapURL).appendingPathComponent("stats.json")
    }

    /// The Map's Stat Blocks, or nil when there are none — the normal case for a Map
    /// nobody has fought on. Also nil when the file cannot be read; that leaves
    /// `lastLoadFailure` set and the file on disk untouched.
    func load(forMapAt mapURL: URL) -> StatsDocument? {
        // One store outlives many Maps, so each load starts clean.
        lastLoadFailure = nil
        let url = Self.statsURL(forMapAt: mapURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(StatsDocument.self, from: Data(contentsOf: url))
        } catch {
            lastLoadFailure = UnreadableFile(url: url, underlying: error)
            return nil
        }
    }

    /// Writes the Map's Stat Blocks, or removes the file when there are none.
    func save(_ document: StatsDocument, forMapAt mapURL: URL) throws {
        let url = Self.statsURL(forMapAt: mapURL)
        guard !document.isEmpty else {
            try? fileManager.removeItem(at: url)
            return
        }
        try fileManager.createDirectory(at: Self.combatDirectory(forMapAt: mapURL),
                                        withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
}
