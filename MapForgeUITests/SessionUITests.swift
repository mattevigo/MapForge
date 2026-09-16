// The Comment Bar's three states are decided by `CommentBarPolicy` and tested there. What
// cannot be tested there is whether the field in the window is actually wired to it: a
// disabled control and a live one look the same to a unit test.
import XCTest
import AppKit

final class SessionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func fixturePNG(pixelsWide: Int, pixelsHigh: Int) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide,
                                   pixelsHigh: pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapforge-session-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func launchApp() throws -> XCUIApplication {
        let map = try fixturePNG(pixelsWide: 1200, pixelsHigh: 900)
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(map.path)", "--test-squares=30",
                               "--test-player-screen",
                               "--test-fresh-preferences"]
        app.launch()
        return app
    }

    private func controlWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["control"]
    }

    /// Launches with a Workspace but no Map. An evening belongs to the Workspace and crosses
    /// whatever Maps the party walks (ADR-0015), so the bar must be there before one is open.
    private func launchWithoutMap() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--test-fresh-preferences"]
        app.launch()
        return app
    }

    func testTheCommentBarIsPresentWithNoMapOpen() throws {
        let app = launchWithoutMap()
        let window = controlWindow(app)

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "a Comment typed before the crypt is opened is still part of the evening")
    }

    func testACommentCanBeSentWithNoMapOpen() throws {
        let app = launchWithoutMap()
        let window = controlWindow(app)

        XCTAssertTrue(window.buttons["session-toggle"].waitForExistence(timeout: 5))
        window.buttons["session-toggle"].click()

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.isEnabled, "a Session needs a Workspace, not a Map")
        field.click()
        field.typeText("party still deciding where to go")
        field.typeKey(.enter, modifierFlags: [])
        XCTAssertEqual(field.value as? String ?? "", "")
    }

    func testTheCommentFieldIsDeadUntilASessionStarts() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(field.isEnabled,
                       "the Comment Bar is the one thing that marks the prep/play boundary")
    }

    func testStartingASessionMakesTheFieldLive() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        let toggle = window.buttons["session-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.isEnabled)
    }

    func testTheButtonSaysWhatItWillDo() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        let toggle = window.buttons["session-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // `title` is empty once an accessibility identifier is set, so the rendered text
        // is read from the label instead.
        XCTAssertEqual(toggle.label, "Start Session")
        toggle.click()
        XCTAssertEqual(window.buttons["session-toggle"].label, "Stop Session")
        window.buttons["session-toggle"].click()
        XCTAssertEqual(window.buttons["session-toggle"].label, "Start Session")
    }

    func testSendingACommentClearsTheField() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        window.buttons["session-toggle"].click()

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("the party went left")
        field.typeKey(.enter, modifierFlags: [])

        // An unsent Comment is a half-finished thought; a sent one is in the file and gone
        // from the field.
        XCTAssertEqual(field.value as? String ?? "", "")
    }

    func testStoppingTheSessionKillsTheFieldAgain() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        let toggle = window.buttons["session-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        toggle.click()

        XCTAssertFalse(window.textFields["comment-field"].isEnabled)
    }
}
