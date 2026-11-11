import XCTest
@testable import MapForge

/// A new Interface Language applies at the next launch, so Settings says so — but only when
/// the next launch would really speak differently from this one. A notice for a relaunch
/// that changes nothing teaches the DM to ignore it.
final class RelaunchNoticeTests: XCTestCase {
    func testChoosingAnotherLanguageTakesEffectAtTheNextLaunch() {
        XCTAssertEqual(InterfaceLanguage.nextLaunch(chosen: .italian, running: "en",
                                                    macLanguages: ["en-GB"]),
                       .italian)
    }

    func testTheLanguageAlreadySpokenNeedsNoRelaunch() {
        XCTAssertNil(InterfaceLanguage.nextLaunch(chosen: .italian, running: "it",
                                                  macLanguages: ["en-GB"]))
    }

    func testSystemIsWhateverTheMacsOwnListResolvesTo() {
        // A DM who chose Deutsch and goes back to System on an Italian Mac gets Italian next
        // time — so that is what the notice names, not "System".
        XCTAssertEqual(InterfaceLanguage.nextLaunch(chosen: .system, running: "de",
                                                    macLanguages: ["it-IT", "en-GB"]),
                       .italian)
        XCTAssertNil(InterfaceLanguage.nextLaunch(chosen: .system, running: "it",
                                                  macLanguages: ["it-IT", "en-GB"]))
    }

    func testAMacLanguageMapForgeDoesNotSpeakFallsBackToEnglish() {
        XCTAssertNil(InterfaceLanguage.nextLaunch(chosen: .system, running: "en",
                                                  macLanguages: ["ja-JP"]))
    }
}
