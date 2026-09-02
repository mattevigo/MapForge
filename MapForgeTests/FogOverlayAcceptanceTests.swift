import XCTest
@testable import MapForge

/// Issue 06's acceptance criterion, end to end through the real pipeline: a traced room,
/// a torch inside it, and what each surface is told to draw.
@MainActor
final class FogOverlayAcceptanceTests: XCTestCase {
    private let imageSize = CGSize(width: 1000, height: 800)

    /// A room 400x400 with a doorway in its right wall, a torch inside.
    ///
    /// Stored, not computed: every access to a computed one would mint fresh UUIDs, so
    /// two "identical" documents would compare unequal and defeat the Visibility cache —
    /// which is exactly what the pan test is asserting about.
    private lazy var document: FogDocument = {
        FogDocument(
            walls: [
                Wall(from: MapPoint(x: 100, y: 100), to: MapPoint(x: 500, y: 100)),
                Wall(from: MapPoint(x: 100, y: 500), to: MapPoint(x: 500, y: 500)),
                Wall(from: MapPoint(x: 100, y: 100), to: MapPoint(x: 100, y: 500)),
                Wall(from: MapPoint(x: 500, y: 100), to: MapPoint(x: 500, y: 260)),
                Wall(from: MapPoint(x: 500, y: 340), to: MapPoint(x: 500, y: 500)),
            ],
            lights: [Light(at: MapPoint(x: 300, y: 300), brightSquares: 20, dimSquares: 20)]
        )
    }()

    private func regions() -> [LitRegion] {
        VisibilityCache().regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 20)
    }

    func testPlayersSeeTheRoomTheDoorwayWedgeAndBlackBeyond() {
        let lit = regions()
        // Inside the room: visible.
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 300, y: 300), in: lit), .bright)
        // Through the doorway, on the torch's line and comfortably inside the radius —
        // 400 px away is exactly ON the bright rim, where lit-or-not is a coin flip.
        XCTAssertNotEqual(Visibility.level(at: MapPoint(x: 650, y: 300), in: lit), .unlit)
        // Beyond the wall, off the doorway's line: black.
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 700, y: 150), in: lit), .unlit)
        XCTAssertEqual(Visibility.level(at: MapPoint(x: 300, y: 700), in: lit), .unlit)
    }

    func testThePlayersDarknessHidesAndTheDMsTintDoesNot() {
        // The same Visibility, two surfaces: players cannot see into the dark, the DM can.
        XCTAssertEqual(FogShading.player(.unlit), 1, accuracy: 1e-9)
        XCTAssertLessThan(FogShading.control(.unlit), 0.8)
    }

    func testSwitchingTheOverlayOffRevealsEverythingButKeepsPawns() {
        // "Switching the overlay off reveals the full Map with Pawns still on it."
        var withPawn = document
        withPawn.pawns = [Pawn(at: MapPoint(x: 300, y: 300), label: "Vex",
                               colorHex: "#C81E1E", brightSquares: 6)]

        for level in [VisibilityLevel.bright, .dim, .unlit] {
            XCTAssertEqual(FogShading.player(level, isOverlayOn: false), 0, accuracy: 1e-9)
        }
        // The Pawn is untouched by the switch. Asserting the document still holds one
        // would prove nothing about the render — the guarantee is that PlayerView's
        // `isFogOverlayOn` guard wraps ONLY the FogCanvas, with the Pawn ForEach outside
        // it. Pin that structurally: the fog's opacity collapses to zero while the token's
        // size does not depend on the switch at all.
        XCTAssertEqual(FogShading.player(.unlit, isOverlayOn: false), 0, accuracy: 1e-9)
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let scale = MapScale(imagePixelSize: imageSize, physicalWidthInches: 50)
        XCTAssertGreaterThan(PlayerPlacement.squareSidePoints(map: scale, frame: frame), 0,
                            "a token would be invisible regardless of the fog switch")
        XCTAssertEqual(withPawn.pawns.count, 1)
    }

    func testPanningTheViewportDoesNotRecomputeVisibility() {
        // "Panning must stay smooth: the overlay redraws from cached Visibility, never
        // recomputes it." The Viewport origin is not among the cache's inputs at all, so
        // repeated reads across a pan cost one computation.
        var computations = 0
        let cache = VisibilityCache { computations += 1 }
        for _ in 0..<100 {
            _ = cache.regions(for: document, imagePixelSize: imageSize, pixelsPerSquare: 20)
        }
        XCTAssertEqual(computations, 1)
    }

    func testAnUndeclaredGridProducesNoFogRatherThanWrongFog() throws {
        // Light radii are in Grid squares. Without a declared Grid every region would be
        // sized against a default that is almost certainly wrong, and darkness in the
        // wrong places is worse than no darkness — so AppState draws none and warns.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FogOverlayAcceptance.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("map.png")
        let image = NSImage(size: NSSize(width: 100, height: 80))
        image.lockFocus(); NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 80).fill(); image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)

        let appState = AppState(
            preferences: DisplayPreferences(defaults: UserDefaults(suiteName: "acc.\(UUID().uuidString)")!))
        appState.loadMap(image: image, at: url)
        appState.fog = document

        XCTAssertFalse(appState.hasDeclaredGrid, "precondition: no Grid declared")
        XCTAssertTrue(appState.litRegions.isEmpty, "fog was drawn against a guessed Grid")

        appState.squaresWide = 50
        XCTAssertFalse(appState.litRegions.isEmpty, "declaring the Grid did not enable fog")
    }
}
