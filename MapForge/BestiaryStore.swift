import Foundation

/// Builds the `Bestiary`, the Characters' notes and the `Treasury` by reading every note in
/// the Workspace once (ADR-0023, ADR-0024, ADR-0031). Named for the Bestiary, which it read
/// first; it reads the Treasury too.
///
/// The whole Workspace rather than a folder, because the DM keeps Monsters and Items wherever
/// their notes put them — a reference shelf, a campaign's own creatures, its named NPCs, an
/// Adventure's treasures — in folders whose names are theirs to translate and change. Which
/// fences are not Monsters, the fences say (`StatblockReader`); which notes are Items, their
/// frontmatter says (`ItemReader`).
///
/// Reads and never writes. Synchronous and free of `AppState`, so the caller chooses the
/// thread — `AppState.open` runs it off the main one — and a test can point it at a
/// temporary folder.
enum BestiaryStore {
    /// What one walk over the Workspace's notes finds: its Monsters, and its Characters'
    /// notes (ADR-0024), read together because they are told apart only by their fences —
    /// and its Items, which say what they are in their frontmatter instead (ADR-0031).
    struct Reading: Equatable {
        var bestiary: Bestiary
        var characters: CharacterNotes
        var treasury: Treasury
    }

    /// The Bestiary alone, for a caller that wants nothing else. `read` gives everything the
    /// walk finds, the Treasury included.
    static func load(for workspace: Workspace,
                     fileManager: FileManager = .default) -> Bestiary {
        read(workspace, fileManager: fileManager).bestiary
    }

    /// Every Monster, Character's note and Item in `workspace`, from one walk over its notes.
    static func read(_ workspace: Workspace,
                     fileManager: FileManager = .default) -> Reading {
        let root = workspace.url.path
        var bestiary = Bestiary()
        let walked = files(under: root, fileManager: fileManager)

        // Every fence first, because a Monster may `extend` one in a note further down the
        // path order — a campaign's NPC is a reference Monster with changes (ADR-0023).
        var fences: [(file: String, fields: StatblockReader.Fields)] = []
        var items: [(file: String, reading: ItemReader.Reading)] = []
        for path in walked.notes {
            let url = URL(fileURLWithPath: (root as NSString).appendingPathComponent(path))
            guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
                bestiary.skipped.append(.init(file: path, reason: String(localized: "the note could not be read")))
                continue
            }
            items.append((path, ItemReader.read(markdown, file: path)))
            switch StatblockReader.fields(in: markdown) {
            case .none: continue
            case .unreadable(let reason): bestiary.skipped.append(.init(file: path, reason: reason))
            case .fields(let fields): fences.append((path, fields))
            }
        }

        let bases = Self.bases(among: fences.map(\.fields))
        var names: Set<String> = []
        for fence in fences {
            switch StatblockReader.monster(from: fence.fields, bases: bases) {
            case .notAMonster:
                continue
            case .skipped(let reason):
                bestiary.skipped.append(.init(file: fence.file, reason: reason))
            case .monster(var monster):
                monster.file = fence.file
                monster.distanceUnits = DistanceUnit.named(in: [monster.speed, monster.senses])
                monster.picture = monster.imageLink.map {
                    NotePicture.resolve($0, among: walked.others)
                }
                guard names.insert(monster.name).inserted else {
                    bestiary.skipped.append(.init(
                        file: fence.file, reason: String(localized: "another note already defines “\(monster.name)”")))
                    continue
                }
                bestiary.monsters.append(monster)
            }
        }
        bestiary.monsters.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        // Read in two passes, reported in one order: the vault's.
        bestiary.skipped.sort { $0.file < $1.file }
        return Reading(bestiary: bestiary,
                       characters: characters(among: fences, files: walked.others),
                       treasury: treasury(of: items, files: walked.others))
    }

    /// The Items among the notes' readings, which are in path order, the first by path
    /// winning a name as a Monster's does.
    private static func treasury(of readings: [(file: String, reading: ItemReader.Reading)],
                                 files: [String]) -> Treasury {
        var treasury = Treasury()
        var names: Set<String> = []
        for (file, reading) in readings {
            switch reading {
            case .notAnItem:
                continue
            case .skipped(let reason):
                treasury.skipped.append(.init(file: file, reason: reason))
            case .item(var item):
                item.picture = item.imageLink.map { NotePicture.resolve($0, among: files) }
                guard names.insert(item.name).inserted else {
                    treasury.skipped.append(.init(
                        file: file, reason: String(localized: "another note already defines “\(item.name)”")))
                    continue
                }
                treasury.items.append(item)
            }
        }
        treasury.items.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return treasury
    }

    /// The Characters' notes among the fences, the first by path winning a name as a
    /// Monster's does.
    private static func characters(
        among fences: [(file: String, fields: StatblockReader.Fields)], files: [String]
    ) -> CharacterNotes {
        var characters = CharacterNotes()
        var names: Set<String> = []
        for fence in fences {
            switch StatblockReader.character(from: fence.fields) {
            case .notACharacter:
                continue
            case .skipped(let reason):
                characters.skipped.append(.init(file: fence.file, reason: reason))
            case .character(var note):
                note.file = fence.file
                note.distanceUnits = DistanceUnit.named(in: [note.speed, note.senses])
                note.picture = note.imageLink.map { NotePicture.resolve($0, among: files) }
                guard names.insert(note.name).inserted else {
                    characters.skipped.append(.init(
                        file: fence.file, reason: String(localized: "another note already defines “\(note.name)”")))
                    continue
                }
                characters.notes.append(note)
            }
        }
        characters.notes.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return characters
    }

    /// What `extends` can name: every named fence that is not a Character's, by name, the
    /// first by path winning as it does in the list. Fences kept out of the Bestiary count
    /// too — `bestiary: false` keeps a base out of the search, not out of reach — but only
    /// for names no listed Monster already holds, so a hidden draft never takes the name of
    /// the Monster the DM sees.
    static func bases(among fences: [StatblockReader.Fields]) -> [String: StatblockReader.Fields] {
        var bases: [String: StatblockReader.Fields] = [:]
        let candidates = fences.filter { !StatblockReader.isCharacter($0) }
        for outOfBestiary in [false, true] {
            for fields in candidates where StatblockReader.isOutOfBestiary(fields) == outOfBestiary {
                guard let name = StatblockReader.name(of: fields), bases[name] == nil else { continue }
                bases[name] = fields
            }
        }
        return bases
    }

    /// Every file under `root`, relative to it: the markdown notes in path order — so that
    /// which of two same-named Monsters wins is a rule the DM can predict rather than whatever
    /// the disk returned — and everything else, which is where the pictures a note's `image:`
    /// names are looked for.
    ///
    /// Hidden folders are not entered: `.mapforge` is the app's, `.obsidian` and `.git` are
    /// tools', and Obsidian does not read them either, so no statblock the DM sees lives
    /// there, and no picture it draws. `.git` alone can hold more files than the vault.
    static func files(under root: String,
                      fileManager: FileManager = .default) -> (notes: [String], others: [String]) {
        guard let enumerator = fileManager.enumerator(atPath: root) else { return ([], []) }
        var notes: [String] = []
        var others: [String] = []
        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if name.hasPrefix(".") {
                // A folder's only: on a file — Finder's `.DS_Store` — it skips the rest of
                // the folder the file is in.
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            guard !isDirectory else { continue }
            if (name as NSString).pathExtension.lowercased() == "md" {
                notes.append(path)
            } else {
                others.append(path)
            }
        }
        return (notes.sorted(), others)
    }
}
