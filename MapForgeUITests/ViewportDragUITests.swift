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
        app.launchArguments = ["--test-map=\(map.path)", "--test-squares=\(squares)",
                               "--test-player-screen",
                               "--test-fresh-preferences"]
        app.launchInEnglish()
        return app
    }

    /// The Control Window, by its identifier — `app.windows.firstMatch` resolves to the
    /// borderless Player window, which sorts first, so the drag ran on the Player Display
    /// instead of on the Viewport rectangle.
    private func controlWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["control"]
    }

    /// Arm the Viewport toggle and drag the rectangle a short, deliberate distance in
    /// several steps - the way a hand does. The app logs every viewportOrigin it is
    /// asked for; the assertion is on that trace.
    func testViewportRectangleDragTracksTheCursor() throws {
        let app = try launchApp(squares: 60, pixelsWide: 3000, pixelsHigh: 2000)

        // "Pan Viewport…" was a mode; it is a toggle now, and the rectangle is drawn either
        // way — the toggle decides whether it can be *dragged*. A `.button`-styled Toggle
        // publishes as a checkBox.
        let viewport = app.checkBoxes["Viewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5), "Viewport toggle not found")
        viewport.click()
        XCTAssertEqual(app.checkBoxes["Viewport"].value as? Int, 1, "the toggle did not arm")

        let window = controlWindow(app)
        // The rectangle sits over the whole Map. Aimed at the Map itself rather than at a
        // fraction of the window: the old offset dodged a live panel on the right, and the
        // panel is on the left now, so it would land on the panel instead.
        let map = app.descendants(matching: .any).matching(identifier: "map-preview").firstMatch
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))

        // A multi-step drag: press, move in increments, release.
        start.press(forDuration: 0.1,
                    thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)),
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
