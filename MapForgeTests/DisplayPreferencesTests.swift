import XCTest
@testable import MapForge

final class DisplayPreferencesTests: XCTestCase {
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

    func testNothingRememberedInitially() {
        XCTAssertNil(DisplayPreferences(defaults: defaults).rememberedPlayerDisplay)
    }

    func testChoiceSurvivesANewInstance() {
        // The point of the type: a relaunch resolves the same display with no interaction.
        let identity = DisplayIdentity(uuid: "uuid-tv", name: "LG TV")
        DisplayPreferences(defaults: defaults).rememberedPlayerDisplay = identity
        XCTAssertEqual(DisplayPreferences(defaults: defaults).rememberedPlayerDisplay, identity)
    }

    func testChoiceCanBeCleared() {
        let preferences = DisplayPreferences(defaults: defaults)
        preferences.rememberedPlayerDisplay = DisplayIdentity(uuid: "uuid-tv", name: "LG TV")
        preferences.rememberedPlayerDisplay = nil
        XCTAssertNil(preferences.rememberedPlayerDisplay)
    }

    func testMissingNameStillResolvesTheUUID() {
        // Matching is by UUID; the name is a label, so a half-written pair still works.
        defaults.set("uuid-tv", forKey: "playerDisplayUUID")
        XCTAssertEqual(DisplayPreferences(defaults: defaults).rememberedPlayerDisplay?.uuid, "uuid-tv")
    }
}
