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

    /// Scrolling in magnifies the Map, and scrolling back out returns it.
    ///
    /// This was `…AndResetPutsItBack`, and it read both halves off a "Zoomed — Reset" button:
    /// the button appearing meant zoomed, clicking it meant reset. That button is gone, so
    /// the test asks the Map instead — which is the better question anyway. A DM sees the
    /// artwork change size; they never saw a boolean.
    ///
    /// The floor is what makes the second half work: `PreviewTransform`'s zoom bottoms out at
    /// fit-to-window, so scrolling out far enough lands back on the same rect rather than
    /// continuing to shrink.
    func testScrollingZoomsTheLiveViewAndScrollingBackOutReturnsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=30",
                               "--test-player-screen", "--test-fresh-preferences"]
        app.launchInEnglish()
        XCTAssertTrue(app.buttons["Wall Editor…"].waitForExistence(timeout: 5))

        let map = app.descendants(matching: .any).matching(identifier: "map-preview").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        let point = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        let atRest = map.screenshot().pngRepresentation

        for _ in 1...5 { point.scroll(byDeltaX: 0, deltaY: 30) }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNotEqual(atRest, map.screenshot().pngRepresentation,
                          "scrolling did not zoom the preview")

        // Well past the floor, so the result is the floor rather than some middle scale.
        for _ in 1...20 { point.scroll(byDeltaX: 0, deltaY: -30) }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(atRest, map.screenshot().pngRepresentation,
                       "scrolling back out did not return the preview to the whole Map")
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
        app.launchInEnglish()
        XCTAssertTrue(app.buttons["Wall Editor…"].waitForExistence(timeout: 5))

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

/// The switch that decides whether the table sees a Measurement.
///
/// Driven through the real window because the point of it is that it is *always* there —
/// present before a Measurement exists, so the DM can decide whether this one is for the
/// table before they take it rather than after it is already on the big screen.
final class MeasurementVisibilityUITests: XCTestCase {
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
            .appendingPathComponent("measure-vis-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testTheSwitchIsThereBeforeAnyMeasurementAndTurnsOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=30",
                               "--test-player-screen", "--test-fresh-preferences"]
        app.launchInEnglish()
        XCTAssertTrue(app.buttons["Wall Editor…"].waitForExistence(timeout: 5))

        // A `.checkbox` Toggle publishes as a checkBox, addressed by the identifier rather
        // than the label — the role-and-label mistake this suite has made three times.
        let visibility = app.checkBoxes["measurement-visibility-switch"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 3),
                      "the switch is missing before a Measurement exists")
        XCTAssertEqual(visibility.value as? Int, 1,
                       "the table should see Measurements by default — ADR-0005")

        // Off before taking one: deciding in advance is what "always visible" buys.
        visibility.click()
        XCTAssertEqual(app.checkBoxes["measurement-visibility-switch"].value as? Int, 0,
                       "the switch did not turn off")

        // And it survives taking a Measurement — right-click arms a shape, the left-click
        // after it places the Origin. See the `measurement` spec.
        //
        // Aimed at the Map rather than at a fraction of the window. The old offset was
        // "well left of centre" to dodge a live panel on the RIGHT; the panel is on the left
        // now, so that same point lands on it — the comment had become the opposite of true.
        let point = app.descendants(matching: .any).matching(identifier: "map-preview").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        point.rightClick()
        let circle = app.menuItems["Circle"]
        XCTAssertTrue(circle.waitForExistence(timeout: 3), "no shape menu on right-click")
        circle.click()
        point.click()

        XCTAssertEqual(app.checkBoxes["measurement-visibility-switch"].value as? Int, 0,
                       "taking a Measurement reset the DM's choice")
    }
}

/// The preview must not resize when the DM changes mode.
///
/// Reported from real use: pressing "Wall Editor…" visibly resized the Map, because each mode
/// contributed its own caption to the stack above the preview. The unit tests hold the
/// arithmetic; this holds the layout, which is the half they cannot see.
final class ChromeStabilityUITests: XCTestCase {
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
            .appendingPathComponent("chrome-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testEnteringAndLeavingModesLeavesThePreviewTheSameSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--test-map=\(try fixturePNG().path)", "--test-squares=30",
                               "--test-player-screen", "--test-fresh-preferences"]
        app.launchInEnglish()
        XCTAssertTrue(app.buttons["Wall Editor…"].waitForExistence(timeout: 5))

        // The Player Display picker sits directly below the chrome and above the preview,
        // so its vertical position moves if and only if the chrome's height changes. It is
        // always present, unlike the Fog switch, which waits for fog. Measuring the preview
        // itself is not possible — it publishes no element of its own.
        let anchor = app.popUpButtons.firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 3), "nothing below the chrome to measure")
        let inLiveView = anchor.frame.minY

        app.buttons["Wall Editor…"].click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3), "did not enter the mode")
        XCTAssertEqual(app.popUpButtons.firstMatch.frame.minY, inLiveView, accuracy: 0.5,
                       "the chrome changed height entering the Wall Editor, so the Map resized")

        app.buttons["Done"].click()
        XCTAssertTrue(app.buttons["Wall Editor…"].waitForExistence(timeout: 3), "did not leave the mode")
        XCTAssertEqual(app.popUpButtons.firstMatch.frame.minY, inLiveView, accuracy: 0.5,
                       "the chrome did not return to its height on leaving the mode")
    }
}
