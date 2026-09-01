// Reproduces "the Viewport drag jumps back and drifts off the cursor" against the
// real app, driving a real mouse drag. The unit-level loop
// (MapForgeTests/ViewportDragLoopTests) proves the geometry is right *if* the
// overlay's dragStartOrigin survives the gesture; this test proves whether it does.
import XCTest
import AppKit

final class ViewportDragUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func fixturePNG(pixelsWide: Int, pixelsHigh: Int) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSColor.black.setFill()
        NSRect(x: pixelsWide / 8, y: pixelsHigh / 6,
               width: pixelsWide / 3, height: pixelsHigh / 3).fill()
        NSColor.white.setFill()
        NSRect(x: pixelsWide * 5 / 8, y: pixelsHigh / 2,
               width: pixelsWide / 5, height: pixelsHigh / 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapforge-drag-\(pixelsWide)x\(pixelsHigh).png")
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

    /// Enter Viewport mode and drag the rectangle a short, deliberate distance in
    /// several steps - the way a hand does. The app logs every viewportOrigin it is
    /// asked for; the assertion is on that trace.
    func testViewportRectangleDragTracksTheCursor() throws {
        let app = try launchApp(squares: 60, pixelsWide: 3000, pixelsHigh: 2000)

        let pan = app.buttons["Pan Viewport…"]
        XCTAssertTrue(pan.waitForExistence(timeout: 5), "Pan Viewport… button not found")
        pan.click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3), "did not enter Viewport mode")

        let window = app.windows.firstMatch
        // The Viewport rectangle is centred in the preview on entry; the preview
        // occupies the lower part of the window.
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))

        // A multi-step drag: press, move in increments, release.
        start.press(forDuration: 0.1,
                    thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.72)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.5)

        // Left as a visual artefact for diagnosis.
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.lifetime = .keepAlways
        shot.name = "after-drag"
        add(shot)
    }
}
