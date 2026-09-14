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
        app.launchArguments = ["--test-map", map.path, "--test-squares", "30",
                               "--test-player-screen", "auto",
                               "--test-fresh-preferences"]
        app.launch()
        return app
    }

    /// The Control Window, by its identifier — never `app.windows.firstMatch`, which
    /// resolves to the borderless Player window: it sorts first, so every coordinate
    /// click aimed at the preview landed on the Player Display instead. The controls
    /// still responded, so the tests looked like they were driving the preview.
    private func controlWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows["control"]
    }

    /// The fog tool picker's segments. A segmented `Picker` publishes them as
    /// **radio buttons**, not buttons — `app.buttons["Lights"]` matches nothing, which is
    /// what made three of these tests fail as "no matches found".
    private func tool(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.radioButtons[label]
    }


    /// Clicks an element by absolute coordinate, bypassing `isHittable`.
    ///
    /// The live panel's `ScrollView` publishes as **Disabled** in the accessibility tree —
    /// at 236 points before the Combat tab existed and at 320 after, so it is AppKit's
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
        let draw = app.buttons["Edit Fog…"]
        XCTAssertTrue(draw.waitForExistence(timeout: 5), "Edit Fog… button not found")
        draw.click()

        // The mode's own controls replace the entry buttons.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2), "did not enter Wall mode")
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 0 Pawns"].exists, "fog summary not shown")
    }

    func testClickingPlacesVerticesAndDoubleClickCommitsTheChain() throws {
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let window = controlWindow(app)
        // Three points across the lower half of the window, safely inside the preview
        // and clear of the controls above it.
        let first = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        let second = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let third = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))

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
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let window = controlWindow(app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)).click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).doubleClick()
        XCTAssertTrue(app.staticTexts["1 Wall, 0 Lights, 0 Pawns"].waitForExistence(timeout: 2))

        app.buttons["Cancel"].click()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 0 Pawns"].waitForExistence(timeout: 2),
                      "Cancel did not discard the Walls drawn in the mode")
    }

    func testPlacingALightWithTheLightToolAndTogglingItLive() throws {
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        // Switch the tool: a click then places a Light, not a Wall vertex.
        tool(app, "Lights").click()
        let window = controlWindow(app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.7)).click()
        XCTAssertTrue(app.staticTexts["0 Walls, 1 Light, 0 Pawns"].waitForExistence(timeout: 2),
                      "the click did not place a Light")

        // The live toggle row is available outside the editing mode.
        //
        // Addressed by identifier rather than by label: this row's Toggle is a bare SF
        // Symbol, so it published as "1" only while the panel was a horizontal strip that
        // numbered its buttons. The query went stale when the panel became vertical and
        // stayed stale for months, because nobody could tell a wrong query from a missing
        // control.
        app.buttons["Done"].click()
        // A `.button`-styled Toggle publishes on macOS as a checkBox, not a button — the
        // same class of role mistake the `tool()` helper documents above for segmented
        // Pickers, and half of why the original `app.buttons["1"]` could never match.
        let toggle = app.checkBoxes["light-toggle-1"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2), "no live toggle for the Light")
        XCTAssertEqual(toggle.value as? Int, 1, "a new Light should be burning")
        clickByCoordinate(app, toggle)
        XCTAssertEqual(app.checkBoxes["light-toggle-1"].value as? Int, 0,
                       "clicking the toggle did not douse the Light")
    }

    /// Regression test for the reported zoom bug: "no zoom limit, and it resets to zoomed
    /// out when reached". The cause was a GeometryReader measuring an unconstrained ZStack
    /// that sized itself to the zoomed Image, so the preview overflowed the window instead
    /// of zooming and snapped back when layout resettled.
    ///
    /// This is the seam that catches it — no unit test can, because the defect is SwiftUI
    /// layout behaviour, not arithmetic.
    func testZoomingInKeepsThePreviewInsideTheWindow() throws {
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        let window = controlWindow(app)
        let windowFrame = window.frame

        // Scroll well past the point where the image exceeds the preview.
        let centre = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
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
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        tool(app, "Pawns").click()
        let window = controlWindow(app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7)).click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 1 Pawn"].waitForExistence(timeout: 2),
                      "the click did not place a Pawn")

        // Leaving the mode: the token stays, and its light toggle joins the live row.
        // A Pawn's toggle is labelled with the Pawn's own name, which the DM can change in
        // the field beside it, so "1" never matched it — this test was asserting against a
        // Light's button that happened to be on screen in an earlier version of the panel.
        app.buttons["Done"].click()
        XCTAssertTrue(app.checkBoxes["pawn-light-toggle"].waitForExistence(timeout: 2),
                      "the Pawn lost its live toggle outside the editing mode")

        // Dragging is a live action — it must work here, with no mode entered.
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7))
        from.press(forDuration: 0.1, thenDragTo: to)

        // The Pawn survived the drag rather than being duplicated or dropped.
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.staticTexts["0 Walls, 0 Lights, 1 Pawn"].waitForExistence(timeout: 2))
    }

    func testTheFogOverlayHasAnAlwaysReachableOffSwitch() throws {
        // "The off switch is a single control" — no mode to enter, nothing to open first.
        let app = try launchApp()
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))

        // Place something so the fog row appears.
        tool(app, "Lights").click()
        controlWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7)).click()
        app.buttons["Done"].click()

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
        app.buttons["Edit Fog…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))
        tool(app, "Lights").click()
        controlWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7)).click()
        app.buttons["Done"].click()

        // A segmented Picker, so the two tabs publish as radio buttons — the same role the
        // fog tool picker uses, which `tool()` documents above.
        let scene = app.radioButtons["Scene"]
        let combat = app.radioButtons["Combat"]
        XCTAssertTrue(scene.waitForExistence(timeout: 2), "no Scene tab")
        XCTAssertTrue(combat.exists, "no Combat tab")
        XCTAssertEqual(scene.value as? Int, 1, "a session should start on the Scene tab")

        // Switching tabs shows the other panel and hides this one's rows.
        combat.click()
        // Only a Light was placed, so the tracker correctly reports there is nobody to
        // fight rather than offering an empty Order.
        XCTAssertTrue(app.staticTexts["Nobody on the Map to fight"].waitForExistence(timeout: 2),
                      "the Combat tab showed nothing")
        XCTAssertFalse(app.checkBoxes["light-toggle-1"].exists,
                       "the Scene tab's rows are still on screen behind the Combat tab")

        scene.click()
        XCTAssertTrue(app.checkBoxes["light-toggle-1"].waitForExistence(timeout: 2),
                      "the Scene tab did not come back")
    }
}
