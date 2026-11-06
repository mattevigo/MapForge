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

    /// The green rectangle covers the whole Map while fitted, and comes back to the True
    /// Scale region it outlined before once Map Fit is off.
    func testTheViewportCoversTheWholeMapWhileFittedAndReturnsAfter() {
        let appState = AppState(preferences: isolatedPreferences())
        // 50 pt/in on a 1000×600 pt screen shows 20×12 in of a 30×20 in Map.
        let display = DisplayMetrics(pixelSize: CGSize(width: 2000, height: 1200),
                                     physicalSizeMM: CGSize(width: 508, height: 304.8),
                                     backingScaleFactor: 2)
        let map = MapScale.grid(squaresWide: 30, imagePixelSize: CGSize(width: 3000, height: 2000))
        func viewport() -> Viewport {
            ScaleMath.playerViewport(map: map, display: display,
                                     screenSizePoints: CGSize(width: 1000, height: 600),
                                     desiredOrigin: appState.viewportOrigin,
                                     isMapFitOn: appState.isMapFitOn)
        }
        appState.viewportOrigin = CGPoint(x: 3, y: 4)
        let before = viewport()

        appState.isMapFitOn = true
        XCTAssertEqual(viewport(), Viewport(originInches: .zero, sizeInches: CGSize(width: 30, height: 20)))

        appState.isMapFitOn = false
        XCTAssertEqual(viewport(), before)
        XCTAssertEqual(before.originInches, CGPoint(x: 3, y: 4))
    }
}

private func isolatedPreferences() -> DisplayPreferences {
    DisplayPreferences(defaults: UserDefaults(suiteName: "MapFitTests.\(UUID().uuidString)")!)
}
