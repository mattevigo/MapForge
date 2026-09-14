// Whether the DM can see their own party with nothing plugged in.
//
// Every other UI test in this suite launches with `--test-player-screen auto`, which is why
// none of them caught `.scratch/pawns-not-drawn/`: the preview has two branches, the live
// layers were built on the branch that needs a Player Display, and every test asked for a
// Player Display. A DM prepping on a laptop got the other branch and saw bare artwork.
//
// These tests deliberately do NOT pass that flag.
import XCTest
import AppKit

final class PreviewWithoutDisplayUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// A Map with a Pawn already on it, so the preview has something to fail to draw.
    /// Written as a fog file rather than placed by clicking: the question here is what the
    /// preview draws, not whether placement works, and `FogEditingUITests` covers placement.
    private func fixture() throws -> URL {
        let pixelsWide = 1200, pixelsHigh = 900
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapforge-nodisplay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let map = dir.appendingPathComponent("map.png")
        try rep.representation(using: .png, properties: [:])!.write(to: map)

        let fog = FogDocumentFixture.json(squaresWide: 30)
        try fog.write(to: dir.appendingPathComponent("map.fog.json"), atomically: true, encoding: .utf8)
        return map
    }

    /// No `--test-player-screen`: this is the DM at the kitchen table.
    private func launchWithoutADisplay() throws -> XCUIApplication {
        let map = try fixture()
        let app = XCUIApplication()
        app.launchArguments = ["--test-map", map.path, "--test-squares", "30",
                               "--test-fresh-preferences"]
        app.launch()
        return app
    }

    private func controlWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["control"]
    }

    /// The bug, as the DM met it: three Pawns in the document, and a preview showing none.
    ///
    /// Asserts on the Scene panel first so a failure distinguishes "the fog file did not
    /// load" from "the fog file loaded and the preview ignored it" — the second is the
    /// defect, and without the first assertion a broken fixture reads as a fixed bug.
    func testPawnsAreDrawnOnThePreviewWithNoPlayerDisplay() throws {
        let app = try launchWithoutADisplay()
        let window = controlWindow(app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // The document really does hold the Pawns.
        XCTAssertTrue(app.staticTexts["Kara"].waitForExistence(timeout: 5),
                      "the fixture's Pawns never reached the Scene panel — check the fog file")

        // And the preview really does draw them. `pawn-token-<label>` is set on the token
        // itself in `PawnLayer`, so this asks the preview rather than the panel.
        XCTAssertTrue(window.descendants(matching: .any)["pawn-token-Kara"].waitForExistence(timeout: 5),
                      "Kara is listed in the Scene panel but not drawn on the preview")

        // The Creature too: it takes a different path through the Fog rules, and a fix that
        // only restored Players would still lose every monster.
        XCTAssertTrue(window.descendants(matching: .any)["pawn-token-Ogre"].exists,
                      "the Creature is not drawn on the preview")
    }

    /// The Player Display picker should still say what it always said: this test is about
    /// the preview, and a fix that quietly invented a display would pass the test above
    /// while breaking True Scale.
    func testNoPlayerDisplayIsStillReportedAsNotPresenting() throws {
        let app = try launchWithoutADisplay()
        let window = controlWindow(app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons.firstMatch.waitForExistence(timeout: 5))
    }
}

/// A fog file with a Pawn, a Creature and a Light, written the way the app writes one.
///
/// Hand-rolled JSON rather than the app's encoder because a UI test target cannot see the
/// app's types. `MapPoint` nests under `imagePixels` — a flat `{"x":…,"y":…}` is refused by
/// the decoder and the DM gets the "Could not read this Map's fog" banner instead.
enum FogDocumentFixture {
    static func json(squaresWide: Int) -> String {
        """
        {
          "version": 2,
          "squaresWide": \(squaresWide),
          "walls": [],
          "lights": [
            { "id": "11111111-1111-1111-1111-111111111111",
              "at": { "imagePixels": { "x": 200, "y": 200 } },
              "brightSquares": 4, "dimSquares": 8, "isOn": true }
          ],
          "pawns": [
            { "id": "22222222-2222-2222-2222-222222222222",
              "label": "Kara", "colorHex": "#3366CC",
              "light": { "id": "33333333-3333-3333-3333-333333333333",
                         "at": { "imagePixels": { "x": 300, "y": 300 } },
                         "brightSquares": 6, "dimSquares": 7, "isOn": true },
              "kind": "player", "isHidden": false, "isBig": false },
            { "id": "66666666-6666-6666-6666-666666666666",
              "label": "Ogre", "colorHex": "#66CC33",
              "light": { "id": "77777777-7777-7777-7777-777777777777",
                         "at": { "imagePixels": { "x": 900, "y": 650 } },
                         "brightSquares": 0, "dimSquares": 1, "isOn": true },
              "kind": "creature", "isHidden": false, "isBig": true }
          ]
        }
        """
    }
}
