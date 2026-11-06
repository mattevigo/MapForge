import XCTest
@testable import MapForge

/// The Treasury where it meets the rest of the app: read when the Workspace opens, beside the
/// Bestiary, and OK in the Edit Pawn sheet making a Treasure remember its Item.
@MainActor
final class TreasuryAppStateTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TreasuryAppStateTests.\(UUID().uuidString)")
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
        return state
    }

    private func treasure(_ label: String, itemName: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: label, colorHex: "#D4A017",
             brightSquares: 0, kind: .treasure, itemName: itemName)
    }

    // MARK: OK

    func testOKMakesTheTreasureRememberTheItemAndRelabelsIt() {
        let state = makeAppState()
        let pawn = treasure("2")
        state.fog.pawns = [treasure("Bo1", itemName: "Borsa"), pawn]

        var draft = EditPawnDraft(pawn: pawn)
        draft.pick(Item(name: "Borsa"), among: state.fog.pawns)
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertEqual(state.fog.pawns[1].itemName, "Borsa")
        XCTAssertEqual(state.fog.pawns[1].label, "Bo2")
        XCTAssertEqual(state.statBlock(for: pawn.id), StatBlock(), "an Item has no numbers")
    }

    func testATreasureMadeACreatureForgetsItsItem() {
        let state = makeAppState()
        let pawn = treasure("Bo1", itemName: "Borsa")
        state.fog.pawns = [pawn]

        var draft = EditPawnDraft(pawn: pawn)
        draft.kind = .creature
        state.updatePawn(id: pawn.id, with: draft)

        XCTAssertNil(state.fog.pawns[0].itemName)
    }

    // MARK: The Workspace

    func testOpeningAWorkspaceReadsItsItemsAndClosingForgetsThem() async throws {
        let root = directory.appendingPathComponent("Vault")
        let notes = root.appendingPathComponent("Riferimento/Equipaggiamento")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mapforge"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("---\nitem: true\n---\n# Borsa\n".utf8)
            .write(to: notes.appendingPathComponent("Borsa.md"))

        let state = makeAppState()
        state.open(Workspace(url: root))
        XCTAssertEqual(state.treasury, .reading)
        await state.bestiaryLoad?.value

        XCTAssertEqual(state.treasury.items.map(\.name), ["Borsa"])

        state.closeWorkspace()
        XCTAssertEqual(state.treasury, .closed)
    }
}
