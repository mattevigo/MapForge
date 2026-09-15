import XCTest
@testable import MapForge

/// Opening, switching and closing a Workspace — and, in particular, the app being fully alive
/// before the DM has picked one, which is the shape change this feature turns on.
@MainActor
final class WorkspaceAppStateTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspaceAppStateTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeAppState() -> AppState {
        AppState(preferences: DisplayPreferences(defaults: defaults))
    }

    /// A Workspace under the test root, adopted.
    private func makeWorkspace(_ name: String) throws -> Workspace {
        let url = root.appendingPathComponent(name)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return try WorkspaceStore().adopt(url)
    }

    private let thorin = PartyCharacter(name: "Thorin", colorHex: "#C81E1E",
                                        sightSquares: 6, isBig: false)

    // MARK: - Alive before a Workspace

    func testTheAppIsUsableBeforeAWorkspaceIsPicked() {
        // The Control Window exists behind the picker sheet, so nothing may assume a roster
        // was read at init — which is exactly what `AppState` used to do.
        let app = makeAppState()

        XCTAssertNil(app.workspace)
        XCTAssertTrue(app.partyBook.isEmpty)
        XCTAssertNil(app.activeParty)
    }

    func testRosterEditsWithNoWorkspaceWriteNothingAndDoNotCrash() {
        let app = makeAppState()

        app.addParty(named: "Eroi")
        app.addCharacter(thorin)
        app.deleteParty(id: UUID())

        XCTAssertNil(app.workspace)
    }

    // MARK: - Opening

    func testOpeningAWorkspaceLoadsItsRoster() throws {
        let workspace = try makeWorkspace("Eroi")
        try PartyStore(directory: workspace.supportDirectory)
            .save(PartyBook(parties: [Party(name: "Lost Boys", characters: [thorin])]))

        let app = makeAppState()
        app.open(workspace)

        XCTAssertEqual(app.workspace, workspace)
        XCTAssertEqual(app.partyBook.parties.map(\.name), ["Lost Boys"])
    }

    func testARosterEditLandsInTheWorkspaceNotApplicationSupport() throws {
        let workspace = try makeWorkspace("Eroi")
        let app = makeAppState()
        app.open(workspace)

        app.addParty(named: "Eroi")
        app.addCharacter(thorin)

        let onDisk = PartyStore(directory: workspace.supportDirectory).load()
        XCTAssertEqual(onDisk.parties.first?.characters.map(\.name), ["Thorin"])
        XCTAssertEqual(onDisk.parties.first?.name, "Eroi")
    }

    func testOpeningRecordsItInTheRecentsList() throws {
        let workspace = try makeWorkspace("Eroi")
        let app = makeAppState()

        app.open(workspace)

        XCTAssertEqual(DisplayPreferences(defaults: defaults).recentWorkspaces.first,
                       workspace.url)
    }

    func testTheActivePartyIsRememberedInTheWorkspace() throws {
        let workspace = try makeWorkspace("Eroi")
        let app = makeAppState()
        app.open(workspace)
        app.addParty(named: "Lost Boys")
        let chosen = try XCTUnwrap(app.activePartyID)

        let relaunched = makeAppState()
        relaunched.open(workspace)

        XCTAssertEqual(relaunched.activePartyID, chosen)
    }

    // MARK: - Switching

    func testOneWorkspacesRosterDoesNotLeakIntoAnother() throws {
        // The reason Parties moved out of Application Support at all.
        let first = try makeWorkspace("Eroi")
        let second = try makeWorkspace("Curse of Strahd")
        let app = makeAppState()
        app.open(first)
        app.addParty(named: "Lost Boys")

        app.open(second)

        XCTAssertTrue(app.partyBook.isEmpty)
        XCTAssertNil(app.activePartyID)
    }

    func testSwitchingBackFindsTheRosterAgain() throws {
        let first = try makeWorkspace("Eroi")
        let second = try makeWorkspace("Curse of Strahd")
        let app = makeAppState()
        app.open(first)
        app.addParty(named: "Lost Boys")

        app.open(second)
        app.open(first)

        XCTAssertEqual(app.partyBook.parties.map(\.name), ["Lost Boys"])
    }

    func testClosingLeavesTheAppInItsLaunchState() throws {
        let workspace = try makeWorkspace("Eroi")
        let app = makeAppState()
        app.open(workspace)
        app.addParty(named: "Lost Boys")

        app.closeWorkspace()

        XCTAssertNil(app.workspace)
        XCTAssertTrue(app.partyBook.isEmpty)
        XCTAssertNil(app.activePartyID)
    }

    // MARK: - The load-failure latch

    func testADamagedRosterInOneWorkspaceDoesNotSuppressWritesInAnother() throws {
        // Before Workspaces the latch was set once at init and never cleared, which was safe
        // when a process saw exactly one roster. A process now sees several, and a failure
        // carried in from a previous Workspace would silently discard every edit in a healthy
        // one — the DM types their party in for an evening and loses all of it.
        let damaged = try makeWorkspace("Damaged")
        try Data("{ not a roster".utf8).write(to: damaged.partiesURL)
        let healthy = try makeWorkspace("Healthy")

        let app = makeAppState()
        app.open(damaged)
        XCTAssertNotNil(app.partyLoadFailure, "the damaged roster must be reported")

        app.open(healthy)
        XCTAssertNil(app.partyLoadFailure, "and the latch must not follow us")

        app.addParty(named: "Lost Boys")
        app.addCharacter(thorin)

        let onDisk = PartyStore(directory: healthy.supportDirectory).load()
        XCTAssertEqual(onDisk.parties.first?.characters.map(\.name), ["Thorin"])
    }

    func testTheDamagedRosterCanBeSetAsideToWorkAgain() throws {
        // The way forward out of the latch. Refusing to write is right — the alternative is a
        // DM retyping their party over the file that could have been recovered — but it leaves
        // them unable to edit anything, and this is the DM's own choice to move on.
        let workspace = try makeWorkspace("Damaged")
        let bytes = Data("{ not a roster".utf8)
        try bytes.write(to: workspace.partiesURL)
        let app = makeAppState()
        app.open(workspace)

        app.setAsideDamagedRoster()

        XCTAssertNil(app.partyLoadFailure)
        XCTAssertEqual(try Data(contentsOf: workspace.partiesURL.appendingPathExtension("damaged")),
                       bytes, "the bytes are renamed, never deleted")

        app.addParty(named: "Retyped")
        app.addCharacter(thorin)
        XCTAssertEqual(PartyStore(directory: workspace.supportDirectory).load()
                        .parties.first?.characters.map(\.name), ["Thorin"])
    }

    func testSettingAsideWithNoFailureDoesNothing() throws {
        let workspace = try makeWorkspace("Healthy")
        let app = makeAppState()
        app.open(workspace)
        app.addParty(named: "Lost Boys")

        app.setAsideDamagedRoster()

        XCTAssertEqual(app.partyBook.parties.map(\.name), ["Lost Boys"])
    }

    func testADamagedRosterIsNeverOverwritten() throws {
        // `PartyStore`'s rule, which the Workspace must not weaken: a DM who opens the app,
        // sees no party and retypes it must not have the first save destroy the file that
        // could have been recovered.
        let workspace = try makeWorkspace("Damaged")
        let bytes = Data("{ not a roster".utf8)
        try bytes.write(to: workspace.partiesURL)

        let app = makeAppState()
        app.open(workspace)
        app.addParty(named: "Retyped")
        app.addCharacter(thorin)

        XCTAssertEqual(try Data(contentsOf: workspace.partiesURL), bytes)
    }
}
