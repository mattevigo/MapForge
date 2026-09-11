import AppKit
import XCTest
@testable import MapForge

/// Choosing who a fight starts with.
///
/// A Pawn is on the Map whether or not it is in the next fight — the innkeeper standing
/// behind the bar while the party brawls in front of it is still a Pawn. The roster is what
/// says which of them roll when the DM presses play, and it is remembered per Map because
/// a dungeon's regulars do not change between sessions.
@MainActor
final class CombatRosterTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CombatRosterTests.\(UUID().uuidString)")
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

    private func pawn(_ label: String, kind: PawnKind = .creature) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind)
    }

    // MARK: What the roster decides

    func testOnlyRosteredPawnsRollWhenTheFightStarts() {
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let barkeep = pawn("Barkeep", kind: .creature)
        state.fog.pawns = [grog, barkeep]
        state.setInCombat(false, for: barkeep.id)

        state.startEncounter()

        XCTAssertEqual(state.encounter?.order, [grog.id])
        XCTAssertFalse(state.encounter?.order.contains(barkeep.id) ?? true)
    }

    func testAPawnLeftOutIsListedAsNotInCombat() {
        // It is on the Map, so the tracker shows it — a DM needs to see the whole room.
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let barkeep = pawn("Barkeep")
        state.fog.pawns = [grog, barkeep]
        state.setInCombat(false, for: barkeep.id)

        state.startEncounter()

        XCTAssertTrue(state.notInCombat.contains(barkeep.id))
    }

    func testAPawnLeftOutCanStillBePutIn() {
        // The bench's way in works for it, because it is on the bench.
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let barkeep = pawn("Barkeep")
        state.fog.pawns = [grog, barkeep]
        state.setInCombat(false, for: barkeep.id)
        state.startEncounter()

        state.unbenchCombatant(barkeep.id)

        XCTAssertTrue(state.encounter?.order.contains(barkeep.id) ?? false)
    }

    func testAFightWithNobodyRosteredDoesNotStart() {
        // Better than an empty tracker.
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        state.fog.pawns = [grog]
        state.setInCombat(false, for: grog.id)

        state.startEncounter()

        XCTAssertNil(state.encounter)
    }

    // MARK: Defaults

    func testEveryPawnIsInCombatUntilSaidOtherwise() {
        // A Map nobody has set up behaves as the app did before the roster existed: press
        // play and everyone rolls.
        let state = makeAppState()
        let grog = pawn("Grog", kind: .player)
        let goblin = pawn("Goblin")
        state.fog.pawns = [grog, goblin]

        XCTAssertTrue(state.isInCombat(grog.id))
        XCTAssertTrue(state.isInCombat(goblin.id))
        state.startEncounter()
        XCTAssertEqual(state.encounter?.order.count, 2)
    }

    func testTreasureIsNeverInCombatWhateverTheRosterSays() {
        // It has nothing to do on its turn, and a checkbox cannot argue with that.
        let state = makeAppState()
        let chest = pawn("Chest", kind: .treasure)
        state.fog.pawns = [pawn("Grog", kind: .player), chest]
        state.setInCombat(true, for: chest.id)

        state.startEncounter()

        XCTAssertFalse(state.encounter?.order.contains(chest.id) ?? true)
    }

    // MARK: Remembered per Map

    func testTheRosterSurvivesAReload() {
        // A dungeon's regulars do not change between sessions.
        let state = makeAppState()
        let barkeep = pawn("Barkeep")
        state.fog.pawns = [barkeep]
        state.setInCombat(false, for: barkeep.id)
        state.flushPendingStatWrites()

        let reopened = makeAppState()
        reopened.loadStats(forMapAt: mapURL)
        XCTAssertFalse(reopened.isInCombat(barkeep.id))
    }

    func testTheRosterIsPartOfTheStatBlockOnDisk() throws {
        // Beside the hit points rather than in a file of its own: both answer "what is this
        // Pawn in a fight", and one of them being absent is not a different question.
        let state = makeAppState()
        let barkeep = pawn("Barkeep")
        state.fog.pawns = [barkeep]
        state.setInCombat(false, for: barkeep.id)
        state.flushPendingStatWrites()

        let text = try String(contentsOf: StatsStore.statsURL(forMapAt: mapURL), encoding: .utf8)
        XCTAssertTrue(text.contains("isInCombat"), "the roster should be readable in the file")
    }

    func testAStatBlockWrittenBeforeTheRosterExistedReadsAsInCombat() throws {
        // Every Pawn in a file written before this feature was fighting, because there was
        // no way to say otherwise.
        let folder = StatsStore.combatDirectory(forMapAt: mapURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID()
        try Data("""
        {"version":1,"blocks":[{"pawnID":"\(id.uuidString)",\
        "block":{"armorClass":15,"currentHP":7,"maxHP":7,"temporaryHP":0,\
        "conditions":[],"exhaustion":0,"isConcentrating":false,"initiativeBonus":0}}]}
        """.utf8).write(to: StatsStore.statsURL(forMapAt: mapURL))

        let state = makeAppState()
        state.loadStats(forMapAt: mapURL)

        XCTAssertTrue(state.isInCombat(id))
        XCTAssertEqual(state.statBlock(for: id).currentHP, 7, "the rest of the block still reads")
    }
}
