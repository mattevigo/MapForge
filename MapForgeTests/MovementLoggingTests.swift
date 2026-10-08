import AppKit
import XCTest
@testable import MapForge

/// Movement on the Map reaching the Combat Log, and Pawns joining or leaving a fight that
/// is already running.
@MainActor
final class MovementLoggingTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MovementLoggingTests.\(UUID().uuidString)")
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

    /// A 1000-pixel-wide Map declared as 20 squares: 50 image pixels to the square, so the
    /// arithmetic in these tests is readable by eye.
    private func makeAppState() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.beginEvening(in: directory)
        state.mapURL = mapURL
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        return state
    }

    private func pawn(_ label: String, at x: CGFloat, kind: PawnKind = .player) -> Pawn {
        Pawn(at: MapPoint(x: x, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind)
    }

    // MARK: Movement

    func testADragRecordsOneMoveWithItsDistance() {
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startEncounter()

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        let moves = (state.encounter?.pendingChanges ?? []).compactMap { change -> CGFloat? in
            if case let .moved(_, _, _, distance) = change { return distance } else { return nil }
        }
        XCTAssertEqual(moves.count, 1)
        // 150 image pixels at 50 to the square.
        XCTAssertEqual(moves.first ?? 0, 3, accuracy: 0.001)
    }

    func testTheMoveCarriesWhereItStartedAndEnded() {
        // Before and after, as every Change does — the whole point being that a Log can be
        // replayed exactly.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startEncounter()

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        guard case let .moved(id, from, to, _)? = state.encounter?.pendingChanges.first else {
            return XCTFail("no moved Change recorded")
        }
        XCTAssertEqual(id, grog.id)
        XCTAssertEqual(from.x, 100)
        XCTAssertEqual(to.x, 250)
    }

    func testThreeDragsRecordThreeMoves() {
        // One Change per completed drag, not per frame of one: the DM's hand-wobble is not
        // domain data, and the decision is where they let go.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startEncounter()

        for (from, to) in [(100.0, 150.0), (150.0, 250.0), (250.0, 200.0)] {
            state.movePawn(id: grog.id, to: MapPoint(x: to, y: 100))
            state.commitPawnMove(id: grog.id, from: MapPoint(x: from, y: 100))
        }

        let distances = (state.encounter?.pendingChanges ?? []).compactMap { change -> CGFloat? in
            if case let .moved(_, _, _, d) = change { return d } else { return nil }
        }
        XCTAssertEqual(distances.count, 3)
        // 1 + 2 + 1 squares: what the DM needs to know is whether that beat the Pawn's speed.
        XCTAssertEqual(distances.reduce(0, +), 4, accuracy: 0.001)
    }

    func testADragWithNoEncounterRecordsNothing() {
        // Moving a Pawn outside a fight is what the app has always done, and stays unlogged.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        XCTAssertNil(state.encounter)
        XCTAssertEqual(state.fog.pawns.first?.at.x, 250, "the Pawn still moved")
    }

    func testADragWhileCorrectingMovesThePawnButRecordsNothing() {
        // ADR-0010: where a Pawn stands is the Map's truth and cannot retroactively be
        // somewhere else.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startEncounter()
        state.endTurn()
        state.stepBackForCorrection()

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        XCTAssertEqual(state.fog.pawns.first?.at.x, 250, "the Pawn must still move")
        XCTAssertTrue(state.encounter?.pendingChanges.isEmpty ?? false)
    }

    func testADragThatEndsWhereItStartedRecordsNothing() {
        // A click that turns into a one-pixel drag is not a move.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startEncounter()

        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        XCTAssertTrue(state.encounter?.pendingChanges.isEmpty ?? false)
    }

    func testAMoveLandsInTheActiveTurnWhoeverMoved() {
        // A Turn records what happened during it, not what happened to one Combatant.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        let goblin = pawn("Goblin", at: 400, kind: .creature)
        state.fog.pawns = [grog, goblin]
        state.startEncounter()
        let active = state.encounter?.activeCombatantID
        let other = active == grog.id ? goblin : grog

        state.movePawn(id: other.id, to: MapPoint(x: 500, y: 100))
        state.commitPawnMove(id: other.id, from: other.at)
        state.endTurn()

        let reader = CombatLogReader()
        guard let url = reader.newestLogURL(forMapAt: mapURL),
              let lines = try? reader.read(at: url) else { return XCTFail("no Log") }
        guard case let .turn(_, combatantID, changes, _)? = lines.last(where: {
            if case .turn = $0 { return true } else { return false }
        }) else { return XCTFail("no turn line") }

        XCTAssertEqual(combatantID, active, "the line belongs to whoever's Turn it was")
        XCTAssertEqual(changes.first?.combatantID, other.id, "the Change names who moved")
    }

    // MARK: Joining and leaving mid-fight

    func testStampingMidFightJoinsTheOrder() {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startEncounter()
        let before = state.encounter?.order.count ?? 0

        let wolf = pawn("Wolf", at: 300, kind: .creature)
        state.addPawnToMap(wolf)

        XCTAssertEqual(state.encounter?.order.count, before + 1)
        XCTAssertTrue(state.encounter?.order.contains(wolf.id) ?? false)
    }

    func testATreasureStampedMidFightDoesNotJoin() {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startEncounter()
        let before = state.encounter?.order.count ?? 0

        state.addPawnToMap(pawn("Chest", at: 300, kind: .treasure))

        XCTAssertEqual(state.encounter?.order.count, before)
    }

    func testStampingACharacterCarriesItsCombatNumbers() {
        // ADR-0007's copy rule reaching the Stat Block, the numbers coming from the
        // Character's note (ADR-0024).
        let state = makeAppState()
        state.characterNotes = CharacterNotes(notes: [
            CharacterNote(name: "Thorin Scudodiquercia", armorClass: 18, maxHP: 44, initiativeBonus: 3),
        ])
        let thorin = PartyCharacter(name: "Thorin", noteName: "Thorin Scudodiquercia")
        let frame = CGRect(x: 0, y: 0, width: 500, height: 400)

        XCTAssertTrue(state.stamp(thorin, at: CGPoint(x: 100, y: 80), frame: frame))

        let stamped = try? XCTUnwrap(state.fog.pawns.first)
        XCTAssertEqual(state.statBlock(for: stamped!.id).armorClass, 18)
        XCTAssertEqual(state.statBlock(for: stamped!.id).currentHP, 44, "stamped at full health")
        XCTAssertEqual(state.statBlock(for: stamped!.id).initiativeBonus, 3)
    }

    func testACharacterStampedMidFightJoinsWithItsNumbers() {
        let state = makeAppState()
        state.fog.pawns = [pawn("Goblin", at: 400, kind: .creature)]
        state.startEncounter()

        state.characterNotes = CharacterNotes(notes: [
            CharacterNote(name: "Thorin Scudodiquercia", armorClass: 18, maxHP: 44),
        ])
        let thorin = PartyCharacter(name: "Thorin", noteName: "Thorin Scudodiquercia")
        XCTAssertTrue(state.stamp(thorin, at: CGPoint(x: 100, y: 80),
                                  frame: CGRect(x: 0, y: 0, width: 500, height: 400)))

        let stamped = try? XCTUnwrap(state.fog.pawns.last)
        XCTAssertTrue(state.encounter?.order.contains(stamped!.id) ?? false, "did not join")
        XCTAssertEqual(state.encounter?.blocks[stamped!.id]?.maxHP, 44,
                       "joined with no numbers")
    }

    func testAPawnAddedWithNoFightJustLands() {
        let state = makeAppState()
        state.addPawnToMap(pawn("Grog", at: 100))
        XCTAssertEqual(state.fog.pawns.count, 1)
        XCTAssertNil(state.encounter)
    }

    func testDeletingAPawnMidFightBenchesIt() {
        // The Log already names it, and a monster that died in Round 2 is part of what
        // happened.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        let goblin = pawn("Goblin", at: 400, kind: .creature)
        state.fog.pawns = [grog, goblin]
        state.startEncounter()

        state.removePawnFromMap(goblin.id)

        XCTAssertFalse(state.fog.pawns.contains { $0.id == goblin.id }, "gone from the Map")
        XCTAssertFalse(state.encounter?.order.contains(goblin.id) ?? true,
                       "a Benched Pawn is out of the Order")
        XCTAssertTrue(state.encounter?.benched.contains(goblin.id) ?? false,
                      "and on the bench, where the tracker still shows it")
    }

    func testAPawnThatWasNeverInTheFightCanBePutIntoIt() {
        // The bench holds everything on the Map that is not taking Turns, including a Pawn
        // the Order has never seen — so the way in has to work for one the Log cannot name.
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startEncounter()

        let chest = pawn("Chest", at: 700, kind: .treasure)
        state.fog.pawns.append(chest)
        let wolf = pawn("Wolf", at: 500, kind: .creature)
        state.fog.pawns.append(wolf)

        state.unbenchCombatant(wolf.id)

        XCTAssertTrue(state.encounter?.order.contains(wolf.id) ?? false)
        XCTAssertNotNil(state.encounter?.initiative(of: wolf.id), "it needs a rolled Initiative")
        XCTAssertFalse(state.encounter?.order.contains(chest.id) ?? true,
                       "a Treasure has nothing to do on its turn")
    }

    func testABenchedPawnComesBackWithTheHitPointsItHad() {
        let state = makeAppState()
        let goblin = pawn("Goblin", at: 400, kind: .creature)
        state.fog.pawns = [pawn("Grog", at: 100), goblin]
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: goblin.id)
        state.startEncounter()
        state.editStatBlock(for: goblin.id) { $0.currentHP = 2 }

        state.benchCombatant(goblin.id)
        XCTAssertTrue(state.encounter?.benched.contains(goblin.id) ?? false)

        state.unbenchCombatant(goblin.id)
        XCTAssertTrue(state.encounter?.order.contains(goblin.id) ?? false)
        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.currentHP, 2,
                       "the bench is not a rest")
    }

    func testApplyingFogEditsLeavesTheFightAlone() {
        // Everything in this feature is live, beside Solo Sight and Measurement: none of
        // it enters `FogEdits`, and the fog Undo button must not unwind a Combatant's hit
        // points. Exercised through the same path the editing mode uses.
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.setStatBlock(StatBlock(currentHP: 26, maxHP: 26), for: grog.id)
        state.startEncounter()
        state.recordChange(.hpChanged(combatantID: grog.id, from: 26, to: 19))

        // A wall traced and applied, which is what the mode commits.
        var edits = FogEdits(document: state.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 100, y: 0))])
        state.fog = edits.document

        XCTAssertEqual(state.encounter?.blocks[grog.id]?.currentHP, 19,
                       "the fight lost its hit points to a fog edit")
        XCTAssertEqual(state.encounter?.order.count, 1)
    }

    func testARemovedCombatantsStatBlockSurvivesUntilTheFightEnds() {
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        let goblin = pawn("Goblin", at: 400, kind: .creature)
        state.fog.pawns = [grog, goblin]
        state.setStatBlock(StatBlock(currentHP: 7, maxHP: 7), for: goblin.id)
        state.startEncounter()

        state.removePawnFromMap(goblin.id)

        XCTAssertEqual(state.encounter?.blocks[goblin.id]?.maxHP, 7,
                       "the record outlives the token")
    }
}
