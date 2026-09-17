// Saying which Monster a Creature is, driven through the real sheet. The rules are tested
// pure; what is left is wiring only a window can show — above all that Return inside the
// open search results picks a Monster and does *not* also press the sheet's OK.
import XCTest
import AppKit

final class BestiaryUITests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A throwaway Workspace with a two-Monster Bestiary and one note that cannot be read.
        // Never a folder the developer uses — see `openWorkspaceFromLaunchArgumentsIfPresent`.
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MapForgeBestiaryUITests.\(UUID().uuidString)")
        let notes = root.appendingPathComponent("03_Bestiario")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mapforge"),
                                                withIntermediateDirectories: true)
        try Data("{ \"bestiaryStatBlockPath\": \"03_Bestiario\" }".utf8)
            .write(to: root.appendingPathComponent(".mapforge/config.json"))
        try Data("""
        ```statblock
        name: Gnoll Guerriero
        size: Media
        type: Immondo
        ac: 15
        initiative: "+1 (11)"
        hp: 27
        speed: 9 m
        cr: 1/2
        actions:
          - name: Squartare
            desc: "*Attacco con arma da mischia:* +4 al tiro per colpire."
        ```
        """.utf8).write(to: notes.appendingPathComponent("Gnoll_Guerriero.md"))
        try Data("```statblock\nname: Goblin Guerriero\nac: 15\nhp: 10\ncr: 1/4\n```\n".utf8)
            .write(to: notes.appendingPathComponent("Goblin_Guerriero.md"))
        try Data("```statblock\nac: 12\n```\n".utf8)
            .write(to: notes.appendingPathComponent("Senza_Nome.md"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func fixturePNG() throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 900,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 900).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = root.appendingPathComponent("dungeon.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func mapPreview(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "map-preview").firstMatch
    }

    /// Saved beside the run when `BESTIARY_SHOTS` names a folder, so a change to the sheet
    /// can be looked at rather than imagined. Silent otherwise.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["BESTIARY_SHOTS"] else { return }
        let png = app.windows["control"].screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    func testReturnPicksAMonsterAndOKThenStampsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=30",
                               "--test-player-screen", "--test-fresh-preferences",
                               "--test-workspace=\(root.path)"]
        app.launch()

        let add = app.menuButtons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add menu")
        add.click()
        app.menuItems["Creature"].click()
        let spot = mapPreview(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        spot.click()

        spot.rightClick()
        let edit = app.menuItems["Edit…"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "no Edit… on a Pawn's menu")
        edit.click()

        let search = app.textFields["monster-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3), "a Creature's sheet has no search box")
        XCTAssertTrue(app.buttons["bestiary-caption"].exists,
                      "the note with no name was skipped without a word")
        let ok = app.buttons["edit-pawn-ok"]
        let restingOK = ok.frame
        search.click()
        search.typeText("g")
        XCTAssertTrue(app.buttons["monster-result-0"].waitForExistence(timeout: 2),
                      "typing offered no Monsters")
        // Reported from real use: the results used to be laid out in the form, so the sheet
        // grew with every keystroke and OK moved under the cursor. They float now.
        XCTAssertEqual(ok.frame, restingOK, "the open results moved the OK button")
        shoot(app, "1-searching")
        search.typeText("no")

        // The point of the test: Return picks, and the sheet is still up afterwards.
        search.typeText("\r")
        XCTAssertTrue(app.descendants(matching: .any)["monster-chosen"].waitForExistence(timeout: 2),
                      "Return did not pick the highlighted Monster")
        XCTAssertTrue(app.buttons["edit-pawn-ok"].exists, "Return also pressed OK")
        shoot(app, "2-picked")

        app.buttons["edit-pawn-ok"].click()
        XCTAssertFalse(app.buttons["edit-pawn-ok"].waitForExistence(timeout: 1),
                       "a first stamp has nothing to lose and should ask nothing")

        // Its page is in the Combat tab once a fight makes it the active Combatant.
        app.radioButtons["Combat"].click()
        let play = app.buttons["encounter-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 2), "no play button")
        // By coordinate: the live panel's ScrollView publishes as Disabled, so everything in
        // it reports `isHittable == false`. See `FogEditingUITests.clickByCoordinate`.
        let window = app.windows["control"].frame
        app.windows["control"].coordinate(withNormalizedOffset: CGVector(
            dx: (play.frame.midX - window.minX) / window.width,
            dy: (play.frame.midY - window.minY) / window.height)).click()
        XCTAssertTrue(app.descendants(matching: .any)["monster-reference"].waitForExistence(timeout: 3),
                      "the Monster's page is not under the Stat Block editor")
        shoot(app, "3-fighting")
    }
}
