import XCTest
@testable import MapForge

/// **Map Fit** is a live switch, not a setting: the DM fits the Map to the Player Display for
/// a moment of the evening and lets it go again. Nothing about it is remembered — not per
/// Map, not per display, not across launches.
@MainActor
final class MapFitTests: XCTestCase {

    func testMapFitIsOffOnLaunch() {
        let appState = AppState(preferences: isolatedPreferences())
        XCTAssertFalse(appState.isMapFitOn)
    }

    func testMapFitIsNotRememberedAcrossLaunches() {
        let preferences = isolatedPreferences()
        AppState(preferences: preferences).isMapFitOn = true
        XCTAssertFalse(AppState(preferences: preferences).isMapFitOn)
    }

    func testTurningMapFitOffReturnsToTheViewportSetBefore() {
        let appState = AppState(preferences: isolatedPreferences())
        appState.viewportOrigin = CGPoint(x: 3, y: 4)
        appState.isMapFitOn = true
        appState.isMapFitOn = false
        XCTAssertEqual(appState.viewportOrigin, CGPoint(x: 3, y: 4))
    }

    // MARK: Without a Player Display

    /// There is no screen to fit the Map to without a Player Display, so the toggle is
    /// unavailable.
    func testItIsOfferedOnlyWithAPlayerDisplay() {
        XCTAssertTrue(MapFitToggle.isAvailable(hasDisplay: true))
        XCTAssertFalse(MapFitToggle.isAvailable(hasDisplay: false))
    }

    /// Unplugging the Player Display while fitted would otherwise leave Map Fit on behind a
    /// disabled toggle the DM cannot press to turn it off. It puts itself away instead, the
    /// way an armed Viewport rectangle does — and the next display starts at True Scale.
    func testLosingThePlayerDisplayPutsItAway() {
        XCTAssertFalse(MapFitToggle.staysOn(hasDisplay: false))
        XCTAssertTrue(MapFitToggle.staysOn(hasDisplay: true))
    }

    /// The session obeys the rule wherever the Player Display is resolved: with no screen to
    /// present on (a test has none), Map Fit cannot stay on.
    func testTheSessionPutsItAwayWithoutAPlayerDisplay() {
        let appState = AppState(preferences: isolatedPreferences())
        XCTAssertNil(appState.playerScreen)
        appState.isMapFitOn = true
        XCTAssertFalse(appState.isMapFitOn)
    }

    // MARK: The Viewport

    /// The green rectangle covers the whole Map while fitted, and comes back to the True
    /// Scale region it outlined before once Map Fit is off.
    func testTheViewportCoversTheWholeMapWhileFittedAndReturnsAfter() {
        // Map Fit held here rather than on an `AppState`: a test has no Player Display, and
        // the session puts Map Fit away without one.
        var isMapFitOn = false
        var viewportOrigin: CGPoint?
        // 50 pt/in on a 1000×600 pt screen shows 20×12 in of a 30×20 in Map.
        let display = DisplayMetrics(pixelSize: CGSize(width: 2000, height: 1200),
                                     physicalSizeMM: CGSize(width: 508, height: 304.8),
                                     backingScaleFactor: 2)
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        func viewport() -> Viewport? {
            ScaleMath.playerViewport(map: map, display: display,
                                     screenSizePoints: CGSize(width: 1000, height: 600),
                                     desiredOrigin: viewportOrigin,
                                     isMapFitOn: isMapFitOn)
        }
        viewportOrigin = CGPoint(x: 3, y: 4)
        let before = viewport()

        isMapFitOn = true
        XCTAssertEqual(viewport(), Viewport(originInches: .zero, sizeInches: CGSize(width: 30, height: 20)))

        isMapFitOn = false
        XCTAssertEqual(viewport(), before)
        XCTAssertEqual(before?.originInches, CGPoint(x: 3, y: 4))
    }
}

private func isolatedPreferences() -> DisplayPreferences {
    DisplayPreferences(defaults: UserDefaults(suiteName: "MapFitTests.\(UUID().uuidString)")!)
}
