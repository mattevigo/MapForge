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
}

private func isolatedPreferences() -> DisplayPreferences {
    DisplayPreferences(defaults: UserDefaults(suiteName: "MapFitTests.\(UUID().uuidString)")!)
}
