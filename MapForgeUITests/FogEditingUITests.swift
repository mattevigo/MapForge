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
        app.launchArguments = ["--test-map=\(map.path)", "--test-squares=30",
                               "--test-player-screen",
                               "--test-fresh-preferences"]
        app.launchInEnglish()
        return app
    }

    /// The Control Window, by its identifier — never `app.windows.firstMatch`, which
    /// resolves to the borderless Player window: it sorts first, so every coordinate
    /// click aimed at the preview landed on the Player Display instead. The controls
    /// still responded, so the tests looked like they were driving the preview.
    private func controlWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["control"]
    }

    /// The Map itself, which is what every coordinate click in this file is aiming at.
    ///
    /// These used to be fractions of the whole Control Window, which worked only while the
    /// Map held the window's left edge: `dx: 0.3` was inside the Map because there was
    /// nothing to its left. The live panel took that edge when the window split into two
    /// columns, so the same fraction started landing on the Party list and every placement
    /// test failed at once. Addressing the Map directly means the offsets say what they
    /// mean — a fraction of the Map — and survive the next layout change.
    private func mapPreview(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "map-preview").firstMatch
    }

    /// Arm `Add` with one kind, then click the preview to place it.
    ///
    /// Replaces a `tool()` helper that clicked the fog editor's segmented picker. That
    /// picker is gone (ADR-0013): Pawns and Lights are placed in the Live View now, with no
    /// mode to enter first. A `Menu` publishes as a **MenuButton** carrying a *title*, not a
    /// Button with a label and not a PopUpButton — the same class of role mistake the old
    /// helper documented for segmented Pickers, and `app.popUpButtons["Add"]` matches
    /// nothing. Read off the element tree rather than guessed.
    private func add(_ app: XCUIApplication, _ kind: String,
                     at offset: CGVector, file: StaticString = #filePath,
                     line: UInt = #line) {
        let menu = app.menuButtons["Add"]
        XCTAssertTrue(menu.waitForExistence(timeout: 2), "no Add menu", file: file, line: line)
        menu.click()
        let item = app.menuItems[kind]
        XCTAssertTrue(item.waitForExistence(timeout: 2), "Add offers no \(kind)",
                      file: file, line: line)
        item.click()
        mapPreview(app).coordinate(withNormalizedOffset: offset).click()
    }


    /// Clicks an element by absolute coordinate, bypassing `isHittable`.
    ///
    /// The live panel's `ScrollView` publishes as **Disabled** in the accessibility tree —
    /// at 236 points before the Encounter tab existed and at 320 after, so it is AppKit's
    /// behaviour rather than this app's. Everything inside it therefore reports
    /// `isHittable == false`, and `element.click()` refuses. The controls are genuinely
    /// live: a coordinate click at the element's own centre toggles them, which is what
    /// this does and what a DM's mouse does.
    private func clickByCoordinate(_ app: XCUIApplication, _ element: XCUIElement) {
        let window = controlWindow(app)
        let frame = window.frame
        let dx = (element.frame.midX - frame.minX) / frame.width
        let dy = (element.frame.midY - frame.minY) / frame.height
        window.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).click()
    }

    func testEditFogButtonEntersTheMode() throws {
        let app = try launchApp()
        let draw = app.buttons["wall-editor"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5), "Wall Editor… button not found")
        draw.click()

        // The mode's own controls replace the entry buttons.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2), "did not enter Wall mode")
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 0 Pawns"].exists, "fog summary not shown")
    }

    func testClickingPlacesVerticesAndDoubleClickCommitsTheChain() throws {
        let app = try launchApp()
        app.buttons["wall-editor"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let map = mapPreview(app)
        // Three points spread across the Map. Fractions of the Map now, not of the window,
        // so they stay inside it wherever the Map sits.
        let first = map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let second = map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4))
        let third = map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7))

        first.click()
        second.click()
        third.click()
        third.doubleClick()

        // Three vertices make two Walls. The count label is the observable outcome.
        XCTAssertTrue(app.staticTexts["2 Walls, 0 Lights, 0 Pawns"].waitForExistence(timeout: 2),
                      "clicks did not become Walls")
    }

    func testCancelRestoresTheWallsFromBeforeTheMode() throws {
        let app = try launchApp()
        app.buttons["wall-editor"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let map = mapPreview(app)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)).click()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)).click()
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)).doubleClick()
        XCTAssertTrue(app.staticTexts["1 Wall, 0 Lights, 0 Pawns"].waitForExistence(timeout: 2))

        app.buttons["Cancel"].click()
        app.buttons["wall-editor"].click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 0 Pawns"].waitForExistence(timeout: 2),
                      "Cancel did not discard the Walls drawn in the mode")
    }

    func testPlacingALightFromTheAddMenuAndTogglingItLive() throws {
        // No mode to enter: a Light is placed in the Live View, which is the whole point of
        // ADR-0013. This test used to click "Wall Editor…" first and switch to the Light tool.
        let app = try launchApp()
        add(app, "Light", at: CGVector(dx: 0.4, dy: 0.7))

        // The live toggle row is the observable outcome, and it is where it always was.
        //
        // Addressed by identifier rather than by label: this row's Toggle is a bare SF
        // Symbol, so it published as "1" only while the panel was a horizontal strip that
        // numbered its buttons. The query went stale when the panel became vertical and
        // stayed stale for months, because nobody could tell a wrong query from a missing
        // control.
        //
        // A `.button`-styled Toggle publishes on macOS as a checkBox, not a button — the
        // same class of role mistake the `add()` helper documents above.
        let toggle = app.checkBoxes["light-toggle-1"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4), "no live toggle for the Light")

        let before = toggle.value as? Int
        toggle.click()
        XCTAssertNotEqual(app.checkBoxes["light-toggle-1"].value as? Int, before,
                          "the live toggle did not douse the Light")
    }

    func testZoomingInKeepsThePreviewInsideTheWindow() throws {
        let app = try launchApp()
        app.buttons["wall-editor"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let window = controlWindow(app)
        let windowFrame = window.frame

        // Scroll well past the point where the image exceeds the preview. The point must be
        // over the Map — the window's centre is no longer inside it.
        let centre = mapPreview(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 1...40 { centre.scroll(byDeltaX: 0, deltaY: 10) }

        // The window must not have been resized by its own content, and the controls must
        // still be there — an overflowing preview drew straight over them.
        XCTAssertEqual(window.frame, windowFrame, "the preview resized the window")
        XCTAssertTrue(app.buttons["Done"].isHittable,
                      "the zoomed preview covered the mode controls")
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
    }

    func testPlacingAPawnAndDraggingItOutsideTheEditingMode() throws {
        let app = try launchApp()
        // Placed from the Live View, with no mode entered — which is what this test is now
        // for. It used to enter the fog editor and switch to the Pawn tool; both are gone.
        add(app, "Player", at: CGVector(dx: 0.45, dy: 0.7))

        // A Pawn's toggle is labelled with the Pawn's own name, which the DM can change in
        // the field beside it, so "1" never matched it — this test was once asserting
        // against a Light's button that happened to be on screen in an earlier panel.
        XCTAssertTrue(app.checkBoxes["pawn-light-toggle"].waitForExistence(timeout: 4),
                      "the placed Pawn has no live toggle")

        // Dragging is a live action, and always was — the difference is that placing is one
        // now too, so the whole test happens in one mode.
        // The same Map-relative offset the Pawn was placed at, or the drag starts somewhere
        // the Pawn is not.
        let map = mapPreview(app)
        let from = map.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7))
        let to = map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7))
        from.press(forDuration: 0.1, thenDragTo: to)

        // The Pawn survived the drag rather than being duplicated or dropped. The fog
        // summary is only drawn inside the Wall Editor, so that is where the count is read.
        app.buttons["wall-editor"].click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 1 Pawn"].waitForExistence(timeout: 2))
    }

    func testTheFogOverlayHasAnAlwaysReachableOffSwitch() throws {
        // "The off switch is a single control" — no mode to enter, nothing to open first.
        let app = try launchApp()
        // Place something so the fog row appears. No mode needed any more (ADR-0013).
        add(app, "Light", at: CGVector(dx: 0.45, dy: 0.7))

        // Addressed by identifier, not by the "Fog" label the old query used — a label is
        // the first thing a redesign changes. The element really is a `Switch` here; the
        // original query missed because `app.switches["Fog"]` matches on label, and the
        // Toggle's label is not exposed as the element's name.
        let fog = app.switches["fog-overlay-switch"]
        XCTAssertTrue(fog.waitForExistence(timeout: 2), "no Fog Overlay switch outside the mode")
        let before = fog.value as? Int
        fog.click()
        XCTAssertNotEqual(app.switches["fog-overlay-switch"].value as? Int, before,
                          "the switch did not change the Fog Overlay")
        XCTAssertTrue(app.switches["fog-overlay-switch"].exists,
                      "the switch vanished after being used")
    }

    func testTheLivePanelHasASceneTabAndACombatTab() throws {
        let app = try launchApp()
        // The panel appears once there is something on the Map to list.
        add(app, "Light", at: CGVector(dx: 0.45, dy: 0.7))

        // A segmented Picker, so the two tabs publish as radio buttons — the same role the
        // fog tool picker uses, which `tool()` documents above.
        let scene = app.radioButtons["Scene"]
        let combat = app.radioButtons["Encounter"]
        XCTAssertTrue(scene.waitForExistence(timeout: 2), "no Scene tab")
        XCTAssertTrue(combat.exists, "no Encounter tab")
        XCTAssertEqual(scene.value as? Int, 1, "a session should start on the Scene tab")

        // Switching tabs shows the other panel and hides this one's rows.
        combat.click()
        // Only a Light was placed, so the tracker correctly reports there is nobody to
        // fight rather than offering an empty Order.
        XCTAssertTrue(app.staticTexts["Nobody on the Map to fight"].waitForExistence(timeout: 2),
                      "the Encounter tab showed nothing")
        XCTAssertFalse(app.checkBoxes["light-toggle-1"].exists,
                       "the Scene tab's rows are still on screen behind the Encounter tab")

        scene.click()
        XCTAssertTrue(app.checkBoxes["light-toggle-1"].waitForExistence(timeout: 2),
                      "the Scene tab did not come back")
    }
}
