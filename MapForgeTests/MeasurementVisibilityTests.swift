import XCTest
@testable import MapForge

/// Whether the table sees the DM's Measurements.
///
/// ADR-0005 put them on the Player Display and argued the case: a Measurement answers a
/// question the players are the ones asking, and one only the DM can see answers it for the
/// person who could already estimate it. That argument holds for the Measurement taken *for*
/// the table — and not for the one a DM takes for themselves, where the distance is exactly
/// the tactical fact they are deciding whether to reveal.
///
/// So it is a switch rather than a rule, defaulting to shown: the ADR's case is the common
/// one, and the DM turns it off for the uncommon one.
@MainActor
final class MeasurementVisibilityTests: XCTestCase {

    func testTheTableSeesMeasurementsByDefault() {
        let appState = AppState(preferences: isolatedPreferences())
        XCTAssertTrue(appState.showsMeasurementsToPlayers,
                      "ADR-0005's case is the common one and stays the default")
    }

    func testTurningItOffHidesThemFromTheTable() {
        let appState = AppState(preferences: isolatedPreferences())
        appState.fog.pawns = []
        appState.squaresWide = 10
        appState.setMeasurement(Measurement(origin: .point(MapPoint(x: 5, y: 5)),
                                            shape: .circle, distance: 3, direction: 0))
        XCTAssertFalse(appState.playerMeasurements.isEmpty, "precondition: one to hide")

        appState.showsMeasurementsToPlayers = false

        XCTAssertTrue(appState.playerMeasurements.isEmpty,
                      "the table still saw a Measurement the DM had hidden")
    }

    /// The DM keeps theirs either way. Hiding is about what the table is shown, not about
    /// the DM giving up the answer they asked for.
    func testTheDMKeepsTheirsWhenTheTableCannotSee() {
        let appState = AppState(preferences: isolatedPreferences())
        appState.squaresWide = 10
        appState.setMeasurement(Measurement(origin: .point(MapPoint(x: 5, y: 5)),
                                            shape: .circle, distance: 3, direction: 0))

        appState.showsMeasurementsToPlayers = false

        XCTAssertFalse(appState.drawableMeasurements.isEmpty,
                       "hiding from the table also blinded the DM")
    }

    /// Pinned ones follow the same switch — a pin is a Measurement that outlives the next
    /// click, not a different kind of thing.
    func testPinnedMeasurementsFollowTheSwitchToo() {
        let appState = AppState(preferences: isolatedPreferences())
        appState.squaresWide = 10
        appState.setMeasurement(Measurement(origin: .point(MapPoint(x: 5, y: 5)),
                                            shape: .circle, distance: 3, direction: 0,
                                            isDistanceSettled: true))
        appState.pinMeasurement()
        XCTAssertFalse(appState.playerMeasurements.isEmpty, "precondition: one pinned")

        appState.showsMeasurementsToPlayers = false

        XCTAssertTrue(appState.playerMeasurements.isEmpty,
                      "a pinned Measurement outlived the switch")
        XCTAssertFalse(appState.drawableMeasurements.isEmpty,
                       "the DM lost their own pin")
    }

    private func isolatedPreferences() -> DisplayPreferences {
        DisplayPreferences(defaults: UserDefaults(
            suiteName: "MeasurementVisibilityTests.\(UUID().uuidString)")!)
    }
}
