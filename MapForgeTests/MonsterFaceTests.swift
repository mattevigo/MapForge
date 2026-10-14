import AppKit
import XCTest
@testable import MapForge

/// A Monster's Face where it meets the rest of the app: OK in the Edit Pawn sheet giving a
/// Creature its Monster's Face, Add taking it fresh, and the cut kept once per Monster.
@MainActor
final class MonsterFaceTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MonsterFaceTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// An open Workspace with a picture for the Gnoll and none for the Ogre, and a Map.
    private func makeAppState() async throws -> (AppState, Workspace) {
        let folder = root.appendingPathComponent("Eroi")
        try fileManager.createDirectory(at: folder.appendingPathComponent("Allegati"),
                                        withIntermediateDirectories: true)
        let workspace = try WorkspaceStore().adopt(folder)
        try picture("Allegati/Gnoll.png", in: workspace)
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.open(workspace)
        await state.bestiaryLoad?.value
        state.bestiary = Bestiary(monsters: [gnoll(picture: "Allegati/Gnoll.png"), ogre(picture: nil)])
        state.mapURL = folder.appendingPathComponent("dungeon.png")
        return (state, workspace)
    }

    private func picture(_ path: String, in workspace: Workspace) throws {
        try FaceFixture.writePNG(try FaceFixture.halves(width: 300, height: 100),
                                 to: workspace.url.appendingPathComponent(path))
    }

    private func gnoll(picture: String?) -> Monster {
        var monster = Monster(name: "Gnoll Guerriero", armorClass: 15, hitPoints: 27)
        monster.picture = picture.map { .found($0) }
        return monster
    }

    private func ogre(picture: String?) -> Monster {
        var monster = Monster(name: "Ogre", armorClass: 11, hitPoints: 59, isBig: true)
        monster.picture = picture.map { .found($0) }
        return monster
    }

    private func creature(_ label: String, face: PawnFace? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, face: face)
    }

    /// OK in the Edit Pawn sheet, having said the Pawn is `monster`.
    private func make(_ id: Pawn.ID, _ monster: Monster, in state: AppState) throws {
        let pawn = try XCTUnwrap(state.fog.pawns.first { $0.id == id })
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(monster, among: state.fog.pawns)
        state.updatePawn(id: id, with: draft)
    }

    private func face(of id: Pawn.ID, in state: AppState) -> PawnFace? {
        state.fog.pawns.first { $0.id == id }?.face
    }

    // MARK: Becoming the Monster

    func testMakingACreatureThatMonsterGivesItTheMonstersFace() async throws {
        let (state, _) = try await makeAppState()
        let pawn = creature("1")
        state.fog.pawns = [pawn]

        try make(pawn.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)

        let face = try XCTUnwrap(face(of: pawn.id, in: state))
        XCTAssertEqual(face.origin, .monster)
        XCTAssertNotNil(try XCTUnwrap(state.faceLibrary).image(for: face))
    }

    func testASecondCreatureMadeIntoItSharesTheCut() async throws {
        let (state, _) = try await makeAppState()
        let first = creature("1"), second = creature("2")
        state.fog.pawns = [first, second]

        try make(first.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)
        try make(second.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)

        XCTAssertNotNil(face(of: first.id, in: state))
        XCTAssertEqual(face(of: second.id, in: state), face(of: first.id, in: state))
    }

    func testTheMonstersCutIsKeptInTheWorkspace() async throws {
        let (state, workspace) = try await makeAppState()
        let pawn = creature("1")
        state.fog.pawns = [pawn]

        try make(pawn.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)

        let kept = try XCTUnwrap(NoteFacesStore(directory: workspace.supportDirectory).load()
            .monsters["Gnoll Guerriero"])
        XCTAssertEqual(kept.file, face(of: pawn.id, in: state)?.file)
    }

    // MARK: Becoming another Monster

    func testBecomingAMonsterWithAPictureSwapsTheFace() async throws {
        let (state, workspace) = try await makeAppState()
        try picture("Allegati/Ogre.png", in: workspace)
        state.bestiary = Bestiary(monsters: [gnoll(picture: "Allegati/Gnoll.png"),
                                             ogre(picture: "Allegati/Ogre.png")])
        let pawn = creature("1")
        state.fog.pawns = [pawn]
        try make(pawn.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)
        let gnollFace = face(of: pawn.id, in: state)

        try make(pawn.id, ogre(picture: "Allegati/Ogre.png"), in: state)

        XCTAssertNotNil(face(of: pawn.id, in: state))
        XCTAssertNotEqual(face(of: pawn.id, in: state), gnollFace)
    }

    func testBecomingAMonsterWithoutAPictureShowsTheColour() async throws {
        let (state, _) = try await makeAppState()
        let pawn = creature("1")
        state.fog.pawns = [pawn]
        try make(pawn.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)
        XCTAssertNotNil(face(of: pawn.id, in: state))

        try make(pawn.id, ogre(picture: nil), in: state)

        XCTAssertNil(face(of: pawn.id, in: state))
    }

    func testAFaceCutByHandSurvivesBecomingAnyMonster() async throws {
        let (state, _) = try await makeAppState()
        let hand = PawnFace(file: "mine.png", origin: .hand)
        let pawn = creature("1", face: hand)
        state.fog.pawns = [pawn]

        try make(pawn.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)
        XCTAssertEqual(face(of: pawn.id, in: state), hand)
        try make(pawn.id, ogre(picture: nil), in: state)
        XCTAssertEqual(face(of: pawn.id, in: state), hand)
    }

    /// What the DM does to the Face in the same sheet is what they meant: a Remove is not
    /// undone by the Monster picked beside it.
    func testRemovingTheFaceInTheSheetThatPicksTheMonsterLeavesNone() async throws {
        let (state, _) = try await makeAppState()
        let pawn = creature("1", face: PawnFace(file: "old.png", origin: .monster))
        state.fog.pawns = [pawn]
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(gnoll(picture: "Allegati/Gnoll.png"), among: state.fog.pawns)
        draft.face.remove()

        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertNil(face(of: pawn.id, in: state))
    }

    func testAFaceCutInTheSheetThatPicksTheMonsterWins() async throws {
        let (state, _) = try await makeAppState()
        let pawn = creature("1")
        state.fog.pawns = [pawn]
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(gnoll(picture: "Allegati/Gnoll.png"), among: state.fog.pawns)
        draft.face.choosePicture(try FaceFixture.halves(width: 100, height: 100))

        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertEqual(face(of: pawn.id, in: state)?.origin, .hand)
    }

    // MARK: Add

    func testAddAfterAMonsterCreatureGivesTheNewPawnTheMonstersFace() async throws {
        let (state, _) = try await makeAppState()
        let first = creature("1")
        state.fog.pawns = [first]
        try make(first.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)

        let added = try XCTUnwrap(AddPlacement.pawn(kind: .creature, at: MapPoint(x: 50, y: 50),
                                                    existing: state.fog.pawns,
                                                    bestiary: state.bestiary))
        state.addPawnToMap(added)

        XCTAssertEqual(state.fog.pawns.last?.face?.origin, .monster)
        XCTAssertEqual(state.fog.pawns.last?.face, face(of: first.id, in: state))
    }

    // MARK: A copy

    func testANewPictureInTheNoteLeavesPawnsAlreadyOnTheMapAlone() async throws {
        let (state, workspace) = try await makeAppState()
        let first = creature("1"), second = creature("2")
        state.fog.pawns = [first, second]
        try make(first.id, gnoll(picture: "Allegati/Gnoll.png"), in: state)
        let before = face(of: first.id, in: state)

        try picture("Allegati/Gnoll-nuovo.png", in: workspace)
        state.bestiary = Bestiary(monsters: [gnoll(picture: "Allegati/Gnoll-nuovo.png")])
        try make(second.id, gnoll(picture: "Allegati/Gnoll-nuovo.png"), in: state)

        XCTAssertEqual(face(of: first.id, in: state), before)
        XCTAssertNotNil(face(of: second.id, in: state))
        XCTAssertNotEqual(face(of: second.id, in: state), before)
    }
}
