import Foundation

/// Shared naming for the JSONL files in a Map's combat folder.
enum CombatLogFile {
    static let fileExtension = "jsonl"

    /// `2026-09-11T143200Z.jsonl` — sortable as text, unique to the second, and legible.
    /// Colons are avoided: they are legal in a POSIX filename and a lifetime of trouble in
    /// every tool that handles one.
    static func name(startedAt date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(formatter.string(from: date)).\(fileExtension)"
    }

    /// The encoder every Log line is written with.
    ///
    /// Deliberately *not* pretty-printed, unlike every other store in this app: a newline
    /// inside an object would split it across two lines and the format would stop meaning
    /// anything. `.sortedKeys` keeps a line stable between runs, and `.withoutEscapingSlashes`
    /// keeps a DM's note readable.
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

/// Appends lines to one Encounter's Combat Log.
///
/// Append-only, one line per call, flushed on every call. A Turn ending is the durability
/// boundary the whole format is built on — see
/// `docs/adr/0008-combat-is-an-append-only-turn-log.md` — so nothing here is debounced and
/// nothing is ever read back and rewritten.
final class CombatLogWriter {
    /// The file this writer appends to. One per Encounter, named for when it started.
    let url: URL

    private let handle: FileHandle

    init(forMapAt mapURL: URL, startedAt: Date = Date(),
         fileManager: FileManager = .default) throws {
        let directory = StatsStore.combatDirectory(forMapAt: mapURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(CombatLogFile.name(startedAt: startedAt))
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    /// Reopens an existing Log to append to it — the writer a resumed fight needs.
    ///
    /// Seeks to the end and adds to what is there. A Log is never rewritten, so picking one
    /// up again is the same operation as starting it, minus creating the file.
    init(reopening url: URL) throws {
        self.url = url
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    deinit { try? handle.close() }

    /// Appends one line and flushes it. A crash after this returns has lost nothing.
    func append(_ line: LogLine) throws {
        var data = try CombatLogFile.encoder().encode(line)
        data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func close() throws {
        try handle.close()
    }
}

/// Reads a Combat Log back.
struct CombatLogReader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Every line of a Log, in the order they were written.
    ///
    /// A **truncated or malformed final line is dropped, not an error**: that is the crash
    /// case ADR-0008 accepts, and refusing to open the file would lose a whole session to
    /// save the last Turn of it. An absent file reads as no lines — a Map nobody has
    /// fought on.
    func read(at url: URL) throws -> [LogLine] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = CombatLogFile.decoder()
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(LogLine.self, from: Data($0.utf8)) }
    }

    /// Every Encounter fought on a Map, oldest first. The filenames sort as text because
    /// `CombatLogFile.name` is built so they do.
    func logURLs(forMapAt mapURL: URL) -> [URL] {
        let directory = StatsStore.combatDirectory(forMapAt: mapURL)
        let contents = (try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == CombatLogFile.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The most recent Encounter on a Map — the one to resume if it never ended.
    func newestLogURL(forMapAt mapURL: URL) -> URL? {
        logURLs(forMapAt: mapURL).last
    }
}
