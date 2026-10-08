import AppKit
import XCTest
@testable import MapForge

/// The Bestiary where it meets the rest of the app: OK in the Edit Pawn sheet writing two
/// files, `Add` stamping before a Creature joins a fight, and the Workspace's notes being read
/// when it opens.
@MainActor
final class BestiaryAppStateTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let gnoll = Monster(name: "Gnoll Guerriero", armorClass: 15, hitPoints: 27,
                                initiativeBonus: 1)
    private let capo = Monster(name: "Capo Goblin", armorClass: 17, hitPoints: 45,
                               initiativeBonus: 2)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BestiaryAppStateTests.\(UUID().uuidString)")
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
        state.beginEvening(in: directory)
        state.mapURL = directory.appendingPathComponent("dungeon.png")
        state.bestiary = Bestiary(monsters: [capo, gnoll])
        return state
    }

    private func creature(_ label: String, monsterName: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, monsterName: monsterName)
    }

    private func draft(for pawn: Pawn, picking monster: Monster, in state: AppState) -> EditPawnDraft {
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(monster, among: state.fog.pawns)
        return draft
    }

    // MARK: OK writes both files

    func testOKStampsTheStatBlockAndNamesTheMonster() {
        let state = makeAppState()
        let pawn = creature("1")
        state.fog.pawns = [pawn]

        state.updatePawn(id: pawn.id, with: draft(for: pawn, picking: gnoll, in: state))

        XCTAssertEqual(state.fog.pawns[0].monsterName, "Gnoll Guerriero")
        XCTAssertEqual(state.fog.pawns[0].label, "GG1")
        let block = state.statBlock(for: pawn.id)
        XCTAssertEqual(block.armorClass, 15)
        XCTAssertEqual(block.initiativeBonus, 1)
        XCTAssertEqual(block.currentHP, 27)
        XCTAssertEqual(block.maxHP, 27)
    }

    func testOKWithTheMonsterUntouchedLeavesTheWoundsAlone() {
        let state = makeAppState()
        let pawn = creature("GG1", monsterName: "Gnoll Guerriero")
        state.fog.pawns = [pawn]
        state.setStatBlock(StatBlock(armorClass: 15, currentHP: 12, maxHP: 27), for: pawn.id)

        var recolour = EditPawnDraft(pawn: pawn)
        recolour.colorHex = "#00FF00"
        state.updatePawn(id: pawn.id, with: recolour)

        XCTAssertEqual(state.statBlock(for: pawn.id).currentHP, 12)
    }

    func testAMonsterThatLeftTheBestiaryWhileTheSheetWasOpenStampsNothing() {
        let state = makeAppState()
        let pawn = creature("1")
        state.fog.pawns = [pawn]
        let picked = draft(for: pawn, picking: gnoll, in: state)
        state.bestiary = Bestiary()

        state.updatePawn(id: pawn.id, with: picked)

        XCTAssertEqual(state.statBlock(for: pawn.id), StatBlock())
    }

    func testMidFightTheStampIsRecordedAsChanges() throws {
        // ADR-0008: during an Encounter a number moves only by a Change, so the Log can say
        // when the gnoll became a Capo.
        let state = makeAppState()
        let pawn = creature("GG1", monsterName: "Gnoll Guerriero")
        state.fog.pawns = [pawn]
        state.setStatBlock(StatBlock(initiativeBonus: 1, armorClass: 15, currentHP: 12, maxHP: 27),
                           for: pawn.id)
        state.startEncounter()
        let initiative = try XCTUnwrap(state.encounter?.initiative(of: pawn.id))

        state.updatePawn(id: pawn.id, with: draft(for: pawn, picking: capo, in: state))

        let block = try XCTUnwrap(state.encounter?.blocks[pawn.id])
        XCTAssertEqual(block.currentHP, 45)
        XCTAssertEqual(block.maxHP, 45)
        XCTAssertEqual(block.armorClass, 17)
        XCTAssertEqual(block.initiativeBonus, 2,
                       "the bonus is what the next re-roll and the next fight roll with")
        XCTAssertEqual(state.encounter?.initiative(of: pawn.id), initiative,
                       "changing a bonus does not by itself move anyone")
        state.stopEncounter()
    }

    func testTheStampedBonusOutlivesTheFight() {
        // `stats.json` follows the fold, so a bonus the Log never heard of would be
        // overwritten by the old one the moment anything else was recorded.
        let state = makeAppState()
        let pawn = creature("GG1", monsterName: "Gnoll Guerriero")
        state.fog.pawns = [pawn]
        state.setStatBlock(StatBlock(initiativeBonus: 1, armorClass: 15), for: pawn.id)
        state.startEncounter()
        state.updatePawn(id: pawn.id, with: draft(for: pawn, picking: capo, in: state))
        state.stopEncounter()
        XCTAssertEqual(state.statBlock(for: pawn.id).initiativeBonus, 2)
    }

    func testStampingABystanderMidFightLeavesItABystander() {
        // On the Map, off the roster, while somebody else fights: it has no block in the
        // Encounter, so its numbers are prep and go straight to `stats.json` — through the
        // Log they would come back as a fresh block, rostered and stripped.
        let state = makeAppState()
        let fighter = creature("GG1")
        let innkeeper = creature("7")
        state.fog.pawns = [fighter, innkeeper]
        state.setStatBlock(StatBlock(temporaryHP: 4, conditions: [.prone], isInCombat: false),
                           for: innkeeper.id)
        state.startEncounter()

        state.updatePawn(id: innkeeper.id, with: draft(for: innkeeper, picking: gnoll, in: state))

        let block = state.statBlock(for: innkeeper.id)
        XCTAssertEqual(block.maxHP, 27)
        XCTAssertEqual(block.initiativeBonus, 1)
        XCTAssertFalse(block.isInCombat)
        XCTAssertEqual(block.temporaryHP, 4)
        XCTAssertEqual(block.conditions, [.prone])
        XCTAssertNil(state.encounter?.blocks[innkeeper.id])
        state.stopEncounter()
    }

    // MARK: Add

    func testAnAddedMonsterIsStampedAtFullHitPoints() {
        let state = makeAppState()
        let placed = creature("GG2", monsterName: "Gnoll Guerriero")
        state.addPawnToMap(placed)
        XCTAssertEqual(state.statBlock(for: placed.id).currentHP, 27)
        XCTAssertEqual(state.statBlock(for: placed.id).armorClass, 15)
    }

    func testAnAddedMonsterJoinsARunningFightAlreadyStamped() throws {
        // Stamped *before* it joins, so it rolls with the gnoll's bonus and the Log's
        // snapshot of it has hit points.
        let state = makeAppState()
        let first = creature("GG1", monsterName: "Gnoll Guerriero")
        state.fog.pawns = [first]
        state.startEncounter()

        let second = creature("GG2", monsterName: "Gnoll Guerriero")
        state.addPawnToMap(second)

        let block = try XCTUnwrap(state.encounter?.blocks[second.id])
        XCTAssertEqual(block.maxHP, 27)
        XCTAssertEqual(block.initiativeBonus, 1)
        state.stopEncounter()
    }

    func testAnAddedPawnThatIsNoMonsterGetsNoStatBlock() {
        let state = makeAppState()
        let placed = creature("1")
        state.addPawnToMap(placed)
        XCTAssertNil(state.statsDocument.blocks[placed.id])
    }

    // MARK: The Workspace

    func testOpeningAWorkspaceReadsItsNotesAndClosingForgetsThem() async throws {
        let root = directory.appendingPathComponent("Vault")
        let support = root.appendingPathComponent(".mapforge")
        let notes = root.appendingPathComponent("03_Bestiario")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("```statblock\nname: Wraith\nhp: 67 (9d8 + 27)\n```\n".utf8)
            .write(to: notes.appendingPathComponent("Wraith.md"))
        try Data("```statblock\nname: Durga Pietraferma\nplayer: Baldu\nhp: 48\n```\n".utf8)
            .write(to: notes.appendingPathComponent("Durga.md"))

        let state = makeAppState()
        state.open(Workspace(url: root))
        await state.bestiaryLoad?.value

        XCTAssertEqual(state.bestiary.monsters.map(\.name), ["Wraith"])
        XCTAssertEqual(state.bestiary.monsters.first?.hitPoints, 67)
        XCTAssertEqual(state.characterNotes.notes.map(\.name), ["Durga Pietraferma"])

        state.closeWorkspace()
        XCTAssertEqual(state.bestiary, .closed)
        XCTAssertEqual(state.characterNotes, CharacterNotes())
    }
}
