import XCTest

/// The Live View's zoom and its Viewport rectangle, driven through the real window.
///
/// Worth UI tests despite the suite's troubles: whether a scroll wheel reaches the preview,
/// and whether a toggle's press reaches the overlay, is gesture composition — the layer this
/// repo has four defects on record in. The assertions are on control state rather than on
/// static text, because static texts publish no label here — see
/// `.scratch/ui-tests-never-ran/`.
final class LiveViewZoomUITests: XCTestCase {
    private func fixturePNG() throws -> URL {
        let size = NSSize(width: 1200, height: 900)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil,
                                                          hints: nil)!)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirror-zoom-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testScrollingZoomsTheLiveViewAndResetPutsItBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=30",
                               "--test-player-screen", "--test-fresh-preferences"]
        app.launch()

        let reset = app.buttons["Zoomed — Reset"]
        XCTAssertTrue(app.buttons["Edit Fog…"].waitForExistence(timeout: 5))
        XCTAssertFalse(reset.exists, "the preview claims to be zoomed before any scroll")

        let window = app.windows["control"]
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .scroll(byDeltaX: 0, deltaY: 30)

        XCTAssertTrue(reset.waitForExistence(timeout: 3),
                      "scrolling did not zoom the preview")

        reset.click()
        XCTAssertFalse(reset.waitForExistence(timeout: 2),
                       "Reset did not return the preview to the whole Map")
    }

    /// The Viewport toggle: one press shows the rectangle, the same press puts it away. It
    /// also ends the Magnifier, since only one of the two is on screen at a time.
    func testTheViewportToggleShowsAndHidesTheRectangle() throws {
        let app = XCUIApplication()
        // A Grid declared at 60 squares makes the Map 60 inches wide at True Scale, which
        // comfortably overflows any Player Display — the condition the toggle needs, since a
        // Map that fits inside the Viewport has no hidden part to pan to.
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=60",
                               "--test-player-screen", "--test-fresh-preferences"]
        app.launch()
        XCTAssertTrue(app.buttons["Edit Fog…"].waitForExistence(timeout: 5))

        // A `.button`-styled Toggle publishes as a checkBox on macOS, not a button — the
        // role mistake this suite has made twice before.
        let viewport = app.checkBoxes["Viewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 3), "no Viewport toggle")
        XCTAssertEqual(viewport.value as? Int, 0, "the rectangle is showing before any press")

        viewport.click()
        XCTAssertEqual(app.checkBoxes["Viewport"].value as? Int, 1,
                       "the toggle did not turn on")

        app.checkBoxes["Viewport"].click()
        XCTAssertEqual(app.checkBoxes["Viewport"].value as? Int, 0,
                       "the same button did not put the rectangle away")
    }
}
