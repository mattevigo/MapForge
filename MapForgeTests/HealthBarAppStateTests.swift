import XCTest
@testable import MapForge

/// Which Pawns the Player Display draws a Health Bar under, as `AppState` hands them to it
/// (ADR-0036).
///
/// The rule itself is `PlayerVisibility`'s and is tested there; these pin the wiring — that
/// the table-wide switch, the per-Pawn setting and the numbers the DM is editing right now
/// all reach it, so the screen cannot disagree with the rule by being handed the wrong facts.
@MainActor
final class HealthBarAppStateTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HealthBarAppStateTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "HealthBarAppStateTests.\(UUID().uuidString)"
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
        state.beginEvening(in: directory)
        state.mapURL = directory.appendingPathComponent("dungeon.png")
        return state
    }

    private func pawn(_ label: String, kind: PawnKind, isHidden: Bool = false) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind, isHidden: isHidden)
    }

    func testTheTableSeesHealthBarsAtLaunch() {
        XCTAssertTrue(makeAppState().areHealthBarsOn)
    }

    func testAPlayerAndACreatureWithCompleteStatBlocksEachGetABar() {
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let goblin = pawn("Goblin", kind: .creature)
        let chest = pawn("Chest", kind: .treasure)
        let stranger = pawn("Stranger", kind: .creature)
        state.fog.pawns = [grog, goblin, chest, stranger]
        state.setStatBlock(StatBlock(currentHP: 30, maxHP: 40), for: grog.id)
        state.setStatBlock(StatBlock(currentHP: 1, maxHP: 7), for: goblin.id)
        state.setStatBlock(StatBlock(currentHP: 10, maxHP: 10), for: chest.id)
        // Hit points typed in, no maximum: the table would be told a fraction of nothing.
        state.setStatBlock(StatBlock(currentHP: 5), for: stranger.id)

        let bars = state.playerHealthBars

        XCTAssertEqual(Set(bars.keys), [grog.id, goblin.id])
        XCTAssertEqual(bars[grog.id]?.tier, .healthy)
        XCTAssertEqual(bars[goblin.id]?.tier, .critical)
    }

    // MARK: What turns a bar off

    func testTurningTheSwitchOffRemovesEveryBar() {
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [grog, goblin]
        state.setStatBlock(StatBlock(currentHP: 30, maxHP: 40), for: grog.id)
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: goblin.id)
        XCTAssertEqual(state.playerHealthBars.count, 2, "precondition: two bars to hide")

        state.areHealthBarsOn = false

        XCTAssertTrue(state.playerHealthBars.isEmpty)
    }

    func testAPawnWhoseOwnSettingIsOffShowsNoBar() {
        let state = makeAppState()
        let lich = pawn("Lich", kind: .creature)
        state.fog.pawns = [lich]
        state.setStatBlock(StatBlock(currentHP: 80, maxHP: 135, showsHealthBarToPlayers: false),
                           for: lich.id)

        XCTAssertNil(state.playerHealthBars[lich.id])
    }

    func testAHiddenPawnShowsNoBar() {
        let state = makeAppState()
        let ambusher = pawn("Ambusher", kind: .creature, isHidden: true)
        state.fog.pawns = [ambusher]
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: ambusher.id)

        XCTAssertNil(state.playerHealthBars[ambusher.id])
    }

    /// A 1000-pixel Map declared as 20 squares, so the fog is real: a Grid, an Overlay,
    /// and darkness wherever no light reaches.
    private func makeAppStateWithFog() -> AppState {
        let state = makeAppState()
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        return state
    }

    func testACreatureInTheDarkShowsNoBar() {
        let state = makeAppStateWithFog()
        let torchbearer = pawn("Grog", kind: .player)          // lights (100, 100)
        var lurker = pawn("Lurker", kind: .creature)
        lurker.at = MapPoint(x: 900, y: 700)                    // far past the torch
        state.fog.pawns = [torchbearer, lurker]
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: lurker.id)
        XCTAssertFalse(state.litRegions.isEmpty, "precondition: the fog is being drawn")

        XCTAssertNil(state.playerHealthBars[lurker.id])
    }

    func testAPawnExcludedBySoloSightShowsNoBar() {
        let state = makeAppStateWithFog()
        let scout = pawn("Scout", kind: .player)
        // Carrying no light of their own, and beyond the Scout's.
        let straggler = Pawn(at: MapPoint(x: 900, y: 700), label: "Straggler",
                             colorHex: "#C81E1E", brightSquares: 0, kind: .player)
        state.fog.pawns = [scout, straggler]
        state.setStatBlock(StatBlock(currentHP: 20, maxHP: 20), for: scout.id)
        state.setStatBlock(StatBlock(currentHP: 20, maxHP: 20), for: straggler.id)
        XCTAssertNotNil(state.playerHealthBars[straggler.id],
                        "precondition: a party Pawn shows its bar before Solo Sight")

        state.setSoloSight(id: scout.id)

        XCTAssertNil(state.playerHealthBars[straggler.id])
        XCTAssertNotNil(state.playerHealthBars[scout.id], "the isolated Pawn keeps its bar")
    }

    // MARK: Live

    /// Mid-fight a number moves only by a Change recorded into the Log (ADR-0008). The bar
    /// must move with it, not wait for anything — the table watches the goblin go red as
    /// the DM types the wound.
    func testDuringAnEncounterTheBarFollowsTheDMsEditsAtOnce() {
        let state = makeAppState()
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(currentHP: 8, maxHP: 8), for: goblin.id)
        state.startEncounter()
        XCTAssertEqual(state.playerHealthBars[goblin.id]?.tier, .healthy, "precondition")

        state.editStatBlock(for: goblin.id) { $0.currentHP = 2 }

        XCTAssertEqual(state.playerHealthBars[goblin.id]?.fill, 0.25)
        XCTAssertEqual(state.playerHealthBars[goblin.id]?.tier, .critical)
    }

    /// The fight's numbers, but the DM's setting: the Log's copy of it is frozen at the
    /// moment the Pawn joined, because withholding a bar is not a Change (ADR-0036). Read
    /// from that copy, the bar would stay on the table after the DM withheld it — or come
    /// back with the next wound.
    func testABarWithheldMidEncounterLeavesTheTableAndStaysGoneAfterAHit() {
        let state = makeAppState()
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(currentHP: 8, maxHP: 8), for: goblin.id)
        state.startEncounter()
        XCTAssertNotNil(state.playerHealthBars[goblin.id], "precondition")

        state.setShowsHealthBarToPlayers(false, for: goblin.id)
        XCTAssertNil(state.playerHealthBars[goblin.id], "withholding it left the bar up")

        state.editStatBlock(for: goblin.id) { $0.currentHP = 3 }
        XCTAssertEqual(state.liveStatBlock(for: goblin.id).currentHP, 3, "precondition: the hit landed")
        XCTAssertNil(state.playerHealthBars[goblin.id], "a Change gave the bar back")
    }

    func testOutsideAnEncounterTheBarFollowsTheDMsEditsToo() {
        let state = makeAppState()
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(currentHP: 8, maxHP: 8), for: goblin.id)

        state.editStatBlock(for: goblin.id) { $0.currentHP = 4 }

        XCTAssertEqual(state.playerHealthBars[goblin.id]?.tier, .bloodied)
    }
}
