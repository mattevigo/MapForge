import Foundation

/// Reads and writes a Map's fog data as `<map>.fog.json` beside the image.
///
/// The app's first *user-authored* persistence — `DisplayPreferences` stores two strings
/// the DM can recreate with one click, whereas a traced room is minutes of work that must
/// never be lost. That asymmetry drives the rules here: a missing file is normal, an
/// unreadable file is reported and left untouched, and an empty document deletes rather
/// than writes.
///
/// Ad-hoc signed with no App Sandbox, so writing next to a user-picked image needs no
/// security-scoped bookmarks. Revisit if sandboxing is ever turned on.
final class FogStore {
    /// Thrown when a fog file exists but cannot be read. Deliberately not swallowed: the
    /// alternative is a DM who reopens a Map, sees no Walls, redraws them, and overwrites
    /// the file that would have recovered them.
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

    /// `/maps/dungeon.png` → `/maps/dungeon.fog.json`. A sibling, so moving a Map and its
    /// fog together keeps them paired.
    static func fogURL(forMapAt mapURL: URL) -> URL {
        mapURL.deletingPathExtension().appendingPathExtension("fog.json")
    }

    /// The Map's fog, or nil when there is none — the normal case for an unauthored Map.
    /// Also nil when the file cannot be read; that leaves `lastLoadFailure` set and the
    /// file on disk untouched.
    func load(forMapAt mapURL: URL) -> FogDocument? {
        // One store outlives many Maps, so each load starts clean: a failure left over
        // from a corrupt Map would attach a stale error to the next good one.
        lastLoadFailure = nil
        let url = Self.fogURL(forMapAt: mapURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(FogDocument.self, from: Data(contentsOf: url))
        } catch {
            lastLoadFailure = UnreadableFile(url: url, underlying: error)
            return nil
        }
    }

    /// Writes the Map's fog, or removes the file when the document is empty — so deleting
    /// the last Wall does not leave the previous ones on disk to reappear next launch.
    func save(_ document: FogDocument, forMapAt mapURL: URL) throws {
        let url = Self.fogURL(forMapAt: mapURL)
        guard !document.isEmpty else {
            try? fileManager.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        // The file is meant to be readable by a human in a text editor — that is the
        // whole reason MapPoint names its units — so pretty-print and keep key order
        // stable, which also keeps diffs meaningful if a DM version-controls their maps.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
}
