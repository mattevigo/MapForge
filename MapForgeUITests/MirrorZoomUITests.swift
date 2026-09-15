import XCTest

/// The DM's magnifier, driven through the real window.
///
/// Worth a UI test despite the suite's troubles: `MirrorZoom` is held by unit tests, but
/// whether a scroll wheel event reaches the mirror at all is gesture composition, and that
/// is the layer this repo has four defects on record in. The assertion is on a button's
/// existence rather than on a static text, because static texts publish no label here — see
/// `.scratch/ui-tests-never-ran/`.
final class MirrorZoomUITests: XCTestCase {
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

    func testScrollingMagnifiesTheMirrorAndResetPutsItBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=30",
                               "--test-player-screen", "--test-fresh-preferences"]
        app.launch()

        let reset = app.buttons["Zoomed — Reset"]
        XCTAssertTrue(app.buttons["Edit Fog…"].waitForExistence(timeout: 5))
        XCTAssertFalse(reset.exists, "the mirror claims to be magnified before any scroll")

        let window = app.windows["control"]
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .scroll(byDeltaX: 0, deltaY: 30)

        XCTAssertTrue(reset.waitForExistence(timeout: 3),
                      "scrolling did not magnify the mirror")

        reset.click()
        XCTAssertFalse(reset.waitForExistence(timeout: 2),
                       "Reset did not return the mirror to a true mirror")
    }
}
