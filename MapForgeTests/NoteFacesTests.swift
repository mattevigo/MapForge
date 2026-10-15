import AppKit
import XCTest
@testable import MapForge

/// The cut each Monster's picture is given: made once, the centred square, kept in the
/// Workspace and shared by every Pawn that takes the Monster's Face — and made again only when
/// the note names another picture, or the Monster is another Monster (ADR-0028).
final class NoteFacesTests: XCTestCase {
    private var root: URL!
    private var library: FaceLibrary!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NoteFacesTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        library = FaceLibrary(directory: root.appendingPathComponent(".mapforge/faces"))
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// A 300 × 100 picture, red on the left half and blue on the right, at `path`.
    @discardableResult
    private func picture(_ path: String) throws -> String {
        let url = root.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try FaceFixture.writePNG(try FaceFixture.halves(width: 300, height: 100), to: url)
        return path
    }

    private func nothic(picture: NotePicture?) -> Monster {
        var monster = Monster(name: "Nothic")
        monster.picture = picture
        return monster
    }

    private func keptFiles() throws -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: library.directory.path)) ?? []
    }

    // MARK: The cut

    func testTheFirstFaceIsTheCentredSquareOfThePicture() throws {
        let path = try picture("Allegati/Nothic.png")
        var faces = NoteFaces()

        let face = try XCTUnwrap(faces.face(for: nothic(picture: .found(path)),
                                            in: root, library: library))

        XCTAssertEqual(face.origin, .monster)
        XCTAssertEqual(faces.monsters["Nothic"]?.picture, path)
        XCTAssertEqual(faces.monsters["Nothic"]?.square, CGRect(x: 100, y: 0, width: 100, height: 100))
        let kept = try XCTUnwrap(FacePicture.load(library.directory.appendingPathComponent(face.file)))
        XCTAssertEqual(kept.width, 100)
    }

    func testEveryPawnTakingTheMonstersFaceSharesOneCut() throws {
        let path = try picture("Allegati/Nothic.png")
        var faces = NoteFaces()
        let first = faces.face(for: nothic(picture: .found(path)), in: root, library: library)

        let second = faces.face(for: nothic(picture: .found(path)), in: root, library: library)

        XCTAssertEqual(second, first)
        XCTAssertEqual(try keptFiles().count, 1)
    }

    /// A new picture in the note reaches the Pawns that take it afterwards.
    func testAnotherPictureInTheNoteIsCutAfresh() throws {
        var faces = NoteFaces()
        let old = faces.face(for: nothic(picture: .found(try picture("Nothic.png"))),
                             in: root, library: library)

        let new = faces.face(for: nothic(picture: .found(try picture("Nuovo/Nothic.png"))),
                             in: root, library: library)

        XCTAssertNotNil(new)
        XCTAssertNotEqual(new?.file, old?.file)
        XCTAssertEqual(faces.monsters["Nothic"]?.picture, "Nuovo/Nothic.png")
    }

    /// Renamed in the notes, a Monster is another Monster, and its cut starts again.
    func testAMonsterOfAnotherNameHasItsOwnCut() throws {
        let path = try picture("Nothic.png")
        var faces = NoteFaces()
        let old = faces.face(for: nothic(picture: .found(path)), in: root, library: library)
        var renamed = nothic(picture: .found(path))
        renamed.name = "Nothic Antico"

        let new = faces.face(for: renamed, in: root, library: library)

        XCTAssertNotEqual(new?.file, old?.file)
        XCTAssertNotNil(faces.monsters["Nothic"])
    }

    func testACutThatHasGoneIsCutAgain() throws {
        let path = try picture("Nothic.png")
        var faces = NoteFaces()
        let old = try XCTUnwrap(faces.face(for: nothic(picture: .found(path)),
                                           in: root, library: library))
        try fileManager.removeItem(at: library.directory.appendingPathComponent(old.file))

        let new = try XCTUnwrap(faces.face(for: nothic(picture: .found(path)),
                                           in: root, library: library))

        XCTAssertTrue(fileManager.fileExists(
            atPath: library.directory.appendingPathComponent(new.file).path))
    }

    // MARK: No Face

    func testAMonsterWhoseNoteNamesNoPictureHasNoFace() {
        var faces = NoteFaces()

        XCTAssertNil(faces.face(for: nothic(picture: nil), in: root, library: library))
        XCTAssertNil(faces.face(for: nothic(picture: .missing(link: "Nothic.png")),
                                in: root, library: library))
        XCTAssertNil(faces.face(for: nothic(picture: .ambiguous(link: "Nothic.png")),
                                in: root, library: library))
        XCTAssertTrue(faces.monsters.isEmpty)
    }

    func testAFileThatIsNoPictureGivesNoFace() throws {
        try Data("not a picture".utf8).write(to: root.appendingPathComponent("Nothic.png"))
        var faces = NoteFaces()

        XCTAssertNil(faces.face(for: nothic(picture: .found("Nothic.png")),
                                in: root, library: library))
    }

    // MARK: On disk

    func testTheCutsSurviveARelaunch() throws {
        let store = NoteFacesStore(directory: root.appendingPathComponent(".mapforge"))
        var faces = NoteFaces()
        _ = faces.face(for: nothic(picture: .found(try picture("Nothic.png"))),
                       in: root, library: library)

        try store.save(faces)

        XCTAssertEqual(store.load(), faces)
    }

    func testNoCutsYetIsNone() {
        XCTAssertEqual(NoteFacesStore(directory: root.appendingPathComponent(".mapforge")).load(),
                       NoteFaces())
    }

    /// Every cut here can be made again from the notes, so a damaged file costs nothing a
    /// DM typed: it is read as none and replaced at the next cut.
    func testAnUnreadableFileIsReadAsNoCuts() throws {
        let directory = root.appendingPathComponent(".mapforge")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: directory.appendingPathComponent("note-faces.json"))

        XCTAssertEqual(NoteFacesStore(directory: directory).load(), NoteFaces())
    }

    // MARK: A Character's note

    private func durgasNote(picture: NotePicture?) -> CharacterNote {
        var note = CharacterNote(name: "Durga Pietraferma")
        note.picture = picture
        return note
    }

    /// Cut once for that Character: kept under the Character, not under its note, so two
    /// Characters reading one note are two cuts.
    func testACharactersNotePictureIsCutOnceForThatCharacter() throws {
        let path = try picture("Personaggi/Durga.png")
        let durga = PartyCharacter(name: "Durga")
        var faces = NoteFaces()

        let first = try XCTUnwrap(faces.face(for: durga, note: durgasNote(picture: .found(path)),
                                             in: root, library: library))
        let second = faces.face(for: durga, note: durgasNote(picture: .found(path)),
                                in: root, library: library)

        XCTAssertEqual(second, first)
        XCTAssertEqual(first.origin, .character)
        XCTAssertEqual(faces.characters[durga.id.uuidString]?.square,
                       CGRect(x: 100, y: 0, width: 100, height: 100))
        XCTAssertTrue(faces.monsters.isEmpty)
    }

    func testACharacterWhoseNoteNamesNoPictureHasNoNoteFace() {
        var faces = NoteFaces()

        XCTAssertNil(faces.face(for: PartyCharacter(name: "Durga"), note: durgasNote(picture: nil),
                                in: root, library: library))
    }
}
