import XCTest
@testable import MapForge

final class PlayerScreenPolicyTests: XCTestCase {
    private let tv = DisplayIdentity(uuid: "uuid-tv", name: "LG TV")
    private let otherTV = DisplayIdentity(uuid: "uuid-other", name: "Samsung TV")
    private let laptop = DisplayIdentity(uuid: "uuid-builtin", name: "Built-in Retina Display")

    private func candidate(_ identity: DisplayIdentity, builtin: Bool = false,
                           metrics: DisplayMetrics? = DisplayMetrics(pixelSize: CGSize(width: 2000, height: 1200),
                                                                     physicalSizeMM: CGSize(width: 508, height: 304.8),
                                                                     backingScaleFactor: 2)) -> DisplayCandidate {
        DisplayCandidate(identity: identity, isBuiltin: builtin, metrics: metrics)
    }

    // MARK: Auto-selection

    func testSoleExternalScreenIsChosenWithNoPreference() {
        let candidates = [candidate(laptop, builtin: true), candidate(tv)]
        let chosen = PlayerScreenPolicy.resolve(candidates: candidates, explicit: nil, remembered: nil)
        XCTAssertEqual(chosen?.identity, tv)
    }

    func testBuiltinAloneIsNeverAutoChosen() {
        // The built-in is selectable, but only ever explicitly — a Map must not appear
        // on the DM's own screen just because no TV is attached.
        let chosen = PlayerScreenPolicy.resolve(candidates: [candidate(laptop, builtin: true)],
                                                explicit: nil, remembered: nil)
        XCTAssertNil(chosen)
    }

    func testTwoUnrecognisedExternalsPresentNothing() {
        let candidates = [candidate(tv), candidate(otherTV)]
        XCTAssertNil(PlayerScreenPolicy.resolve(candidates: candidates, explicit: nil, remembered: nil))
    }

    func testNoScreensPresentNothing() {
        XCTAssertNil(PlayerScreenPolicy.resolve(candidates: [], explicit: nil, remembered: nil))
    }

    // MARK: Remembered

    func testRememberedScreenWinsOverTheOtherOfTwo() {
        let candidates = [candidate(tv), candidate(otherTV)]
        let chosen = PlayerScreenPolicy.resolve(candidates: candidates, explicit: nil, remembered: otherTV)
        XCTAssertEqual(chosen?.identity, otherTV)
    }

    func testDisconnectedRememberedScreenFallsBackToSoleExternal() {
        let candidates = [candidate(laptop, builtin: true), candidate(tv)]
        let chosen = PlayerScreenPolicy.resolve(candidates: candidates, explicit: nil, remembered: otherTV)
        XCTAssertEqual(chosen?.identity, tv)
    }

    func testDisconnectedRememberedScreenDoesNotGuessAmongTwo() {
        let candidates = [candidate(tv), candidate(otherTV)]
        let absent = DisplayIdentity(uuid: "uuid-absent", name: "Old TV")
        XCTAssertNil(PlayerScreenPolicy.resolve(candidates: candidates, explicit: nil, remembered: absent))
    }

    func testRememberedMatchesByUUIDNotName() {
        // A renamed display is still the same glass.
        let renamed = DisplayIdentity(uuid: tv.uuid, name: "Living Room TV")
        let chosen = PlayerScreenPolicy.resolve(candidates: [candidate(renamed), candidate(otherTV)],
                                                explicit: nil, remembered: tv)
        XCTAssertEqual(chosen?.identity.uuid, tv.uuid)
    }

    // MARK: Explicit

    func testExplicitChoiceBeatsRemembered() {
        let candidates = [candidate(tv), candidate(otherTV)]
        let chosen = PlayerScreenPolicy.resolve(candidates: candidates, explicit: tv, remembered: otherTV)
        XCTAssertEqual(chosen?.identity, tv)
    }

    func testExplicitChoiceBeatsSoleExternalAutoPick() {
        let candidates = [candidate(laptop, builtin: true), candidate(tv)]
        let chosen = PlayerScreenPolicy.resolve(candidates: candidates, explicit: laptop, remembered: nil)
        XCTAssertEqual(chosen?.identity, laptop)
    }

    func testDisconnectedExplicitChoiceFallsBackToRemembered() {
        let candidates = [candidate(tv), candidate(otherTV)]
        let absent = DisplayIdentity(uuid: "uuid-absent", name: "Old TV")
        let chosen = PlayerScreenPolicy.resolve(candidates: candidates, explicit: absent, remembered: otherTV)
        XCTAssertEqual(chosen?.identity, otherTV)
    }

    // MARK: Screens with no EDID size

    func testScreenWithoutPhysicalSizeIsStillChosen() {
        // Presentable — True Scale is a guess until Calibration, flagged in the UI.
        let chosen = PlayerScreenPolicy.resolve(candidates: [candidate(tv, metrics: nil)],
                                                explicit: nil, remembered: nil)
        XCTAssertEqual(chosen?.identity, tv)
        XCTAssertFalse(chosen?.hasKnownPhysicalSize ?? true)
    }
}
