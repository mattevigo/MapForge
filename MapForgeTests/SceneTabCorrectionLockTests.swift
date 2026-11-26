import AppKit
import XCTest
@testable import MapForge

/// The Scene tab's Stat Editor while the Encounter's correction cursor is on a past Turn.
///
/// ADR-0010 calls correcting the most dangerous interaction in the feature: an edit made in
/// the wrong mode is silent and wrong. The Encounter tab says so with its correcting bar; the
/// Scene tab has no such bar, so its editor stands down and names the Turn being corrected,
/// sending the DM to the tab that shows it.
@MainActor
final class SceneTabCorrectionLockTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SceneTabCorrectionLockTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// A fight with Grog alone in it, so whose Turn is corrected is never in doubt.
    private func fightWithGrog() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.mapURL = directory.appendingPathComponent("cave.png")
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        state.open(Workspace(url: directory))
        state.fog.pawns = [Pawn(at: MapPoint(x: 100, y: 100), label: "Grog", colorHex: "#C81E1E",
                                brightSquares: 6, kind: .player)]
        state.startSession()
        state.startEncounter()
        return state
    }

    func testOutsideAFightTheSceneTabsEditorIsOpen() {
        XCTAssertNil(SceneTabCorrectionLock.line(for: nil))
    }

    func testOnTheLiveTurnTheSceneTabsEditorIsOpen() {
        let state = fightWithGrog()
        state.endTurn()

        XCTAssertNil(SceneTabCorrectionLock.line(for: state.encounter))
    }

    func testWhileCorrectingItNamesTheTurnAndSendsTheDMToTheEncounterTab() {
        let state = fightWithGrog()
        state.endTurn()                    // Grog's Round 1 Turn ends; Round 2 begins
        state.stepBackForCorrection()      // onto Grog's Round 1 Turn
        XCTAssertNotNil(state.encounter?.correctionTarget, "precondition: correcting")

        XCTAssertEqual(SceneTabCorrectionLock.line(for: state.encounter),
                       "Correcting Round 1, Grog's Turn — edit in the Encounter tab")
    }

    func testReturningToTheLiveTurnOpensItAgain() {
        let state = fightWithGrog()
        state.endTurn()
        state.stepBackForCorrection()

        state.endTurn()                    // Next, while correcting, walks back towards live

        XCTAssertNil(state.encounter?.correctionTarget, "precondition: back on the live Turn")
        XCTAssertNil(SceneTabCorrectionLock.line(for: state.encounter))
    }
}
