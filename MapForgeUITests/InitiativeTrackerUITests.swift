import XCTest
import AppKit

/// The Initiative Tracker driven as a DM drives it.
///
/// Everything here lives in the live panel, whose `ScrollView` publishes as Disabled in the
/// accessibility tree — so `isHittable` is always false and `element.click()` refuses. The
/// controls are genuinely live; see `.scratch/initiative-tracker/issues/04-the-combat-tab.md`.
/// Clicks go through `clickByCoordinate`.
final class InitiativeTrackerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func fixturePNG() throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 900,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 900).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapforge-combat-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func controlWindow(_ app: XCUIApplication) -> XCUIElement { app.windows["control"] }

    private func clickByCoordinate(_ app: XCUIApplication, _ element: XCUIElement) {
        let frame = controlWindow(app).frame
        let dx = (element.frame.midX - frame.minX) / frame.width
        let dy = (element.frame.midY - frame.minY) / frame.height
        controlWindow(app).coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).click()
    }

    /// A Map with two Pawns on it and the Combat tab showing.
    private func launchWithCombatants() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map", try fixturePNG().path, "--test-squares", "30",
                               "--test-player-screen", "auto", "--test-fresh-preferences"]
        app.launch()

        // Two Pawns, placed in the fog editing mode as the Pawns tool does.
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        app.radioButtons["Pawns"].click()
        let window = controlWindow(app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.7)).click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 2 Pawns"].waitForExistence(timeout: 2),
                      "the fixture needs two Pawns to fight")
        app.buttons["Done"].click()

        app.radioButtons["Combat"].click()
        return app
    }

    func testPlayRollsInitiativeAndShowsTheOrder() throws {
        let app = try launchWithCombatants()

        let play = app.buttons["encounter-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 2), "no play button")
        clickByCoordinate(app, play)

        XCTAssertTrue(app.staticTexts["round-number"].waitForExistence(timeout: 2),
                      "the Round is not shown")
        XCTAssertEqual(app.staticTexts["round-number"].value as? String, "Round 1")
        // `.any` counts a row's nested labels and images too; the rows themselves are the
        // elements carrying the identifier, so match on the type that publishes it.
        // The rows are combined into single accessibility elements, so this counts rows
        // rather than every Text and Image inside them.
        XCTAssertEqual(app.descendants(matching: .any)
            .matching(identifier: "combatant-row").count, 2,
                       "both Pawns should be in the Order")
    }

    func testNextAdvancesTheTurnAndTheRound() throws {
        let app = try launchWithCombatants()
        clickByCoordinate(app, app.buttons["encounter-play"])
        XCTAssertTrue(app.staticTexts["round-number"].waitForExistence(timeout: 2))

        // Two Combatants, so two Nexts wrap into Round 2.
        clickByCoordinate(app, app.buttons["encounter-next"])
        XCTAssertEqual(app.staticTexts["round-number"].value as? String, "Round 1",
                       "one Turn of two should not end the Round")
        clickByCoordinate(app, app.buttons["encounter-next"])
        XCTAssertEqual(app.staticTexts["round-number"].value as? String, "Round 2",
                       "the Round did not advance when the Order wrapped")
    }

    func testPreviousShowsTheCorrectingBarAndNextReturnsToLive() throws {
        let app = try launchWithCombatants()
        clickByCoordinate(app, app.buttons["encounter-play"])
        XCTAssertTrue(app.staticTexts["round-number"].waitForExistence(timeout: 2))
        clickByCoordinate(app, app.buttons["encounter-next"])

        clickByCoordinate(app, app.buttons["encounter-previous"])
        XCTAssertTrue(app.staticTexts["correcting-bar"].waitForExistence(timeout: 2),
                      "going back did not announce that it is a correction")

        // Next walks back towards live rather than ending a Turn.
        clickByCoordinate(app, app.buttons["encounter-next"])
        XCTAssertFalse(app.staticTexts["correcting-bar"].exists,
                       "Next did not return to live play")
        XCTAssertEqual(app.staticTexts["round-number"].value as? String, "Round 1",
                       "returning to live must not have ended a Turn")
    }

    func testStoppingAsksFirstAndCancellingKeepsTheFight() throws {
        let app = try launchWithCombatants()
        clickByCoordinate(app, app.buttons["encounter-play"])
        XCTAssertTrue(app.staticTexts["round-number"].waitForExistence(timeout: 2))

        clickByCoordinate(app, app.buttons["encounter-stop"])
        // The sheet's Cancel, not the fog editing mode's — both exist in this window.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 2), "stopping did not confirm first")
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["round-number"].exists, "Cancel ended the fight anyway")
    }

    func testThePlayButtonIsUnavailableWithNobodyToFight() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map", try fixturePNG().path, "--test-squares", "30",
                               "--test-player-screen", "auto", "--test-fresh-preferences"]
        app.launch()
        // A Light, so the panel appears at all, but no Pawn to take a Turn.
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        app.radioButtons["Lights"].click()
        controlWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7)).click()
        app.buttons["Done"].click()

        app.radioButtons["Combat"].click()
        XCTAssertTrue(app.staticTexts["Nobody on the Map to fight"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["encounter-play"].isEnabled)
    }
}
