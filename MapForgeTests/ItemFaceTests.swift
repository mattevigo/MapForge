import AppKit
import XCTest
@testable import MapForge

/// An Item's Face where it meets the rest of the app: OK in the Edit Pawn sheet giving a
/// Treasure its Item's Face, the cut kept once per Item — what `MonsterFaceTests` proves for a
/// Creature and its Monster.
@MainActor
final class ItemFaceTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ItemFaceTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// An open Workspace with a picture for the Borsa and none for the Corda, and a Map.
    private func makeAppState() async throws -> (AppState, Workspace) {
        let folder = root.appendingPathComponent("Eroi")
        try fileManager.createDirectory(at: folder.appendingPathComponent("Allegati"),
                                        withIntermediateDirectories: true)
        let workspace = try WorkspaceStore().adopt(folder)
        try picture("Allegati/Borsa.png", in: workspace)
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.open(workspace)
        await state.bestiaryLoad?.value
        state.treasury = Treasury(items: [borsa(picture: .found("Allegati/Borsa.png")),
                                          corda(picture: nil)])
        state.mapURL = folder.appendingPathComponent("dungeon.png")
        return (state, workspace)
    }

    private func picture(_ path: String, in workspace: Workspace) throws {
        try FaceFixture.writePNG(try FaceFixture.halves(width: 300, height: 100),
                                 to: workspace.url.appendingPathComponent(path))
    }

    private func borsa(picture: NotePicture?) -> Item {
        var item = Item(name: "Borsa")
        item.picture = picture
        return item
    }

    private func corda(picture: NotePicture?) -> Item {
        var item = Item(name: "Corda")
        item.picture = picture
        return item
    }

    private func treasure(_ label: String, face: PawnFace? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#D4A017",
             brightSquares: 0, kind: .treasure, face: face)
    }

    /// OK in the Edit Pawn sheet, having said the Treasure is `item`.
    private func make(_ id: Pawn.ID, _ item: Item, in state: AppState) throws {
        let pawn = try XCTUnwrap(state.fog.pawns.first { $0.id == id })
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(item, among: state.fog.pawns)
        state.updatePawn(id: id, with: draft)
    }

    private func face(of id: Pawn.ID, in state: AppState) -> PawnFace? {
        state.fog.pawns.first { $0.id == id }?.face
    }

    // MARK: Becoming the Item

    func testMakingATreasureThatItemGivesItTheItemsFace() async throws {
        let (state, _) = try await makeAppState()
        let pawn = treasure("1")
        state.fog.pawns = [pawn]

        try make(pawn.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)

        let face = try XCTUnwrap(face(of: pawn.id, in: state))
        XCTAssertEqual(face.origin, .item)
        XCTAssertNotNil(try XCTUnwrap(state.faceLibrary).image(for: face))
    }

    func testEveryTreasureMadeIntoItSharesOneCutKeptInTheWorkspace() async throws {
        let (state, workspace) = try await makeAppState()
        let first = treasure("1"), second = treasure("2")
        state.fog.pawns = [first, second]

        try make(first.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)
        try make(second.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)

        XCTAssertNotNil(face(of: first.id, in: state))
        XCTAssertEqual(face(of: second.id, in: state), face(of: first.id, in: state))
        let kept = try XCTUnwrap(NoteFacesStore(directory: workspace.supportDirectory).load()
            .items["Borsa"])
        XCTAssertEqual(kept.file, face(of: first.id, in: state)?.file)
    }

    // MARK: Becoming another Item

    func testBecomingAnItemWithAPictureSwapsTheFace() async throws {
        let (state, workspace) = try await makeAppState()
        try picture("Allegati/Corda.png", in: workspace)
        state.treasury = Treasury(items: [borsa(picture: .found("Allegati/Borsa.png")),
                                          corda(picture: .found("Allegati/Corda.png"))])
        let pawn = treasure("1")
        state.fog.pawns = [pawn]
        try make(pawn.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)
        let borsaFace = face(of: pawn.id, in: state)

        try make(pawn.id, corda(picture: .found("Allegati/Corda.png")), in: state)

        XCTAssertEqual(face(of: pawn.id, in: state)?.origin, .item)
        XCTAssertNotEqual(face(of: pawn.id, in: state), borsaFace)
    }

    func testBecomingAnItemWithoutAPictureShowsTheColour() async throws {
        let (state, _) = try await makeAppState()
        let pawn = treasure("1")
        state.fog.pawns = [pawn]
        try make(pawn.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)
        XCTAssertNotNil(face(of: pawn.id, in: state))

        try make(pawn.id, corda(picture: nil), in: state)

        XCTAssertNil(face(of: pawn.id, in: state))
    }

    func testAFaceCutByHandOrGivenByACharacterSurvivesBecomingAnyItem() async throws {
        let (state, _) = try await makeAppState()
        let hand = PawnFace(file: "mine.png", origin: .hand)
        let durga = PawnFace(file: "durga.png", origin: .character)
        let chest = treasure("1", face: hand), relic = treasure("2", face: durga)
        state.fog.pawns = [chest, relic]

        try make(chest.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)
        try make(relic.id, borsa(picture: .found("Allegati/Borsa.png")), in: state)
        XCTAssertEqual(face(of: chest.id, in: state), hand)
        XCTAssertEqual(face(of: relic.id, in: state), durga)
        try make(chest.id, corda(picture: nil), in: state)
        XCTAssertEqual(face(of: chest.id, in: state), hand)
    }

    /// What the DM does to the Face in the same sheet is what they meant.
    func testRemovingTheFaceInTheSheetThatPicksTheItemLeavesNone() async throws {
        let (state, _) = try await makeAppState()
        let pawn = treasure("1", face: PawnFace(file: "old.png", origin: .item))
        state.fog.pawns = [pawn]
        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(borsa(picture: .found("Allegati/Borsa.png")), among: state.fog.pawns)
        draft.face.remove()

        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertNil(face(of: pawn.id, in: state))
    }

    /// OK with the Item untouched leaves the Face alone: a Treasure that already was the
    /// Borsa is not handed its Face again behind the DM's back.
    func testOKWithTheItemUntouchedLeavesTheFaceAlone() async throws {
        let (state, _) = try await makeAppState()
        var pawn = treasure("Bo1")
        pawn.itemName = "Borsa"
        state.fog.pawns = [pawn]

        state.updatePawn(id: pawn.id, with: EditPawnDraft(pawn: pawn))

        XCTAssertNil(face(of: pawn.id, in: state))
    }

    // MARK: A picture that gives no Face

    func testAMissingOrSharedPictureGivesNoFaceAndIsReported() async throws {
        let (state, _) = try await makeAppState()
        state.treasury = Treasury(items: [borsa(picture: .missing(link: "Borsa.png")),
                                          corda(picture: .ambiguous(link: "Corda.png"))])
        let chest = treasure("1"), coil = treasure("2")
        state.fog.pawns = [chest, coil]

        try make(chest.id, borsa(picture: .missing(link: "Borsa.png")), in: state)
        try make(coil.id, corda(picture: .ambiguous(link: "Corda.png")), in: state)

        XCTAssertNil(face(of: chest.id, in: state))
        XCTAssertNil(face(of: coil.id, in: state))
        XCTAssertEqual(state.fog.pawns.map(\.itemName), ["Borsa", "Corda"])
        XCTAssertEqual(Set(state.treasury.pictureProblems.map(\.name)), ["Borsa", "Corda"])
    }
}
