import Foundation

/// Builds the `Bestiary` by reading every note in the Workspace (ADR-0023).
///
/// The whole Workspace rather than a folder, because the DM keeps Monsters wherever their
/// notes put them — a reference shelf, a campaign's own creatures, its named NPCs — in
/// folders whose names are theirs to translate and change. Which fences are not Monsters, the
/// fences say (`StatblockReader`).
///
/// Reads and never writes. Synchronous and free of `AppState`, so the caller chooses the
/// thread — `AppState.open` runs it off the main one — and a test can point it at a
/// temporary folder.
enum BestiaryStore {
    static func load(for workspace: Workspace,
                     fileManager: FileManager = .default) -> Bestiary {
        let root = workspace.url.path
        var bestiary = Bestiary()
        var names: Set<String> = []
        for path in notes(under: root, fileManager: fileManager) {
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

    /// Every markdown note under `root`, relative to it, in path order — so that which of two
    /// same-named Monsters wins is a rule the DM can predict rather than whatever the disk
    /// returned.
    ///
    /// Hidden folders are not entered: `.mapforge` is the app's, `.obsidian` and `.git` are
    /// tools', and Obsidian does not read them either, so no statblock the DM sees lives
    /// there. `.git` alone can hold more files than the vault.
    static func notes(under root: String, fileManager: FileManager = .default) -> [String] {
        guard let enumerator = fileManager.enumerator(atPath: root) else { return [] }
        var paths: [String] = []
        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }
            if (name as NSString).pathExtension.lowercased() == "md" {
                paths.append(path)
            }
        }
        return paths.sorted()
    }
}
