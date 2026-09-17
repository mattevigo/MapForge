import AppKit
import XCTest
@testable import MapForge

/// A fight is one fight of an evening: no Session, no Encounter.
///
/// `CONTEXT.md` has always said an Encounter "sits *inside* a Session"; nothing enforced it,
/// so a DM could press Play during prep and get a Combat Log no Session Log pointed at — a
/// fight the Log View, which reads the evening, could never show.
@MainActor
final class EncounterNeedsASessionTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EncounterNeedsASessionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeAppState() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.open(Workspace(url: directory))
        state.mapURL = directory.appendingPathComponent("dungeon.png")
        state.fog.pawns = [Pawn(at: MapPoint(x: 100, y: 100), label: "Goblin",
                                colorHex: "#C81E1E", brightSquares: 6, kind: .creature)]
        return state
    }

    func testPlayDoesNothingBeforeTheEveningStarts() {
        let state = makeAppState()
        state.startEncounter()
        XCTAssertNil(state.encounter)
        XCTAssertNil(state.logWriter, "a refused fight must not leave a Log behind")
    }

    func testPlayStartsAFightOnceTheEveningHas() {
        let state = makeAppState()
        state.startSession()
        state.startEncounter()
        XCTAssertNotNil(state.encounter)
        state.stopEncounter()
        state.stopSession()
    }

    func testTheRefusalSaysWhy() {
        let state = makeAppState()
        XCTAssertEqual(state.encounterRefusal, "Start a Session first — a fight is part of an evening.")
        state.startSession()
        XCTAssertNil(state.encounterRefusal)
        state.stopSession()
    }

    func testAFightAlreadyRunningIsNotEndedByTheRule() {
        // The rule is about *starting*. A fight resumed from its Log when the Map reopens,
        // or one whose Session the DM stopped mid-fight, carries on.
        let state = makeAppState()
        state.startSession()
        state.startEncounter()
        state.stopSession()
        XCTAssertNotNil(state.encounter)
        state.stopEncounter()
    }
}
