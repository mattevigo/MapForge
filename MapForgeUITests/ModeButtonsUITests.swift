// Regression tests: the Control Window's buttons must stay clickable with the
// Player Display mirror active. SwiftUI's .clipped() masks drawing only — an
// overflowing mirror Image that participates in hit-testing swallows clicks on
// every control above the preview (only for maps that overflow the Player
// Display, which is why small maps were immune). The app loads a fixture map and
// presents on the built-in screen via the --test-map / --test-player-screen seams,
// so these run without a TV attached.
import XCTest
import AppKit

final class ModeButtonsUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Writes a PNG with the given true pixel size to a temp path. The content is
    /// deliberately asymmetric: the zoom and pan tests compare rendered pixels, and a
    /// uniform or repeating fill looks unchanged after a pan, failing against code
    /// that works.
    private func fixturePNG(pixelsWide: Int, pixelsHigh: Int) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        // One big off-centre landmark, so any pan visibly changes the render.
        NSColor.black.setFill()
        NSRect(x: pixelsWide / 8, y: pixelsHigh / 6,
               width: pixelsWide / 3, height: pixelsHigh / 3).fill()
        NSColor.white.setFill()
        NSRect(x: pixelsWide * 5 / 8, y: pixelsHigh / 2,
               width: pixelsWide / 5, height: pixelsHigh / 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapforge-uitest-\(pixelsWide)x\(pixelsHigh).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func launchApp(squares: Double, pixelsWide: Int, pixelsHigh: Int) throws -> XCUIApplication {
        let map = try fixturePNG(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh)
        let app = XCUIApplication()
        app.launchArguments = ["--test-map", map.path, "--test-squares", String(squares),
                               "--test-player-screen", "auto"]
        app.launch()
        return app
    }

    /// A map that overflows the Player Display on both axes (60 squares = 60 in
    /// wide) renders the mirror with an Image frame far larger than the preview;
    /// both mode buttons must still respond.
    func testModeButtonsClickableWithOverflowingMap() throws {
        let app = try launchApp(squares: 60, pixelsWide: 3000, pixelsHigh: 2000)

        let pan = app.buttons["Pan Viewport…"]
        XCTAssertTrue(pan.waitForExistence(timeout: 5), "Pan Viewport… button not found")
        XCTAssertTrue(pan.isEnabled, "Pan Viewport… disabled with an overflowing map")
        pan.click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2),
                      "Pan Viewport… click did not enter Viewport mode")
        app.buttons["Cancel"].click()

        let fit = app.buttons["Fit Grid…"]
        XCTAssertTrue(fit.waitForExistence(timeout: 2), "Fit Grid… button not found")
        fit.click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2),
                      "Fit Grid… click did not enter Grid Fit mode")
        app.buttons["Cancel"].click()
    }

    /// Scroll-to-zoom must actually reach the preview. This caught two real failures:
    /// an NSViewRepresentable catcher inside Grid Fit's .position()-based ZStack never
    /// gets a non-zero frame (so never receives events), and a hitTest override that
    /// returned nil muted scrollWheel dispatch entirely. Compares the rendered window
    /// before and after, because both bugs left every button working and only the
    /// pixels unchanged.
    func testScrollZoomChangesThePreview() throws {
        let app = try launchApp(squares: 30, pixelsWide: 3000, pixelsHigh: 2000)

        let fit = app.buttons["Fit Grid…"]
        XCTAssertTrue(fit.waitForExistence(timeout: 5), "Fit Grid… button not found")
        fit.click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3),
                      "Fit Grid… click did not enter Grid Fit mode")

        let window = app.windows.firstMatch
        let before = window.screenshot().pngRepresentation
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .scroll(byDeltaX: 0, deltaY: 200)
        Thread.sleep(forTimeInterval: 1.0)

        XCTAssertNotEqual(before, window.screenshot().pngRepresentation,
                          "scrolling did not change the preview — zoom is not wired up")

        app.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Fit Grid…"].waitForExistence(timeout: 2),
                      "Cancel did not leave Grid Fit mode after zooming")
    }

    /// Control case: a small map (no overflow, letterboxed mirror). Pan Viewport
    /// is unavailable by design; Fit Grid must be clickable.
    func testFitGridClickableWithSmallMap() throws {
        let app = try launchApp(squares: 10, pixelsWide: 1000, pixelsHigh: 750)

        let fit = app.buttons["Fit Grid…"]
        XCTAssertTrue(fit.waitForExistence(timeout: 5), "Fit Grid… button not found")
        fit.click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2),
                      "Fit Grid… click did not enter Grid Fit mode")
    }
}
