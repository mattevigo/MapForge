import CoreGraphics
import Foundation

/// The cut the app made from each Monster's picture, and from each Character's note's: which
/// picture, which square of it, and the kept file every Pawn that takes the Face names
/// (ADR-0028).
///
/// Cut **once per Monster**, so four Goblins share one file, and keyed by the Monster's name,
/// as a Pawn remembers its Monster: a Monster renamed in the notes is another Monster to the
/// app, and its cut starts again. Cut **once per Character** too, keyed by its id, for as long
/// as the DM has cut no Face for it. Cut **once per Item**, keyed by its name, exactly as a
/// Monster's is (ADR-0031). The cut starts as the centred square, until the DM cuts
/// another. It is made again when the note names another picture — a new picture reaches the
/// Pawns that take the Face afterwards, never those already on a Map, which keep the copy they
/// were given.
struct NoteFaces: Codable, Equatable {
    static let current = 1

    var monsters: [String: Cut] = [:]
    /// By the Character's id rather than its note's name: cut once for that Character, as a
    /// Face cut by hand for it would be, so two Characters reading one note are two cuts.
    var characters: [String: Cut] = [:]
    /// By the Item's name, as a Treasure remembers its Item. Absent from files written before
    /// Items gave Faces, which read as no cuts.
    var items: [String: Cut] = [:]

    /// One Monster's, Character's or Item's cut.
    struct Cut: Codable, Equatable {
        /// The picture it was cut from, relative to the Workspace root.
        var picture: String
        /// The square, in the picture's pixels with the origin at its top left.
        var square: CGRect
        /// The kept cut's file name in `.mapforge/faces/`.
        var file: String

        private enum CodingKeys: String, CodingKey {
            case picture, x, y, side, file
        }

        init(picture: String, square: CGRect, file: String) {
            self.picture = picture
            self.square = square
            self.file = file
        }

        /// `x`, `y` and `side` rather than a rectangle: the cut is always square, and a DM
        /// reading the file sees three numbers rather than two nested pairs.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            picture = try container.decode(String.self, forKey: .picture)
            let side = try container.decode(CGFloat.self, forKey: .side)
            square = CGRect(x: try container.decode(CGFloat.self, forKey: .x),
                         y: try container.decode(CGFloat.self, forKey: .y),
                         width: side, height: side)
            file = try container.decode(String.self, forKey: .file)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(picture, forKey: .picture)
            try container.encode(square.minX, forKey: .x)
            try container.encode(square.minY, forKey: .y)
            try container.encode(square.width, forKey: .side)
            try container.encode(file, forKey: .file)
        }
    }

    init(monsters: [String: Cut] = [:], characters: [String: Cut] = [:],
         items: [String: Cut] = [:]) {
        self.monsters = monsters
        self.characters = characters
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case version, monsters, characters, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monsters = try container.decodeIfPresent([String: Cut].self, forKey: .monsters) ?? [:]
        characters = try container.decodeIfPresent([String: Cut].self, forKey: .characters) ?? [:]
        items = try container.decodeIfPresent([String: Cut].self, forKey: .items) ?? [:]
    }

    /// The version is stamped, never echoed, as every file this app writes stamps its own.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.current, forKey: .version)
        try container.encode(monsters, forKey: .monsters)
        try container.encode(characters, forKey: .characters)
        try container.encode(items, forKey: .items)
    }

    /// The Face a Pawn takes from `monster`, cutting it now when there is no cut of the
    /// picture the note names — or nil when the Monster has no usable picture.
    ///
    /// `root` is the Workspace's folder, which the picture's path is relative to.
    mutating func face(for monster: Monster, in root: URL, library: FaceLibrary) -> PawnFace? {
        face(of: monster.picture, at: \.monsters, key: monster.name, origin: .monster,
             in: root, library: library)
    }

    /// The Face a Treasure takes from `item`, cut now as a Monster's is — or nil when the Item
    /// has no usable picture.
    mutating func face(for item: Item, in root: URL, library: FaceLibrary) -> PawnFace? {
        face(of: item.picture, at: \.items, key: item.name, origin: .item,
             in: root, library: library)
    }

    /// The Face `character` takes from its `note`'s picture, cut now as a Monster's is.
    mutating func face(for character: PartyCharacter, note: CharacterNote, in root: URL,
                       library: FaceLibrary) -> PawnFace? {
        face(of: note.picture, at: \.characters, key: character.id.uuidString,
             origin: .character, in: root, library: library)
    }

    /// The cut of `character`'s note's picture if one is already kept — never cutting one, so
    /// it can be asked while SwiftUI draws.
    func keptFace(for character: PartyCharacter, note: CharacterNote,
                  library: FaceLibrary) -> PawnFace? {
        keptFace(of: note.picture, at: \.characters, key: character.id.uuidString,
                 origin: .character, library: library)
    }

    /// The cut of `picture` kept under `key` in `cuts`, or nil when there is none of it.
    private func keptFace(of picture: NotePicture?,
                          at cuts: WritableKeyPath<NoteFaces, [String: Cut]>,
                          key: String, origin: PawnFace.Origin,
                          library: FaceLibrary) -> PawnFace? {
        guard let path = picture?.path, let kept = self[keyPath: cuts][key],
              kept.picture == path, library.holds(kept.file) else { return nil }
        return PawnFace(file: kept.file, origin: origin)
    }

    /// The cut of `picture` kept under `key` in `cuts`, made now if there is none of it.
    private mutating func face(of picture: NotePicture?,
                               at cuts: WritableKeyPath<NoteFaces, [String: Cut]>,
                               key: String, origin: PawnFace.Origin,
                               in root: URL, library: FaceLibrary) -> PawnFace? {
        if let kept = keptFace(of: picture, at: cuts, key: key, origin: origin,
                               library: library) {
            return kept
        }
        guard let path = picture?.path, let image = FacePicture.load(root.appendingPathComponent(path)) else { return nil }
        let square = FaceCut.centredSquare(in: image.pixelSize)
        guard let kept = try? library.keep(image, cut: square) else { return nil }
        self[keyPath: cuts][key] = Cut(picture: path, square: square, file: kept.file)
        return PawnFace(file: kept.file, origin: origin)
    }
}

/// Reads and writes `NoteFaces` as `note-faces.json` in a Workspace's `.mapforge/`.
///
/// Forgiving, as `WorkspacePreferences` is and unlike `PartyStore`: every cut in it can be
/// made again from the notes, so a file that cannot be read costs nothing the DM typed. It is
/// read as no cuts, and replaced at the next one.
final class NoteFacesStore {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    var fileURL: URL { directory.appendingPathComponent("note-faces.json") }

    func load() -> NoteFaces {
        guard let data = try? Data(contentsOf: fileURL),
              let faces = try? JSONDecoder.workspace.decode(NoteFaces.self, from: data) else {
            return NoteFaces()
        }
        return faces
    }

    func save(_ faces: NoteFaces) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.workspace.encode(faces).write(to: fileURL, options: .atomic)
    }
}
