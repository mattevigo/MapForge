import AppKit
import XCTest
@testable import MapForge

/// A Character's Face: cut in the Character's editor, kept in the Workspace by Save alone, and
/// copied by the Stamp onto every Pawn it makes — a copy, so the Pawns already Stamped keep the
/// Face they were given whatever happens to the Character's afterwards (ADR-0007, ADR-0028).
@MainActor
final class CharacterFaceTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterFaceTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// An open Workspace holding one Party, and a 40 × 30 Map drawn into a 400 × 300 frame.
    private func makeAppStateWithAMap() throws -> (AppState, Workspace, CGRect) {
        let folder = root.appendingPathComponent("Eroi")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let workspace = try WorkspaceStore().adopt(folder)
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.open(workspace)
        state.addParty(named: "Eroi")

        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let mapURL = folder.appendingPathComponent("dungeon.png")
        try FaceFixture.writePNG(try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil,
                                                             hints: nil)), to: mapURL)
        state.loadMap(image: image, at: mapURL)
        return (state, workspace, CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    /// A Face draft holding a cut of a red-and-blue picture, not yet kept.
    private func cut() throws -> FaceDraft {
        var face = FaceDraft(nil)
        face.choosePicture(try FaceFixture.halves(width: 200, height: 100))
        return face
    }

    private func character(in state: AppState) throws -> PartyCharacter {
        try XCTUnwrap(state.activeParty?.characters.first)
    }

    // MARK: The editor's Save

    func testSavingANewCharacterKeepsItsCutInTheWorkspace() throws {
        let (state, workspace, _) = try makeAppStateWithAMap()

        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())

        let face = try XCTUnwrap(try character(in: state).face)
        XCTAssertTrue(fileManager.fileExists(
            atPath: workspace.facesDirectory.appendingPathComponent(face.file).path))
    }

    func testTheCharactersFaceReachesTheRoster() throws {
        let (state, workspace, _) = try makeAppStateWithAMap()

        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())

        let reloaded = PartyStore(directory: workspace.supportDirectory).load()
        XCTAssertEqual(reloaded.parties.first?.characters.first?.face,
                       try character(in: state).face)
    }

    func testRemovingTheCharactersFaceShowsItsColourAgain() throws {
        let (state, _, _) = try makeAppStateWithAMap()
        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())
        let durga = try character(in: state)
        var face = FaceDraft(durga.face)
        face.remove()

        state.updateCharacter(durga, face: face)

        XCTAssertNil(try character(in: state).face)
    }

    func testAnEditThatLeavesTheFaceAloneKeepsIt() throws {
        let (state, _, _) = try makeAppStateWithAMap()
        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())
        var durga = try character(in: state)
        let kept = durga.face
        durga.colorHex = "#1E90C8"

        state.updateCharacter(durga, face: FaceDraft(durga.face))

        XCTAssertEqual(try character(in: state).face, kept)
    }

    // MARK: The Stamp

    func testStampingTheCharacterPutsAPawnOnTheMapWearingItsFace() throws {
        let (state, _, frame) = try makeAppStateWithAMap()
        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())
        let durga = try character(in: state)

        XCTAssertTrue(state.stamp(durga, at: CGPoint(x: 100, y: 80), frame: frame))

        let pawn = try XCTUnwrap(state.fog.pawns.first)
        XCTAssertEqual(pawn.face?.file, durga.face?.file)
        XCTAssertEqual(pawn.face?.origin, .character)
        XCTAssertNotNil(try XCTUnwrap(state.faceLibrary).image(for: try XCTUnwrap(pawn.face)))
    }

    func testReCuttingTheCharactersFaceLeavesItsStampedPawnsAlone() throws {
        let (state, _, frame) = try makeAppStateWithAMap()
        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())
        XCTAssertTrue(state.stamp(try character(in: state), at: CGPoint(x: 100, y: 80),
                                  frame: frame))
        let stamped = state.fog.pawns[0].face

        state.updateCharacter(try character(in: state), face: try cut())

        XCTAssertNotEqual(try character(in: state).face?.file, stamped?.file)
        XCTAssertEqual(state.fog.pawns[0].face, stamped)
        XCTAssertNotNil(try XCTUnwrap(state.faceLibrary).image(for: try XCTUnwrap(stamped)))
    }

    func testRemovingTheCharactersFaceLeavesItsStampedPawnsAlone() throws {
        let (state, _, frame) = try makeAppStateWithAMap()
        state.addCharacter(PartyCharacter(name: "Durga"), face: try cut())
        XCTAssertTrue(state.stamp(try character(in: state), at: CGPoint(x: 100, y: 80),
                                  frame: frame))
        let stamped = state.fog.pawns[0].face
        var removed = FaceDraft(try character(in: state).face)
        removed.remove()

        state.updateCharacter(try character(in: state), face: removed)

        XCTAssertNil(try character(in: state).face)
        XCTAssertEqual(state.fog.pawns[0].face, stamped)
        XCTAssertNotNil(try XCTUnwrap(state.faceLibrary).image(for: try XCTUnwrap(stamped)))
    }

    /// Nowhere to keep a cut: the Character keeps the Face it had rather than naming a file
    /// never written.
    func testWithNoWorkspaceACutLeavesTheCharactersFaceAsItWas() throws {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: root))
        state.addParty(named: "Eroi")
        let face = PawnFace(file: "durga.png", origin: .hand)
        var draft = FaceDraft(face)
        draft.choosePicture(try FaceFixture.halves(width: 200, height: 100))

        state.addCharacter(PartyCharacter(name: "Durga", face: face), face: draft)

        XCTAssertEqual(try character(in: state).face, face)
    }
}
