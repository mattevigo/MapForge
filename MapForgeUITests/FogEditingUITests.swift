// Wall drawing drives real clicks on the preview, which unit tests cannot reach: the
// snapping and chain geometry are tested pure, but whether a click in the window actually
// becomes a Wall is a wiring question. Both previous overlays (GridFitOverlay's corner
// handles, ViewportOverlay's drag) cost a round of debugging in exactly this gap.
import XCTest
import AppKit

final class FogEditingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func fixturePNG(pixelsWide: Int, pixelsHigh: Int) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapforge-walls-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func launchApp() throws -> XCUIApplication {
        let map = try fixturePNG(pixelsWide: 1200, pixelsHigh: 900)
        let app = XCUIApplication()
        app.launchArguments = ["--test-map", map.path, "--test-squares", "30",
                               "--test-player-screen", "auto"]
        app.launch()
        return app
    }

    func testEditFogButtonEntersTheMode() throws {
        let app = try launchApp()
        let draw = app.buttons["Edit Fog…"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5), "Edit Fog… button not found")
        draw.click()

        // The mode's own controls replace the entry buttons.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2), "did not enter Wall mode")
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights"].exists, "fog summary not shown")
    }

    func testClickingPlacesVerticesAndDoubleClickCommitsTheChain() throws {
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let window = app.windows.firstMatch
        // Three points across the lower half of the window, safely inside the preview
        // and clear of the controls above it.
        let first = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        let second = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let third = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))

        first.click()
        second.click()
        third.click()
        third.doubleClick()

        // Three vertices make two Walls. The count label is the observable outcome.
        XCTAssertTrue(app.staticTexts["2 Walls, 0 Lights"].waitForExistence(timeout: 2),
                      "clicks did not become Walls")
    }

    func testCancelRestoresTheWallsFromBeforeTheMode() throws {
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)).click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).doubleClick()
        XCTAssertTrue(app.staticTexts["1 Wall, 0 Lights"].waitForExistence(timeout: 2))

        app.buttons["Cancel"].click()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights"].waitForExistence(timeout: 2),
                      "Cancel did not discard the Walls drawn in the mode")
    }

    func testPlacingALightWithTheLightToolAndTogglingItLive() throws {
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        // Switch the tool: a click then places a Light, not a Wall vertex.
        app.buttons["Lights"].click()
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.7)).click()
        XCTAssertTrue(app.staticTexts["0 Walls, 1 Light"].waitForExistence(timeout: 2),
                      "the click did not place a Light")

        // The live toggle row is available outside the editing mode.
        app.buttons["Done"].click()
        let toggle = app.buttons["1"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2), "no live toggle for the Light")
        toggle.click()
    }
}
