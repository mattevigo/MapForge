import AppKit
import XCTest
@testable import MapForge

/// The DM withholding one Pawn's **Health Bar** for good, from the Edit Pawn sheet (ADR-0036).
///
/// Asserted where it meets the rest of the app — the sheet's OK through `updatePawn`, Add
/// through `addPawnToMap` — because what matters is what the Player Display is then told,
/// and that neither Log hears of it: whether the table could see a bar is not something
/// that happened in the fight.
@MainActor
final class EditPawnHealthBarTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EditPawnHealthBarTests.\(UUID().uuidString)")
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
        state.beginEvening(in: directory)
        state.mapURL = directory.appendingPathComponent("dungeon.png")
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        return state
    }

    private func mimic(_ label: String = "1", in state: AppState) -> Pawn {
        let pawn = Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
                        brightSquares: 6, kind: .creature)
        state.fog.pawns.append(pawn)
        state.setStatBlock(StatBlock(currentHP: 58, maxHP: 58), for: pawn.id)
        return pawn
    }

    /// The sheet as `ControlView` opens it: seeded from the Pawn and its Stat Block.
    private func sheet(for pawn: Pawn, in state: AppState) -> EditPawnDraft {
        EditPawnDraft(pawn: pawn,
                      showsHealthBarToPlayers: state.statBlock(for: pawn.id).showsHealthBarToPlayers)
    }

    /// What the Player Display is told about `pawn`, with everything else in its favour: the
    /// fog off, so only the bar's own rules can say no.
    private func tableSeesBar(of pawn: Pawn, in state: AppState) -> Bool {
        PlayerVisibility.showsHealthBarToPlayers(pawn: pawn, stats: state.statBlock(for: pawn.id),
                                                 regions: [], isFogOverlayOn: false,
                                                 hasVisibility: false, soloSightPawnID: nil,
                                                 areHealthBarsOn: true)
    }

    // MARK: OK and Cancel

    func testTurningTheToggleOffAndSavingWithholdsTheBar() {
        let state = makeAppState()
        let pawn = mimic(in: state)
        XCTAssertTrue(tableSeesBar(of: pawn, in: state), "precondition: the bar is shown")

        var draft = sheet(for: pawn, in: state)
        draft.showsHealthBarToPlayers = false
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertFalse(state.statBlock(for: pawn.id).showsHealthBarToPlayers)
        XCTAssertFalse(tableSeesBar(of: pawn, in: state))
    }

    /// Cancel is the sheet never committing: the draft is dropped, and the Stat Block is as
    /// it was.
    func testCancellingLeavesTheBarAsItWas() {
        let state = makeAppState()
        let pawn = mimic(in: state)

        var draft = sheet(for: pawn, in: state)
        draft.showsHealthBarToPlayers = false

        XCTAssertTrue(state.statBlock(for: pawn.id).showsHealthBarToPlayers)
        XCTAssertTrue(tableSeesBar(of: pawn, in: state))
    }

    func testTheSheetOpensShowingAWithheldBarAsWithheld() {
        let state = makeAppState()
        let pawn = mimic(in: state)
        state.setShowsHealthBarToPlayers(false, for: pawn.id)

        XCTAssertFalse(sheet(for: pawn, in: state).showsHealthBarToPlayers)
    }

    func testTurningItBackOnShowsTheBarAgain() {
        let state = makeAppState()
        let pawn = mimic(in: state)
        state.setShowsHealthBarToPlayers(false, for: pawn.id)

        var draft = sheet(for: pawn, in: state)
        draft.showsHealthBarToPlayers = true
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertTrue(tableSeesBar(of: pawn, in: state))
    }

    /// OK on a sheet opened to change a colour must not give a Pawn with no numbers a Stat
    /// Block it never had.
    func testSavingWithTheToggleUntouchedWritesNoStatBlock() {
        let state = makeAppState()
        let pawn = Pawn(at: MapPoint(x: 100, y: 100), label: "1", colorHex: "#C81E1E",
                        brightSquares: 6, kind: .creature)
        state.fog.pawns = [pawn]

        var draft = sheet(for: pawn, in: state)
        draft.colorHex = "#1E88C8"
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertNil(state.statsDocument.blocks[pawn.id])
    }

    // MARK: Treasure

    func testTheToggleIsOfferedForPlayersAndCreaturesButNotForATreasure() {
        let state = makeAppState()
        let pawn = mimic(in: state)
        var draft = sheet(for: pawn, in: state)
        XCTAssertTrue(draft.offersHealthBar)
        draft.kind = .player
        XCTAssertTrue(draft.offersHealthBar)
        draft.kind = .treasure
        XCTAssertFalse(draft.offersHealthBar)
    }

    /// A setting the DM can no longer see is not one they chose: the toggle went with the
    /// Kind, and OK writes nothing for it.
    func testACreatureMadeATreasureKeepsTheSettingItHad() {
        let state = makeAppState()
        let pawn = mimic(in: state)

        var draft = sheet(for: pawn, in: state)
        draft.showsHealthBarToPlayers = false
        draft.kind = .treasure
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertTrue(state.statBlock(for: pawn.id).showsHealthBarToPlayers)
    }

    // MARK: Nothing is logged

    private func sessionLines(_ state: AppState) throws -> [SessionLine] {
        guard let url = state.sessionLogURL else { return [] }
        return try SessionLogReader().read(at: url)
    }

    private func withhold(_ pawn: Pawn, in state: AppState) {
        var draft = sheet(for: pawn, in: state)
        draft.showsHealthBarToPlayers = false
        state.updatePawn(id: pawn.id, with: draft)
    }

    func testWithholdingABarWritesNoSessionLogLine() throws {
        let state = makeAppState()
        state.startSession()
        let pawn = mimic(in: state)
        let before = try sessionLines(state)

        withhold(pawn, in: state)

        XCTAssertEqual(try sessionLines(state), before)
    }

    func testWithholdingABarMidFightWritesNothingToTheCombatLog() throws {
        let state = makeAppState()
        state.startSession()
        let pawn = mimic(in: state)
        state.startEncounter()
        let encounter = try XCTUnwrap(state.encounter)

        withhold(pawn, in: state)

        XCTAssertEqual(state.encounter?.lines, encounter.lines)
        XCTAssertEqual(state.encounter?.pendingChanges, encounter.pendingChanges)
        XCTAssertFalse(tableSeesBar(of: pawn, in: state))
        state.stopEncounter()
    }

    /// The Log is the fight's authority on every number, and every Change copies its blocks
    /// beside the Map — but it never held this setting, so it must not take it back.
    func testABarWithheldMidFightStaysWithheldThroughTheFightAndAfterIt() throws {
        let state = makeAppState()
        state.startSession()
        let pawn = mimic(in: state)
        state.startEncounter()

        withhold(pawn, in: state)
        state.editStatBlock(for: pawn.id) { $0.currentHP = 20 }

        XCTAssertEqual(state.statBlock(for: pawn.id).currentHP, 20, "precondition: the hit landed")
        XCTAssertFalse(tableSeesBar(of: pawn, in: state), "a Change gave the bar back")
        state.stopEncounter()
        XCTAssertFalse(tableSeesBar(of: pawn, in: state), "stopping the fight gave the bar back")
    }

    /// Mid-fight the numbers the table's bar is drawn from are the fight's, folded from the
    /// Log — and the Log's copy of the setting is whatever it was when the Pawn joined. The
    /// block the screens read has to carry both: the fight's numbers, the DM's setting.
    func testMidFightTheLiveBlockHasTheFightsNumbersAndTheWithheldBar() throws {
        let state = makeAppState()
        state.startSession()
        let pawn = mimic(in: state)
        state.startEncounter()

        withhold(pawn, in: state)
        state.editStatBlock(for: pawn.id) { $0.currentHP = 20 }

        let live = state.liveStatBlock(for: pawn.id)
        XCTAssertEqual(live.currentHP, 20)
        XCTAssertFalse(live.showsHealthBarToPlayers)
        state.stopEncounter()
    }

    // MARK: Add

    private let gnoll = Monster(name: "Gnoll Guerriero", armorClass: 15, hitPoints: 27,
                                initiativeBonus: 1)

    /// Add as `ControlView` performs it: what `AddPlacement` places, and whether it shows
    /// its bar, handed to `addPawnToMap`.
    @discardableResult
    private func add(_ kind: PawnKind, in state: AppState) throws -> Pawn {
        let pawn = try XCTUnwrap(AddPlacement.pawn(kind: kind, at: MapPoint(x: 200, y: 200),
                                                   existing: state.fog.pawns,
                                                   bestiary: state.bestiary))
        state.addPawnToMap(pawn, showingHealthBar: AddPlacement.showsHealthBarToPlayers(
            kind: kind, existing: state.fog.pawns, stats: state.statsDocument.blocks))
        return pawn
    }

    func testAddAfterAWithheldCreaturePlacesAWithheldOne() throws {
        let state = makeAppState()
        withhold(mimic(in: state), in: state)

        let second = try add(.creature, in: state)

        XCTAssertFalse(state.statBlock(for: second.id).showsHealthBarToPlayers)
    }

    /// The second gnoll is a gnoll, stamped at full hit points — and still withheld: the
    /// Monster's numbers are not the DM's choice about the table.
    func testAnAddedMonsterAfterAWithheldOneIsStampedAndStillWithheld() throws {
        let state = makeAppState()
        state.bestiary = Bestiary(monsters: [gnoll])
        let first = Pawn(at: MapPoint(x: 100, y: 100), label: "GG1", colorHex: "#C81E1E",
                         brightSquares: 6, kind: .creature, monsterName: gnoll.name)
        state.addPawnToMap(first)
        withhold(first, in: state)

        let second = try add(.creature, in: state)

        XCTAssertEqual(state.statBlock(for: second.id).currentHP, 27)
        XCTAssertFalse(state.statBlock(for: second.id).showsHealthBarToPlayers)
    }

    func testAddAfterAShownCreatureGivesThePawnNoStatBlockToSayIt() throws {
        let state = makeAppState()
        _ = mimic(in: state)

        let second = try add(.creature, in: state)

        XCTAssertNil(state.statsDocument.blocks[second.id])
    }

    /// Joining a running fight snapshots the block into the Log; the setting is there first,
    /// and joining writes nothing about it beyond the join itself.
    func testAWithheldCreatureAddedMidFightJoinsWithheld() throws {
        let state = makeAppState()
        state.startSession()
        withhold(mimic(in: state), in: state)
        state.startEncounter()

        let second = try add(.creature, in: state)

        XCTAssertTrue(state.encounter?.order.contains(second.id) ?? false)
        XCTAssertFalse(state.liveStatBlock(for: second.id).showsHealthBarToPlayers)
        state.stopEncounter()
        XCTAssertFalse(state.statBlock(for: second.id).showsHealthBarToPlayers)
    }

    // MARK: Stamping and Monsters leave it alone

    func testGivingAWithheldPawnAMonsterLeavesItWithheld() {
        let state = makeAppState()
        state.bestiary = Bestiary(monsters: [gnoll])
        let pawn = mimic(in: state)
        withhold(pawn, in: state)

        var draft = sheet(for: pawn, in: state)
        draft.pick(gnoll, among: state.fog.pawns)
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertEqual(state.statBlock(for: pawn.id).maxHP, 27, "precondition: it was stamped")
        XCTAssertFalse(state.statBlock(for: pawn.id).showsHealthBarToPlayers)
    }

    func testGivingAWithheldPawnAMonsterMidFightLeavesItWithheld() throws {
        let state = makeAppState()
        state.startSession()
        state.bestiary = Bestiary(monsters: [gnoll])
        let pawn = mimic(in: state)
        withhold(pawn, in: state)
        state.startEncounter()

        var draft = sheet(for: pawn, in: state)
        draft.pick(gnoll, among: state.fog.pawns)
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertEqual(state.liveStatBlock(for: pawn.id).maxHP, 27, "precondition: it was stamped")
        XCTAssertFalse(state.liveStatBlock(for: pawn.id).showsHealthBarToPlayers)
        state.stopEncounter()
    }

    func testAMonsterStampKeepsTheSettingItIsStampedOver() {
        let withheld = StatBlock(currentHP: 3, maxHP: 58, showsHealthBarToPlayers: false)

        XCTAssertFalse(MonsterStamp.statBlock(from: gnoll, over: withheld).showsHealthBarToPlayers)
    }

    /// A Character Stamps a new Pawn, and the table sees its bar: Stamping does not inherit
    /// from the last Player as Add does.
    func testAStampedCharactersBarIsShown() throws {
        let block = try XCTUnwrap(Stamp.statBlock(from: CharacterNote(name: "Durga")))

        XCTAssertTrue(block.showsHealthBarToPlayers)
    }
}
