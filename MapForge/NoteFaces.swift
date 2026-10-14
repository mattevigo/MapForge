import CoreGraphics
import Foundation

/// The cut the app made from each Monster's picture: which picture, which square of it, and
/// the kept file every Pawn that takes the Monster's Face names (ADR-0028).
///
/// Cut **once per Monster**, so four Goblins share one file, and keyed by the Monster's name,
/// as a Pawn remembers its Monster: a Monster renamed in the notes is another Monster to the
/// app, and its cut starts again. The cut starts as the centred square, until the DM cuts
/// another. It is made again when the note names another picture — a new picture reaches the
/// Pawns that take the Face afterwards, never those already on a Map, which keep the copy they
/// were given.
struct NoteFaces: Codable, Equatable {
    static let current = 1

    var monsters: [String: Cut] = [:]

    /// One Monster's cut.
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

    init(monsters: [String: Cut] = [:]) {
        self.monsters = monsters
    }

    private enum CodingKeys: String, CodingKey {
        case version, monsters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monsters = try container.decodeIfPresent([String: Cut].self, forKey: .monsters) ?? [:]
    }

    /// The version is stamped, never echoed, as every file this app writes stamps its own.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.current, forKey: .version)
        try container.encode(monsters, forKey: .monsters)
    }

    /// The Face a Pawn takes from `monster`, cutting it now when there is no cut of the
    /// picture the note names — or nil when the Monster has no usable picture.
    ///
    /// `root` is the Workspace's folder, which the picture's path is relative to.
    mutating func face(for monster: Monster, in root: URL, library: FaceLibrary) -> PawnFace? {
        guard let path = monster.picture?.path else { return nil }
        if let kept = monsters[monster.name], kept.picture == path, library.holds(kept.file) {
            return PawnFace(file: kept.file, origin: .monster)
        }
        guard let picture = FacePicture.load(root.appendingPathComponent(path)) else { return nil }
        let square = FaceCut.centredSquare(in: picture.pixelSize)
        guard let kept = try? library.keep(picture, cut: square) else { return nil }
        monsters[monster.name] = Cut(picture: path, square: square, file: kept.file)
        return PawnFace(file: kept.file, origin: .monster)
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
