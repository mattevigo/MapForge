import AppKit
import XCTest
@testable import MapForge

/// The one Pawn the Stat Editor is pointed at, shared by the Scene tab and the Encounter tab.
///
/// One pointer rather than one per tab, so switching tabs keeps the same Pawn in the editor:
/// a DM who clicked the goblin in the Scene tab and turns to the Encounter tab is still
/// editing the goblin. A fight ending clears it whichever tab is showing, because the rule
/// (`CombatSelectionPolicy`) is about the fight, not about the tab.
@MainActor
final class StatEditorPointerTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatEditorPointerTests.\(UUID().uuidString)")
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
        state.mapURL = directory.appendingPathComponent("cave.png")
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        state.open(Workspace(url: directory))
        return state
    }

    private func pawn(_ label: String, kind: PawnKind = .creature) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 0, kind: kind)
    }

    func testNothingIsPointedAtUntilTheDMClicksARow() {
        XCTAssertNil(makeAppState().statEditorPawn)
    }

    /// Outside a fight the editor edits exactly what the DM pointed at, and nothing when
    /// they pointed at nothing — there is no Turn to fall back on.
    func testOutsideAFightTheEditorEditsThePawnPointedAt() {
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]
        XCTAssertNil(state.statEditorSubject)

        state.statEditorPawn = goblin.id

        XCTAssertEqual(state.statEditorSubject, goblin.id)
    }

    /// During a fight, a DM who has pointed at nobody edits whoever's Turn it is — the
    /// Encounter tab's editor always did, and the Scene tab's reads the same subject.
    func testDuringAFightWithNothingPointedAtTheEditorEditsTheActiveCombatant() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", kind: .player)]
        state.startSession()
        state.startEncounter()
        let active = try XCTUnwrap(state.encounter?.activeCombatantID)

        XCTAssertEqual(state.statEditorSubject, active)
    }

    func testDuringAFightThePawnPointedAtWinsOverTheActiveCombatant() throws {
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let goblin = pawn("Goblin")
        state.fog.pawns = [grog, goblin]
        state.startSession()
        state.startEncounter()
        let active = try XCTUnwrap(state.encounter?.activeCombatantID)
        let other = active == grog.id ? goblin.id : grog.id

        state.statEditorPawn = other

        XCTAssertEqual(state.statEditorSubject, other)
    }

    /// `CombatSelectionPolicy`: a fight ending leaves nothing pointed at — in both tabs,
    /// since there is one pointer, and whichever tab happens to be showing.
    func testStoppingAFightClearsThePointer() {
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]
        state.startSession()
        state.startEncounter()
        state.statEditorPawn = goblin.id

        state.stopEncounter()

        XCTAssertNil(state.statEditorPawn)
        XCTAssertNil(state.statEditorSubject)
    }

    /// Every way a fight can end arrives as `encounter` becoming nil — closing the Map
    /// included, which flushes the fight rather than stopping it.
    func testAFightEndingByAnyRouteClearsThePointer() {
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]
        state.startSession()
        state.startEncounter()
        state.statEditorPawn = goblin.id

        state.loadMap(image: NSImage(size: NSSize(width: 500, height: 500)),
                      at: directory.appendingPathComponent("tavern.png"))

        XCTAssertNil(state.statEditorPawn)
    }

    /// Turns going by is the fight going on, not ending: the DM's pointer stays put.
    func testEndingATurnKeepsThePointer() {
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let goblin = pawn("Goblin")
        state.fog.pawns = [grog, goblin]
        state.startSession()
        state.startEncounter()
        state.statEditorPawn = goblin.id

        state.endTurn()

        XCTAssertEqual(state.statEditorPawn, goblin.id)
    }

    /// Clearing what is pointed *at* is not touching what it points *to*: stopping a fight
    /// is not a rest (`CONTEXT.md`, **Encounter**).
    func testClearingThePointerTouchesNoStatBlock() {
        let state = makeAppState()
        let goblin = pawn("Goblin")
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(currentHP: 4, maxHP: 7), for: goblin.id)
        state.startSession()
        state.startEncounter()
        state.statEditorPawn = goblin.id

        state.stopEncounter()

        XCTAssertEqual(state.statBlock(for: goblin.id).currentHP, 4)
    }
}
