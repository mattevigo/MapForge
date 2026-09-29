import Foundation

/// Builds the `Bestiary` by reading the folder `WorkspaceConfig.bestiaryStatBlockPath` names.
///
/// Reads and never writes. Synchronous and free of `AppState`, so the caller chooses the
/// thread — `AppState.open` runs it off the main one — and a test can point it at a
/// temporary folder.
enum BestiaryStore {
    static func load(for workspace: Workspace,
                     fileManager: FileManager = .default) -> Bestiary {
        let configName = ".mapforge/\(workspace.configURL.lastPathComponent)"
        let config: WorkspaceConfig
        switch WorkspaceConfig.read(from: workspace, fileManager: fileManager) {
        case .success(let read): config = read
        case .failure(.missing):
            return Bestiary(unavailable: String(localized: "No \(configName) in this Workspace."))
        case .failure(.malformed):
            return Bestiary(unavailable: String(localized: "\(configName) could not be read."))
        }
        // A configuration written for some other setting: a DM with no Bestiary, not a
        // broken file.
        guard let path = config.bestiaryStatBlockPath else {
            return Bestiary(unavailable: String(localized: "No bestiaryStatBlockPath in \(configName)."))
        }
        guard let folder = folderURL(path, in: workspace) else {
            return Bestiary(unavailable: String(localized: "bestiaryStatBlockPath must be a folder inside this Workspace, written relative to it — “03_Bestiario”, not a full path."))
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return Bestiary(unavailable:
                String(localized: "The Bestiary folder “\(path)” was not found in this Workspace."))
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
        // Both sides standardised, or a root spelled `/private/…` would disown its own
        // folders. `Workspace.init` already does it; this does not lean on that.
        let root = (workspace.url.path as NSString).standardizingPath
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
                bestiary.skipped.append(.init(file: path, reason: String(localized: "the note could not be read")))
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
                        file: path, reason: String(localized: "another note already defines “\(monster.name)”")))
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
