// The Log View's states and its reading model are decided by `LogViewPolicy` and
// `LogViewModel`, and tested there. What cannot be tested there is whether the toggle in the
// window actually swaps the pane and greys the buttons beside it: a disabled control and a
// live one look the same to a unit test.
import XCTest
import AppKit

final class LogViewUITests: XCTestCase {

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
            .appendingPathComponent("mapforge-log-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func launchApp() throws -> XCUIApplication {
        let map = try fixturePNG(pixelsWide: 1200, pixelsHigh: 900)
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(map.path)", "--test-squares=30",
                               "--test-fresh-preferences"]
        app.launch()
        return app
    }

    private func controlWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["control"]
    }

    func testTheLogToggleSwapsTheMapForTheLogAndBack() throws {
        let app = try launchApp()
        let window = controlWindow(app)
        let toggle = window.checkBoxes["log-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        XCTAssertFalse(window.otherElements["log-view"].exists,
                       "the Map holds the pane until the DM asks otherwise")

        toggle.click()
        XCTAssertTrue(window.otherElements["log-view"].waitForExistence(timeout: 2))

        toggle.click()
        XCTAssertFalse(window.otherElements["log-view"].exists)
    }

    /// The Session control goes with the Live Toolbar. Stopping the evening is done where the
    /// evening is being run.
    func testTheSessionToggleIsGoneWhileReading() throws {
        let app = try launchApp()
        let window = controlWindow(app)
        let toggle = window.checkBoxes["log-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["session-toggle"].exists)

        toggle.click()
        XCTAssertTrue(window.otherElements["log-view"].waitForExistence(timeout: 2))

        XCTAssertFalse(window.buttons["session-toggle"].exists,
                       "every switch in that row is about the Player Display")
    }

    /// All three act on a Map that is not on screen. `Add` in particular would arm a click
    /// invisibly, which is the trap a greyed button avoids.
    func testTheMapButtonsAreDisabledWhileReading() throws {
        let app = try launchApp()
        let window = controlWindow(app)
        let toggle = window.checkBoxes["log-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        XCTAssertTrue(window.buttons["Fit Grid…"].isEnabled)
        XCTAssertTrue(window.buttons["Edit Fog…"].isEnabled)

        toggle.click()
        XCTAssertTrue(window.otherElements["log-view"].waitForExistence(timeout: 2))

        XCTAssertFalse(window.buttons["Fit Grid…"].isEnabled)
        XCTAssertFalse(window.buttons["Edit Fog…"].isEnabled)
        XCTAssertFalse(window.popUpButtons["Add"].isEnabled)
    }

    /// The Comment Bar stays: a DM reading back over the night is the DM about to write the
    /// next Line of it.
    func testTheCommentBarSurvivesTheSwap() throws {
        let app = try launchApp()
        let window = controlWindow(app)
        let toggle = window.checkBoxes["log-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        toggle.click()
        XCTAssertTrue(window.otherElements["log-view"].waitForExistence(timeout: 2))

        XCTAssertTrue(window.textFields["comment-field"].exists)
    }

    /// Without a Session the pane says what fills it, rather than the button being disabled
    /// and teaching nothing.
    func testWithNoSessionTheLogSaysWhatFillsIt() throws {
        let app = try launchApp()
        let window = controlWindow(app)
        let toggle = window.checkBoxes["log-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        toggle.click()
        // Asserted by identifier, not by its words. `.scratch/ui-tests-never-ran/` records
        // that every `staticText` in this window publishes an empty `label` on this macOS, so
        // matching on the sentence would fail for a reason that has nothing to do with the
        // Log. `LogViewTests` owns the wording; this owns that the pane is the empty one.
        XCTAssertTrue(window.staticTexts["log-empty"].waitForExistence(timeout: 2),
                      "with no Session the pane says what fills it")
    }

    /// Issue 05's last "Done when": open → scroll up → append → the view stays put.
    ///
    /// The decision itself is `LogViewPolicy.isFollowing`, unit-tested against the geometry.
    /// What only the real window can show is that the numbers reaching it are the ones that
    /// function expects — the bug this test exists for was a viewport height that was never
    /// measured, which no unit test could have caught.
    func testScrollingUpStopsTheViewFollowingNewLines() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        window.buttons["session-toggle"].click()
        window.checkBoxes["log-toggle"].click()
        XCTAssertTrue(window.otherElements["log-view"].waitForExistence(timeout: 2))

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.click()
        // Enough Lines to overflow the pane, so there is somewhere to scroll up to.
        for index in 0..<40 { field.typeText("line \(index)\n") }

        let rows = window.descendants(matching: .any).matching(identifier: "log-row")
        let first = rows.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 3))

        window.otherElements["log-view"].scroll(byDeltaX: 0, deltaY: 600)
        let restingY = first.frame.origin.y

        field.click()
        field.typeText("one more\n")

        XCTAssertEqual(first.frame.origin.y, restingY, accuracy: 2,
                       "a DM reading back must not be yanked to the bottom by a new Line")
    }

    /// A Comment typed with the Log open must appear: the bar stays visible precisely so it
    /// can be typed into, and a Comment that does not show up is a bug to the DM.
    func testACommentTypedWhileReadingAppearsInTheLog() throws {
        let app = try launchApp()
        let window = controlWindow(app)

        window.buttons["session-toggle"].click()
        window.checkBoxes["log-toggle"].click()
        XCTAssertTrue(window.otherElements["log-view"].waitForExistence(timeout: 2))

        // One row: the `sessionStarted` Line.
        let rows = window.descendants(matching: .any).matching(identifier: "log-row")
        let before = rows.count

        let field = window.textFields["comment-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.click()
        field.typeText("the door is stuck\n")

        // Counted rather than read: the words are unreachable on this macOS (see above), and
        // what this test is for is that the Log noticed at all. `LogViewModelTests` owns what
        // the new row says.
        let grew = NSPredicate(format: "count > %d", before)
        expectation(for: grew, evaluatedWith: rows)
        waitForExpectations(timeout: 3)
    }
}
