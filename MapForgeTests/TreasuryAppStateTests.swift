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

    // MARK: The Workspace

    func testOpeningAWorkspaceReadsItsItemsAndClosingForgetsThem() async throws {
        let root = directory.appendingPathComponent("Vault")
        let notes = root.appendingPathComponent("Riferimento/Equipaggiamento")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mapforge"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("---\nitem: true\n---\n# Borsa\n".utf8)
            .write(to: notes.appendingPathComponent("Bag.md"))

        let state = makeAppState()
        state.open(Workspace(url: root))
        XCTAssertEqual(state.treasury, .reading)
        await state.bestiaryLoad?.value

        XCTAssertEqual(state.treasury.items.map(\.name), ["Borsa"])

        state.closeWorkspace()
        XCTAssertEqual(state.treasury, .closed)
    }
}
