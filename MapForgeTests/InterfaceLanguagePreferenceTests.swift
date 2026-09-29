import XCTest
@testable import MapForge

/// The Interface Language is chosen per Mac (`CONTEXT.md`), so it lives beside the recents in
/// `DisplayPreferences` — and it is stored where macOS itself looks for an app's language, the
/// app's own `AppleLanguages`, so the next launch speaks it with no code of ours running first.
final class InterfaceLanguagePreferenceTests: XCTestCase {
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

    private func preferences() -> DisplayPreferences {
        DisplayPreferences(defaults: defaults, domain: suiteName)
    }

    func testAChosenLanguageSurvivesANewInstance() {
        preferences().interfaceLanguage = .italian

        XCTAssertEqual(preferences().interfaceLanguage, .italian)
    }

    func testSystemHandsTheChoiceBackToMacOS() {
        // Not English: nothing at all, so the Mac's own language list decides again.
        let preferences = preferences()
        preferences.interfaceLanguage = .german
        preferences.interfaceLanguage = .system

        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(preferences.interfaceLanguage, .system)
    }

    func testAChoiceMadeInSystemSettingsIsTheOneShown() {
        // System Settings › Language & Region › Applications writes the same key, and may
        // qualify it with a region the picker does not offer.
        defaults.set(["it-IT"], forKey: "AppleLanguages")
        XCTAssertEqual(preferences().interfaceLanguage, .italian)

        defaults.set(["pt-PT"], forKey: "AppleLanguages")
        XCTAssertEqual(preferences().interfaceLanguage, .portuguese)
    }
}
