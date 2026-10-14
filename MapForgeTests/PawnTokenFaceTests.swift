import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// What `PawnToken` draws for a Pawn with a Face: the Face, over the whole token, and the
/// colour only when the cut is missing. Rendered offscreen, so no window is needed.
@MainActor
final class PawnTokenFaceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PawnTokenFaceTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// A library holding one all-blue cut, and the Face naming it.
    private func blueFace() throws -> (FaceLibrary, PawnFace) {
        let library = FaceLibrary(directory: root.appendingPathComponent("faces"))
        let picture = try FaceFixture.halves(width: 200, height: 100)
        let face = try library.keep(picture, cut: CGRect(x: 100, y: 0, width: 100, height: 100))
        return (library, face)
    }

    /// The token rendered at 100 points, and the colour at its centre.
    private func centre(of pawn: Pawn, library: FaceLibrary?) throws -> FaceFixture.Colour {
        let renderer = ImageRenderer(content: PawnToken(pawn: pawn, squareSide: 100)
            .environment(\.faceLibrary, library))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return FaceFixture.colour(of: image, x: image.width / 2, y: image.height / 2)
    }

    private func redPawn(face: PawnFace?) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: "", colorHex: "#FF0000", brightSquares: 6,
             kind: .creature, face: face)
    }

    func testAPawnWithAFaceIsDrawnAsItsFace() throws {
        let (library, face) = try blueFace()

        XCTAssertEqual(try centre(of: redPawn(face: face), library: library), .blue)
    }

    func testAPawnWithoutAFaceIsDrawnInItsColour() throws {
        let (library, _) = try blueFace()

        XCTAssertEqual(try centre(of: redPawn(face: nil), library: library), .red)
    }

    func testAMissingCutFallsBackToTheColour() throws {
        let (library, _) = try blueFace()

        XCTAssertEqual(try centre(of: redPawn(face: PawnFace(file: "gone.png", origin: .hand)),
                                  library: library), .red)
    }

    func testWithNoWorkspaceTheColourIsDrawn() throws {
        let (_, face) = try blueFace()

        XCTAssertEqual(try centre(of: redPawn(face: face), library: nil), .red)
    }
}
