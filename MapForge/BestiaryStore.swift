import Foundation

/// `.mapforge/bestiary.json`: which folder of the Workspace holds the DM's Monsters.
///
/// Hand-edited for now, and **never written by the app** — which is why it is its own file
/// rather than a key in `preferences.json`, whose store forgives an unreadable file by
/// overwriting it. A typo here can cost the DM the Bestiary and nothing else. See ADR-0020.
struct BestiaryConfig: Decodable, Equatable {
    /// Relative to the Workspace root, so it travels with the Workspace (ADR-0012).
    var folder: String
}

/// Builds the `Bestiary` by reading the folder `bestiary.json` names.
///
/// Reads and never writes. Synchronous and free of `AppState`, so the caller chooses the
/// thread — `AppState.open` runs it off the main one — and a test can point it at a
/// temporary folder.
enum BestiaryStore {
    static func load(for workspace: Workspace,
                     fileManager: FileManager = .default) -> Bestiary {
        let configName = ".mapforge/\(workspace.bestiaryURL.lastPathComponent)"
        guard fileManager.fileExists(atPath: workspace.bestiaryURL.path) else {
            return Bestiary(unavailable: "No \(configName) in this Workspace.")
        }
        guard let data = try? Data(contentsOf: workspace.bestiaryURL),
              let config = try? JSONDecoder().decode(BestiaryConfig.self, from: data) else {
            return Bestiary(unavailable: "\(configName) could not be read.")
        }
        guard let folder = folderURL(config.folder, in: workspace) else {
            return Bestiary(unavailable: "The Bestiary folder must be inside this Workspace.")
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return Bestiary(unavailable:
                "The Bestiary folder “\(config.folder)” was not found in this Workspace.")
        }
        return read(folder: folder, fileManager: fileManager)
    }

    /// The configured folder as a URL, or nil when it would leave the Workspace.
    ///
    /// Decided on the *standardised* path, so `Bestiario/../../Altrove` is caught as surely as
    /// `../Altrove` — a prefix check on the raw string would pass the first.
    static func folderURL(_ folder: String, in workspace: Workspace) -> URL? {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else { return nil }
        let root = workspace.url.path
        let resolved = (root as NSString).appendingPathComponent(trimmed)
        let standardised = (resolved as NSString).standardizingPath
        guard standardised == root || standardised.hasPrefix(root + "/") else { return nil }
        return URL(fileURLWithPath: standardised)
    }

    /// Every markdown note under `folder`, in path order, so that which of two same-named
    /// Monsters wins is a rule the DM can predict rather than whatever the disk returned.
    private static func read(folder: URL, fileManager: FileManager) -> Bestiary {
        let root = folder.path
        let paths = (fileManager.enumerator(atPath: root)?.allObjects as? [String] ?? [])
            .filter { ($0 as NSString).pathExtension.lowercased() == "md" }
            .sorted()

        var bestiary = Bestiary()
        var names: Set<String> = []
        for path in paths {
            let url = URL(fileURLWithPath: (root as NSString).appendingPathComponent(path))
            guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
                bestiary.skipped.append(.init(file: path, reason: "the note could not be read"))
                continue
            }
            switch StatblockReader.read(markdown) {
            case .notAMonster:
                continue
            case .skipped(let reason):
                bestiary.skipped.append(.init(file: path, reason: reason))
            case .monster(let monster):
                guard names.insert(monster.name).inserted else {
                    bestiary.skipped.append(.init(
                        file: path, reason: "another note already defines “\(monster.name)”"))
                    continue
                }
                bestiary.monsters.append(monster)
            }
        }
        bestiary.monsters.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return bestiary
    }
}
