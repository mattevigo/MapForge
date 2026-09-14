import AppKit
import XCTest
@testable import MapForge

/// The Encounter where it meets the rest of the app: starting one from the Pawns on the
/// Map, Stat Blocks reaching disk, and the Combat Log being written as Turns end.
@MainActor
final class EncounterAppStateTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EncounterAppStateTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
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
        state.mapURL = mapURL
        return state
    }

    private func pawn(_ label: String, kind: PawnKind) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind)
    }

    // MARK: Starting

    func testStartingRollsForThePawnsOnTheMap() {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", kind: .player), pawn("Goblin", kind: .creature)]

        state.startEncounter()

        XCTAssertNotNil(state.encounter)
        XCTAssertEqual(state.encounter?.order.count, 2)
    }

    func testTreasureIsLeftOutOfTheOrder() {
        // It has nothing to do on its turn.
        let state = makeAppState()
        let chest = pawn("Chest", kind: .treasure)
        state.fog.pawns = [pawn("Grog", kind: .player), chest]

        state.startEncounter()

        XCTAssertEqual(state.encounter?.order, state.encounter?.order.filter { $0 != chest.id })
        XCTAssertEqual(state.encounter?.order.count, 1)
    }

    func testACombatantTakesTheStatBlockItAlreadyHad() {
        // A DM who filled in a monster's hit points during prep does not retype them when
        // the fight starts.
        let state = makeAppState()
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(armorClass: 15, currentHP: 7, maxHP: 7), for: goblin.id)

        state.startEncounter()

        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.currentHP, 7)
        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.armorClass, 15)
    }

    func testStartingWithNoPawnsDoesNothing() {
        // Nothing to fight. Offering an empty tracker would be worse than refusing.
        let state = makeAppState()
        state.startEncounter()
        XCTAssertNil(state.encounter)
    }

    // MARK: Stat Blocks reaching disk

    func testAStatBlockSurvivesAReload() {
        let state = makeAppState()
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(armorClass: 15, currentHP: 7, maxHP: 7), for: goblin.id)
        state.flushPendingStatWrites()

        let reopened = makeAppState()
        reopened.loadStats(forMapAt: mapURL)
        XCTAssertEqual(reopened.statBlock(for: goblin.id).currentHP, 7)
    }

    func testAPawnWithNoStatBlockReadsAsDefaults() {
        // Never nil at the call site: a Creature stamped and not filled in is AC 10 with
        // no hit points, which is what the tracker flags rather than refuses.
        let state = makeAppState()
        let block = state.statBlock(for: UUID())
        XCTAssertEqual(block.armorClass, 10)
        XCTAssertFalse(block.isComplete)
    }

    // MARK: The Combat Log reaching disk

    func testEndingATurnWritesALine() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", kind: .player)]
        state.startEncounter()

        state.endTurn()

        let url = try XCTUnwrap(CombatLogReader().newestLogURL(forMapAt: mapURL))
        let lines = try CombatLogReader().read(at: url)
        XCTAssertTrue(lines.contains { if case .turn = $0 { return true } else { return false } },
                      "the Turn that ended is not in the file")
    }

    func testTheLogIsWrittenTheMomentATurnEndsRatherThanBeingDebounced() throws {
        // A Turn ending is the durability boundary the whole format is built on, so unlike
        // fog there is nothing to flush.
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", kind: .player)]
        state.startEncounter()
        state.recordChange(.hpChanged(combatantID: state.fog.pawns[0].id, from: 26, to: 20))
        state.endTurn()

        let url = try XCTUnwrap(CombatLogReader().newestLogURL(forMapAt: mapURL))
        XCTAssertFalse(try CombatLogReader().read(at: url).isEmpty)
    }

    func testStoppingClosesTheLog() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", kind: .player)]
        state.startEncounter()
        state.stopEncounter()

        XCTAssertNil(state.encounter, "the tracker is empty once the fight is over")
        let url = try XCTUnwrap(CombatLogReader().newestLogURL(forMapAt: mapURL))
        let lines = try CombatLogReader().read(at: url)
        XCTAssertTrue(lines.contains { if case .encounterEnded = $0 { return true } else { return false } })
    }

    func testStoppingLeavesTheStatBlocksAlone() {
        // A fight ending is not a rest. The state a party fought three Rounds to reach is
        // the state they are in.
        let state = makeAppState()
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: goblin.id)
        state.startEncounter()
        state.recordChange(.hpChanged(combatantID: goblin.id, from: 7, to: 2))
        state.recordChange(.conditionAdded(combatantID: goblin.id, condition: .prone))
        state.stopEncounter()

        XCTAssertEqual(state.statBlock(for: goblin.id).currentHP, 2)
        XCTAssertTrue(state.statBlock(for: goblin.id).conditions.contains(.prone))
    }

    // MARK: Resuming

    func testAnUnfinishedFightResumesWhenTheMapReopens() throws {
        // The payoff of the whole format: a DM who closed the laptop mid-fight gets the
        // Round, the Order and every hit point back.
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let goblin = pawn("Goblin", kind: .creature)
        state.fog.pawns = [grog, goblin]
        state.setStatBlock(StatBlock(currentHP: 26, maxHP: 26), for: grog.id)
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: goblin.id)
        state.startEncounter()
        state.recordChange(.hpChanged(combatantID: goblin.id, from: 7, to: 3))
        state.endTurn()

        let resumed = makeAppState()
        resumed.fog.pawns = [grog, goblin]
        resumed.resumeEncounter(forMapAt: mapURL)

        XCTAssertNotNil(resumed.encounter, "the fight did not come back")
        XCTAssertEqual(resumed.encounter?.blocks[goblin.id]?.currentHP, 3)
        XCTAssertEqual(resumed.encounter?.order.count, 2)
    }

    func testAFinishedFightDoesNotResume() {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", kind: .player)]
        state.startEncounter()
        state.stopEncounter()

        let resumed = makeAppState()
        resumed.resumeEncounter(forMapAt: mapURL)
        XCTAssertNil(resumed.encounter)
    }

    func testAMapNobodyHasFoughtOnResumesNothing() {
        let state = makeAppState()
        state.resumeEncounter(forMapAt: mapURL)
        XCTAssertNil(state.encounter)
    }
}
