import AppKit
import XCTest
@testable import MapForge

/// Giving a Pawn a Face in the Edit Pawn sheet: what the draft holds until OK, and what OK
/// keeps in the Workspace. Cancel keeps nothing, because nothing is kept before OK.
@MainActor
final class FaceEditTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FaceEditTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makePawn(face: PawnFace? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: "1", colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, face: face)
    }

    /// A picture somewhere outside the Workspace, as the DM would pick one from Downloads.
    private func makePicture(width: Int = 400, height: Int = 300) throws -> URL {
        let url = root.appendingPathComponent("Downloads/Goblin.png")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try FaceFixture.writePNG(try FaceFixture.halves(width: width, height: height), to: url)
        return url
    }

    private func makeAppStateInWorkspace() throws -> (AppState, Workspace) {
        let folder = root.appendingPathComponent("Eroi")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let workspace = try WorkspaceStore().adopt(folder)
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.open(workspace)
        return (state, workspace)
    }

    // MARK: The draft

    func testChoosingAPictureStartsTheCutAsTheCentredSquare() throws {
        var draft = EditPawnDraft(pawn: makePawn())

        draft.choosePicture(try FaceFixture.halves(width: 400, height: 300))

        XCTAssertEqual(draft.newCut?.cut, CGRect(x: 50, y: 0, width: 300, height: 300))
        XCTAssertTrue(draft.hasFace)
    }

    func testRemovingTheFaceForgetsBothTheKeptAndThePendingCut() throws {
        var draft = EditPawnDraft(pawn: makePawn(face: PawnFace(file: "a.png", origin: .hand)))
        draft.choosePicture(try FaceFixture.halves(width: 100, height: 100))

        draft.removeFace()

        XCTAssertNil(draft.newCut)
        XCTAssertFalse(draft.hasFace)
        XCTAssertNil(draft.applied(to: makePawn(face: PawnFace(file: "a.png", origin: .hand))).face)
    }

    func testAFaceTheSheetDidNotTouchComesThrough() {
        let face = PawnFace(file: "a.png", origin: .hand)
        let pawn = makePawn(face: face)

        XCTAssertEqual(EditPawnDraft(pawn: pawn).applied(to: pawn).face, face)
    }

    // MARK: OK

    func testOKKeepsTheCutInTheWorkspaceAndDrawsThePawnAsIt() throws {
        let (state, workspace) = try makeAppStateInWorkspace()
        let pawn = makePawn()
        state.fog.pawns = [pawn]
        var draft = EditPawnDraft(pawn: pawn)
        draft.choosePicture(try XCTUnwrap(FacePicture.load(try makePicture())))
        draft.resizeCut(toSide: 100)
        draft.setCut(CGRect(x: 1000, y: 0, width: 100, height: 100))

        state.updatePawn(id: pawn.id, with: draft)

        let face = try XCTUnwrap(state.fog.pawns[0].face)
        XCTAssertEqual(face.origin, .hand)
        let kept = workspace.facesDirectory.appendingPathComponent(face.file)
        XCTAssertTrue(fileManager.fileExists(atPath: kept.path))
        // Shrunk and moved to the right edge, the cut is the blue half alone.
        XCTAssertEqual(FaceFixture.colour(of: try XCTUnwrap(FacePicture.load(kept)), x: 10, y: 10),
                       .blue)
        XCTAssertEqual(state.fog.pawns[0].colorHex, "#C81E1E")
    }

    func testThePictureMayGoBeforeOKAndAfter() throws {
        // OK cuts the picture the DM was shown, not the file it came from: deleted while the
        // sheet was open, it is still kept; and once kept, it needs the file no more.
        let (state, _) = try makeAppStateInWorkspace()
        let pawn = makePawn()
        state.fog.pawns = [pawn]
        let picture = try makePicture()
        var draft = EditPawnDraft(pawn: pawn)
        draft.choosePicture(try XCTUnwrap(FacePicture.load(picture)))

        try fileManager.removeItem(at: picture)
        state.updatePawn(id: pawn.id, with: draft)

        let face = try XCTUnwrap(state.fog.pawns[0].face)
        XCTAssertNotNil(try XCTUnwrap(state.faceLibrary).image(for: face))
    }

    func testRemovingTheFaceShowsTheColourAgain() throws {
        let (state, _) = try makeAppStateInWorkspace()
        let pawn = makePawn(face: PawnFace(file: "a.png", origin: .hand))
        state.fog.pawns = [pawn]
        var draft = EditPawnDraft(pawn: pawn)
        draft.removeFace()

        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertNil(state.fog.pawns[0].face)
        XCTAssertEqual(state.fog.pawns[0].colorHex, "#C81E1E")
    }

    func testWithNoWorkspaceACutChangesNothing() throws {
        // Nowhere to keep it. The sheet does not offer a picture then; this is the backstop.
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        let pawn = makePawn()
        state.fog.pawns = [pawn]
        var draft = EditPawnDraft(pawn: pawn)
        draft.choosePicture(try FaceFixture.halves(width: 400, height: 300))

        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertNil(state.fog.pawns[0].face)
    }

    func testClosingTheWorkspaceForgetsItsFaces() throws {
        let (state, _) = try makeAppStateInWorkspace()
        XCTAssertNotNil(state.faceLibrary)

        state.closeWorkspace()

        XCTAssertNil(state.faceLibrary)
    }
}
