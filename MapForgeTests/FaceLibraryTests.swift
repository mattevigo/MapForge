import AppKit
import XCTest
@testable import MapForge

/// Keeping a cut in the Workspace and reading it back. The app keeps the square, never the
/// picture it was cut from (ADR-0028).
final class FaceLibraryTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FaceLibraryTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private var facesDirectory: URL { root.appendingPathComponent(".mapforge/faces") }

    func testTheKeptFileIsTheCutSquare() throws {
        // Red on the left half, blue on the right: a cut from the right half is all blue.
        let picture = try FaceFixture.halves(width: 400, height: 300)
        let library = FaceLibrary(directory: facesDirectory)

        let face = try library.keep(picture, cut: CGRect(x: 250, y: 50, width: 100, height: 100))

        XCTAssertEqual(face.origin, .hand)
        let kept = try XCTUnwrap(FacePicture.load(facesDirectory.appendingPathComponent(face.file)))
        XCTAssertEqual(kept.width, 100)
        XCTAssertEqual(kept.height, 100)
        XCTAssertEqual(FaceFixture.colour(of: kept, x: 50, y: 50), .blue)
    }

    func testTheCutIsReadBackFromTheWorkspaceAlone() throws {
        // The picture is gone after the cut — moved, deleted — and the Face is not.
        let pictureURL = root.appendingPathComponent("Goblin.png")
        try FaceFixture.writePNG(try FaceFixture.halves(width: 200, height: 200), to: pictureURL)
        let picture = try XCTUnwrap(FacePicture.load(pictureURL))
        let face = try FaceLibrary(directory: facesDirectory)
            .keep(picture, cut: FaceCut.centredSquare(in: CGSize(width: 200, height: 200)))

        try fileManager.removeItem(at: pictureURL)

        // A fresh library, as after a relaunch: nothing cached from the cut.
        XCTAssertNotNil(FaceLibrary(directory: facesDirectory).image(for: face))
    }

    func testALargeCutIsKeptAtTokenSize() throws {
        // A token is never drawn larger than a few hundred points; a 4000-pixel square is
        // weight in the Workspace and nothing on the screen.
        let picture = try FaceFixture.halves(width: 2000, height: 2000)

        let face = try FaceLibrary(directory: facesDirectory)
            .keep(picture, cut: CGRect(x: 0, y: 0, width: 2000, height: 2000))

        let kept = FacePicture.load(facesDirectory.appendingPathComponent(face.file))
        XCTAssertEqual(kept?.width, FaceLibrary.keptSide)
        XCTAssertEqual(kept?.height, FaceLibrary.keptSide)
    }

    func testEveryCutIsItsOwnFile() throws {
        let picture = try FaceFixture.halves(width: 200, height: 200)
        let library = FaceLibrary(directory: facesDirectory)
        let cut = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertNotEqual(try library.keep(picture, cut: cut).file,
                          try library.keep(picture, cut: cut).file)
    }

    func testAMissingCutGivesNoImage() {
        // The Pawn is then drawn in its colour, and loses nothing else.
        XCTAssertNil(FaceLibrary(directory: facesDirectory)
            .image(for: PawnFace(file: "gone.png", origin: .hand)))
    }

    func testAFaceCannotNameAFileOutsideTheFolder() throws {
        // The fog file is the DM's to edit by hand; a name is a name, never a path.
        let outside = root.appendingPathComponent(".mapforge/secret.png")
        try fileManager.createDirectory(at: outside.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try FaceFixture.writePNG(try FaceFixture.halves(width: 10, height: 10), to: outside)

        XCTAssertNil(FaceLibrary(directory: facesDirectory)
            .image(for: PawnFace(file: "../secret.png", origin: .hand)))
    }
}
