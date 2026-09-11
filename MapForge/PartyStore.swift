import Foundation

/// Reads and writes the DM's Parties as `parties.json` in Application Support.
///
/// App state, not Map state: a campaign's cast outlives the Map a session happens to be run
/// on, so it cannot live in a `.fog.json` sidecar. See ADR 0007.
///
/// The rules are `FogStore`'s, for the same reason — a roster a DM typed in by hand is work
/// that must never be silently lost. A missing file is normal, an unreadable file is reported
/// and left on disk untouched, and an empty book deletes rather than writes. It differs in
/// one way: this store owns its directory and must create it.
final class PartyStore {
    /// Thrown when the roster exists but cannot be read. Not swallowed: the alternative is a
    /// DM who opens the app, sees no party, retypes it, and overwrites the file that would
    /// have recovered it.
    struct UnreadableFile: Error {
        let url: URL
        let underlying: Error
    }

    private let directory: URL
    private let fileManager: FileManager

    /// The last failure from `load`, for the UI to surface. Read after an empty return.
    private(set) var lastLoadFailure: UnreadableFile?

    /// `~/Library/Application Support/MapForge`. The app is ad-hoc signed with no App
    /// Sandbox, so this needs no security-scoped bookmark — the same footing `FogStore`
    /// stands on.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MapForge")
    }

    init(directory: URL = PartyStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    var fileURL: URL { directory.appendingPathComponent("parties.json") }

    /// The DM's roster, or an empty book when there is none — the normal case on a machine
    /// where no Party has been defined yet. Also empty when the file cannot be read; that
    /// leaves `lastLoadFailure` set and the bytes on disk untouched.
    func load() -> PartyBook {
        lastLoadFailure = nil
        guard fileManager.fileExists(atPath: fileURL.path) else { return PartyBook() }
        do {
            return try JSONDecoder().decode(PartyBook.self, from: Data(contentsOf: fileURL))
        } catch {
            lastLoadFailure = UnreadableFile(url: fileURL, underlying: error)
            return PartyBook()
        }
    }

    /// Writes the roster, or removes the file once the last Party is deleted — so a deleted
    /// Party does not reappear at the next launch.
    func save(_ book: PartyBook) throws {
        guard !book.isEmpty else {
            try? fileManager.removeItem(at: fileURL)
            return
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Readable in a text editor and stable in a diff, as the fog file is: a DM who keeps
        // their campaign in version control should see a one-line change for a rename.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(book).write(to: fileURL, options: .atomic)
    }
}
