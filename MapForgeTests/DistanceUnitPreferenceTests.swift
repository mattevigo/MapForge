import Combine
import XCTest
@testable import MapForge

/// The Distance Unit is chosen per Mac (ADR-0027), so it lives beside the Interface Language in
/// `DisplayPreferences` — and until the DM chooses, the Mac's region decides.
final class DistanceUnitPreferenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func preferences(region: String) -> DisplayPreferences {
        DisplayPreferences(defaults: defaults, domain: suiteName,
                           region: Locale(identifier: region))
    }

    func testAnAmericanMacStartsInFeet() {
        XCTAssertEqual(preferences(region: "en_US").distanceUnit, .feet)
    }

    func testAnItalianMacStartsInMetres() {
        XCTAssertEqual(preferences(region: "it_IT").distanceUnit, .metres)
    }

    func testABritishMacStartsInMetres() {
        // Only a US-measurement region starts in feet: the UK's system is metric with
        // exceptions, and its tables are the DM's to switch.
        XCTAssertEqual(preferences(region: "en_GB").distanceUnit, .metres)
    }

    func testAChoiceSurvivesANewInstanceAndOutranksTheRegion() {
        preferences(region: "en_US").distanceUnit = .metres

        XCTAssertEqual(preferences(region: "en_US").distanceUnit, .metres)
        XCTAssertEqual(preferences(region: "it_IT").distanceUnit, .metres)
    }

    @MainActor
    func testSwitchingTheUnitRedrawsAtOnceAndIsRemembered() {
        // Live, unlike the Interface Language: nothing is resolved at launch, so both screens
        // re-read every distance the moment the DM picks.
        let state = AppState(preferences: preferences(region: "it_IT"))
        var redraws = 0
        let subscription = state.objectWillChange.sink { redraws += 1 }

        state.distanceUnit = .feet

        XCTAssertEqual(redraws, 1)
        XCTAssertEqual(state.distanceUnit, .feet)
        XCTAssertEqual(preferences(region: "it_IT").distanceUnit, .feet)
        subscription.cancel()
    }
}
