import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// What `PawnToken` draws for a Pawn with a Face: the Face, over the whole token, and the
/// colour only when the cut is missing; and its label over the Face only while the DM's
/// pointer rests on it. Rendered offscreen, so no window is needed.
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

    /// The token rendered at 100 points.
    private func render(_ token: PawnToken, library: FaceLibrary?) throws -> CGImage {
        let renderer = ImageRenderer(content: token.environment(\.faceLibrary, library))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    /// The colour at the centre of the token.
    private func centre(of pawn: Pawn, library: FaceLibrary?) throws -> FaceFixture.Colour {
        let image = try render(PawnToken(pawn: pawn, squareSide: 100), library: library)
        return FaceFixture.colour(of: image, x: image.width / 2, y: image.height / 2)
    }

    private func redPawn(face: PawnFace?, label: String = "") -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: label, colorHex: "#FF0000", brightSquares: 6,
             kind: .creature, face: face)
    }

    /// How many of the token's pixels are the label's white.
    private func labelPixels(of pawn: Pawn, library: FaceLibrary, isHovered: Bool,
                             isForPlayers: Bool = false) throws -> Int {
        let image = try render(PawnToken(pawn: pawn, squareSide: 100,
                                         isForPlayers: isForPlayers, isHovered: isHovered),
                               library: library)
        var count = 0
        for x in 0..<image.width {
            for y in 0..<image.height where FaceFixture.colour(of: image, x: x, y: y) == .white {
                count += 1
            }
        }
        return count
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

    // MARK: The label over a Face

    func testAFacesLabelIsNotDrawnWhileNothingPointsAtIt() throws {
        let (library, face) = try blueFace()

        XCTAssertEqual(try labelPixels(of: redPawn(face: face, label: "W"), library: library,
                                       isHovered: false), 0)
    }

    func testAFacesLabelIsDrawnOverItWhileThePointerRestsOnIt() throws {
        let (library, face) = try blueFace()

        XCTAssertGreaterThan(try labelPixels(of: redPawn(face: face, label: "W"),
                                             library: library, isHovered: true), 0)
    }

    // MARK: A Treasure's Face on the Player Display

    private func chest(at point: MapPoint = MapPoint(x: 0, y: 0), face: PawnFace?) -> Pawn {
        Pawn(at: point, label: "Bo1", colorHex: "#FF0000", brightSquares: 0, kind: .treasure,
             itemName: "Borsa", face: face)
    }

    /// The table sees the Item's picture in the Treasure's rounded square, not in a disc: near
    /// a corner, where a disc has already curved away, the square still shows the Face.
    func testThePlayerDisplayDrawsATreasuresFaceInItsRoundedSquare() throws {
        let (library, cut) = try blueFace()
        let face = PawnFace(file: cut.file, origin: .item)
        let token = PawnToken(pawn: chest(face: face), squareSide: 100, isForPlayers: true)

        let image = try render(token, library: library)

        XCTAssertEqual(FaceFixture.colour(of: image, x: 50, y: 50), .blue)
        XCTAssertEqual(FaceFixture.colour(of: image, x: 12, y: 12), .blue)
        var creature = chest(face: face)
        creature.kind = .creature
        let disc = try render(PawnToken(pawn: creature, squareSide: 100, isForPlayers: true),
                              library: library)
        XCTAssertNotEqual(FaceFixture.colour(of: disc, x: 12, y: 12), .blue)
    }

    /// A Face hides nothing and reveals nothing: a Treasure wearing one is hidden from the
    /// table exactly as its token would be — by darkness, by the DM's hiding, by Solo Sight.
    func testATreasureWearingAFaceIsHiddenAsItsTokenIs() {
        let face = PawnFace(file: "borsa.png", origin: .item)
        let lit = VisibilityCache().regions(
            for: FogDocument(lights: [Light(at: MapPoint(x: 300, y: 300),
                                            brightSquares: 5, dimSquares: 5)]),
            imagePixelSize: CGSize(width: 1000, height: 800), pixelsPerSquare: 20,
            soloSightPawnID: nil)
        func shows(_ pawn: Pawn, solo: Pawn.ID? = nil) -> Bool {
            PlayerVisibility.showsToPlayers(pawn: pawn, regions: lit, isFogOverlayOn: true,
                                            hasVisibility: true, soloSightPawnID: solo)
        }
        let inTheLight = chest(at: MapPoint(x: 300, y: 300), face: face)
        var hidden = inTheLight
        hidden.isHidden = true

        XCTAssertTrue(shows(inTheLight))
        XCTAssertFalse(shows(chest(at: MapPoint(x: 900, y: 700), face: face)), "in the dark")
        XCTAssertFalse(shows(hidden), "hidden by the DM")
        XCTAssertFalse(shows(chest(at: MapPoint(x: 900, y: 700), face: face), solo: UUID()),
                       "outside what the isolated Pawn sees")
    }

    func testThePlayerDisplayNeverDrawsAFacesLabel() throws {
        let (library, face) = try blueFace()

        XCTAssertEqual(try labelPixels(of: redPawn(face: face, label: "W"), library: library,
                                       isHovered: true, isForPlayers: true), 0)
    }
}
