import AppKit
import XCTest
@testable import MapForge

/// Dragging a member of the **Selection** carries every member rigidly
/// (`CONTEXT.md`, **Selection**), stops as a whole at the image edge, and records one move
/// per Pawn exactly as a single drag would.
///
/// Driven through what `PawnLayer`'s drag hands `AppState`: a `SelectionMove` taken as the
/// drag begins, the translation so far on each update, and the commit on release.
@MainActor
final class SelectionMoveTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SelectionMoveTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("corridor.png")
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Moving

    func testATranslationMovesEveryMemberByExactlyThatTranslation() throws {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        let lantern = light(at: MapPoint(x: 120, y: 90))
        state.fog.pawns = [rogue, fighter]
        state.fog.lights = [lantern]
        pick(rogue, fighter, lantern, in: state)

        let move = try grab(rogue, in: state)
        state.moveSelection(move, by: CGVector(dx: 200, dy: 50))

        XCTAssertEqual(position(of: rogue, in: state), MapPoint(x: 300, y: 150))
        XCTAssertEqual(position(of: fighter, in: state), MapPoint(x: 350, y: 170))
        XCTAssertEqual(position(of: lantern, in: state), MapPoint(x: 320, y: 140))
    }

    /// A Light Marker that is a member carries the party as a Pawn does: the rogue's lantern
    /// can lead.
    func testGrabbingAPickedLightMovesTheWholeSelection() throws {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let lantern = light(at: MapPoint(x: 120, y: 90))
        state.fog.pawns = [rogue]
        state.fog.lights = [lantern]
        pick(rogue, in: state)
        state.toggleSelection(light: lantern.id)

        let move = try XCTUnwrap(SelectionMove(grabbingLight: lantern.id,
                                               selection: state.selection,
                                               pawns: state.fog.pawns,
                                               lights: state.fog.lights))
        state.moveSelection(move, by: CGVector(dx: 10, dy: 20))

        XCTAssertEqual(position(of: rogue, in: state), MapPoint(x: 110, y: 120))
        XCTAssertEqual(position(of: lantern, in: state), MapPoint(x: 130, y: 110))
    }

    /// A Pawn or a Light that is not picked moves alone, exactly as before there was a
    /// Selection, and the party it was dragged past stays where it stood, still picked.
    func testDraggingANonMemberMovesOnlyItAndLeavesTheSelectionWhereItWas() {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        let goblin = pawn("Goblin", at: MapPoint(x: 600, y: 400))
        let lantern = light(at: MapPoint(x: 120, y: 90))
        let brazier = light(at: MapPoint(x: 700, y: 500))
        state.fog.pawns = [rogue, fighter, goblin]
        state.fog.lights = [lantern, brazier]
        pick(rogue, fighter, lantern, in: state)
        let picked = state.selection

        XCTAssertNil(SelectionMove(grabbingPawn: goblin.id, selection: state.selection,
                                   pawns: state.fog.pawns, lights: state.fog.lights),
                     "a drag on the goblin is the goblin's alone")
        XCTAssertNil(SelectionMove(grabbingLight: brazier.id, selection: state.selection,
                                   pawns: state.fog.pawns, lights: state.fog.lights),
                     "and a drag on the brazier the brazier's")
        // What `PawnLayer` does instead: the single-thing drag, as it always has.
        state.movePawn(id: goblin.id, to: MapPoint(x: 650, y: 400))
        state.commitPawnMove(id: goblin.id, from: MapPoint(x: 600, y: 400))
        state.moveLight(id: brazier.id, to: MapPoint(x: 720, y: 500))
        state.commitLightMove()

        XCTAssertEqual(position(of: goblin, in: state), MapPoint(x: 650, y: 400))
        XCTAssertEqual(position(of: brazier, in: state), MapPoint(x: 720, y: 500))
        XCTAssertEqual(position(of: rogue, in: state), MapPoint(x: 100, y: 100))
        XCTAssertEqual(position(of: fighter, in: state), MapPoint(x: 150, y: 120))
        XCTAssertEqual(position(of: lantern, in: state), MapPoint(x: 120, y: 90))
        XCTAssertEqual(state.selection, picked)
    }

    // MARK: The image edge

    /// The whole Selection stops when its first member reaches the edge — here the lantern,
    /// so a Light holds the party back as surely as a Pawn would. Nobody is clamped on their
    /// own: the formation arrives at the edge intact rather than squashed against it.
    func testATranslationPastTheEdgeStopsTheWholeSelectionWhereItsFirstMemberReachesIt()
        throws {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        let lantern = light(at: MapPoint(x: 940, y: 90))
        state.fog.pawns = [rogue, fighter]
        state.fog.lights = [lantern]
        pick(rogue, fighter, lantern, in: state)

        let move = try grab(rogue, in: state)
        // 100 to the right would carry the lantern to 1040, 40 past a 1000-pixel image;
        // the downward 30 is clear of the bottom edge and is kept whole.
        state.moveSelection(move, by: CGVector(dx: 100, dy: 30))

        XCTAssertEqual(position(of: lantern, in: state), MapPoint(x: 1000, y: 120),
                       "the lantern lands on the edge")
        XCTAssertEqual(position(of: rogue, in: state), MapPoint(x: 160, y: 130),
                       "the others keep their offsets from it")
        XCTAssertEqual(position(of: fighter, in: state), MapPoint(x: 210, y: 150))
    }

    /// Up and to the left, and stopped by a Pawn: the same rule on the other two edges.
    func testATranslationPastTheTopLeftStopsAtTheMemberNearestIt() throws {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 40))
        let fighter = pawn("Fighter", at: MapPoint(x: 30, y: 120))
        state.fog.pawns = [rogue, fighter]
        pick(rogue, fighter, in: state)

        let move = try grab(rogue, in: state)
        state.moveSelection(move, by: CGVector(dx: -50, dy: -60))

        XCTAssertEqual(position(of: fighter, in: state), MapPoint(x: 0, y: 80))
        XCTAssertEqual(position(of: rogue, in: state), MapPoint(x: 70, y: 0))
    }

    /// Each update is the translation from where the drag began, so pushing against the
    /// edge and coming back leaves no trace of the stop in the formation.
    func testADragHeldAgainstTheEdgeAndBroughtBackLandsWhereTheCursorSays() throws {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 900, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 800, y: 100))
        state.fog.pawns = [rogue, fighter]
        pick(rogue, fighter, in: state)

        let move = try grab(rogue, in: state)
        state.moveSelection(move, by: CGVector(dx: 300, dy: 0))
        state.moveSelection(move, by: CGVector(dx: 50, dy: 0))

        XCTAssertEqual(position(of: rogue, in: state), MapPoint(x: 950, y: 100))
        XCTAssertEqual(position(of: fighter, in: state), MapPoint(x: 850, y: 100))
    }

    // MARK: The record

    /// A Selection is a way of acting, not a thing in the record: each Pawn's line is the
    /// one a drag of that Pawn alone writes, with its own from, to and distance, and the
    /// lantern carried along writes nothing, as a Light's move never does.
    func testCommittingDuringASessionWritesOneLinePerPawnAndNoneForTheLight() throws {
        let state = makeAppState()
        state.beginEvening(in: directory)
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        let lantern = light(at: MapPoint(x: 120, y: 90))
        state.fog.pawns = [rogue, fighter]
        state.fog.lights = [lantern]
        pick(rogue, fighter, lantern, in: state)
        let linesBefore = try sessionLines(state).count

        let move = try grab(fighter, in: state)
        state.moveSelection(move, by: CGVector(dx: 150, dy: 0))
        state.commitSelectionMove(move)

        let lines = try sessionLines(state)
        XCTAssertEqual(lines.count, linesBefore + 2, "two Pawns, two lines; the Light none")
        let moves = lines.compactMap { line -> (Pawn.ID, String, MapPoint, MapPoint, CGFloat)? in
            guard case let .pawnMoved(id, label, _, from, to, distance, _) = line else {
                return nil
            }
            return (id, label, from, to, distance)
        }
        XCTAssertEqual(moves.map(\.0), [rogue.id, fighter.id], "in the Map's own order")
        XCTAssertEqual(moves.map(\.1), ["Rogue", "Fighter"])
        XCTAssertEqual(moves.map(\.2), [MapPoint(x: 100, y: 100), MapPoint(x: 150, y: 120)])
        XCTAssertEqual(moves.map(\.3), [MapPoint(x: 250, y: 100), MapPoint(x: 300, y: 120)])
        // 150 image pixels at 50 to the square.
        XCTAssertEqual(moves.map(\.4), [3, 3])
    }

    /// During an Encounter the Combat Log takes each Pawn's move and the Session Log takes
    /// none of them — ADR-0014, exactly as a single drag behaves.
    func testCommittingDuringAnEncounterRecordsOneChangePerPawnAndNoSessionLine() throws {
        let state = makeAppState()
        state.beginEvening(in: directory)
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        let lantern = light(at: MapPoint(x: 120, y: 90))
        state.fog.pawns = [rogue, fighter]
        state.fog.lights = [lantern]
        state.startEncounter()
        pick(rogue, fighter, lantern, in: state)
        let linesBefore = try sessionLines(state)

        let move = try grab(rogue, in: state)
        state.moveSelection(move, by: CGVector(dx: 0, dy: 100))
        state.commitSelectionMove(move)

        let moves = (state.encounter?.pendingChanges ?? []).compactMap {
            change -> (Pawn.ID, MapPoint, MapPoint, CGFloat)? in
            guard case let .moved(id, from, to, distance) = change else { return nil }
            return (id, from, to, distance)
        }
        XCTAssertEqual(moves.map(\.0), [rogue.id, fighter.id])
        XCTAssertEqual(moves.map(\.1), [MapPoint(x: 100, y: 100), MapPoint(x: 150, y: 120)])
        XCTAssertEqual(moves.map(\.2), [MapPoint(x: 100, y: 200), MapPoint(x: 150, y: 220)])
        XCTAssertEqual(moves.map(\.3), [2, 2])
        XCTAssertEqual(try sessionLines(state), linesBefore,
                       "exactly one recorder is live at any instant — ADR-0014")
    }

    /// A drag that ends where it began is a click, not a move — for the Selection as for
    /// one Pawn.
    func testCommittingADragThatEndedWhereItBeganRecordsNothing() throws {
        let state = makeAppState()
        state.beginEvening(in: directory)
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        state.fog.pawns = [rogue, fighter]
        pick(rogue, fighter, in: state)
        let linesBefore = try sessionLines(state)

        let move = try grab(rogue, in: state)
        state.moveSelection(move, by: CGVector(dx: 80, dy: 0))
        state.moveSelection(move, by: CGVector(dx: 0, dy: 0))
        state.commitSelectionMove(move)

        XCTAssertEqual(try sessionLines(state), linesBefore)
    }

    /// The Selection survives the move, so the DM can walk the party down a corridor in
    /// several drags.
    func testTheSelectionSurvivesTheMove() throws {
        let state = makeAppState()
        let rogue = pawn("Rogue", at: MapPoint(x: 100, y: 100))
        let fighter = pawn("Fighter", at: MapPoint(x: 150, y: 120))
        let lantern = light(at: MapPoint(x: 120, y: 90))
        state.fog.pawns = [rogue, fighter]
        state.fog.lights = [lantern]
        pick(rogue, fighter, lantern, in: state)
        let picked = state.selection

        let move = try grab(rogue, in: state)
        state.moveSelection(move, by: CGVector(dx: 50, dy: 50))
        state.commitSelectionMove(move)

        XCTAssertEqual(state.selection, picked)
    }

    // MARK: Fixtures

    /// A 1000×800 Map declared as 20 squares: 50 image pixels to the square, so the
    /// distances in these tests are readable by eye.
    private func makeAppState() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.mapURL = mapURL
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        return state
    }

    private func pawn(_ label: String, at point: MapPoint) -> Pawn {
        Pawn(at: point, label: label, colorHex: "#C81E1E", brightSquares: 6)
    }

    private func light(at point: MapPoint) -> Light {
        Light(at: point, brightSquares: 4, dimSquares: 8, name: "lantern")
    }

    private func pick(_ pawns: Pawn..., in state: AppState) {
        pawns.forEach { state.toggleSelection(pawn: $0.id) }
    }

    private func pick(_ first: Pawn, _ second: Pawn, _ light: Light, in state: AppState) {
        pick(first, second, in: state)
        state.toggleSelection(light: light.id)
    }

    /// What `PawnLayer` takes as a drag on a member begins.
    private func grab(_ pawn: Pawn, in state: AppState) throws -> SelectionMove {
        try XCTUnwrap(SelectionMove(grabbingPawn: pawn.id, selection: state.selection,
                                    pawns: state.fog.pawns, lights: state.fog.lights),
                      "\(pawn.label) is a member, so grabbing it moves the Selection")
    }

    /// The Session Log as it stands on disk.
    private func sessionLines(_ state: AppState) throws -> [SessionLine] {
        guard let url = state.sessionLogURL else { return [] }
        return try SessionLogReader().read(at: url)
    }

    private func position(of pawn: Pawn, in state: AppState) -> MapPoint? {
        state.fog.pawns.first { $0.id == pawn.id }?.at
    }

    private func position(of light: Light, in state: AppState) -> MapPoint? {
        state.fog.lights.first { $0.id == light.id }?.at
    }
}
