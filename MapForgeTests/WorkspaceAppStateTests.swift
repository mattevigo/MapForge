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
                                        sightSquares: 6)

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

// MARK: - Reaching the Workspace (ADR-0025)

/// Security-scoped access, counted per folder. A count above one is a grant that outlived its
/// use; below zero, a stop with no start.
private final class AccessLedger {
    private(set) var held: [String: Int] = [:]

    var scope: SecurityScope {
        SecurityScope(
            start: { [self] url in held[Workspace(url: url).url.path, default: 0] += 1; return true },
            stop: { [self] url in held[Workspace(url: url).url.path, default: 0] -= 1 })
    }

    /// The folders with access held, and how many times over.
    var outstanding: [String: Int] { held.filter { $0.value != 0 } }
}

extension WorkspaceAppStateTests {
    private func makeAppState(_ ledger: AccessLedger) -> AppState {
        AppState(preferences: DisplayPreferences(defaults: defaults), securityScope: ledger.scope)
    }

    func testTheOpenWorkspaceHoldsItsFolder() throws {
        let workspace = try makeWorkspace("Eroi")
        let ledger = AccessLedger()
        let app = makeAppState(ledger)

        app.open(workspace)

        XCTAssertEqual(ledger.outstanding, [workspace.url.path: 1])
    }

    func testSwitchingBackAndForthHoldsOnlyTheOpenOne() throws {
        let first = try makeWorkspace("Eroi")
        let second = try makeWorkspace("Curse of Strahd")
        let ledger = AccessLedger()
        let app = makeAppState(ledger)

        app.open(first)
        app.open(second)
        app.open(first)

        XCTAssertEqual(ledger.outstanding, [first.url.path: 1])
    }

    func testClosingGivesTheAccessBack() throws {
        let workspace = try makeWorkspace("Eroi")
        let ledger = AccessLedger()
        let app = makeAppState(ledger)
        app.open(workspace)

        app.closeWorkspace()

        XCTAssertTrue(ledger.outstanding.isEmpty)
    }

    func testCheckingARecentHoldsNothingAfterwards() throws {
        let workspace = try makeWorkspace("Eroi")
        makeAppState(AccessLedger()).open(workspace)
        let ledger = AccessLedger()
        let app = makeAppState(ledger)

        XCTAssertTrue(app.isRecentWorkspaceAvailable(workspace.url))
        XCTAssertTrue(ledger.outstanding.isEmpty)
    }

    func testARecentWorkspaceOpensThroughItsBookmarkAfterARelaunch() throws {
        let workspace = try makeWorkspace("Eroi")
        makeAppState().open(workspace)
        let ledger = AccessLedger()
        let relaunched = makeAppState(ledger)

        let result = relaunched.openRecentWorkspace(workspace.url)

        XCTAssertEqual(try result.get(), workspace)
        XCTAssertEqual(relaunched.workspace, workspace)
        XCTAssertEqual(ledger.outstanding, [workspace.url.path: 1])
    }

    func testARecentWhoseFolderMovedOpensWhereItWent() throws {
        let workspace = try makeWorkspace("Eroi")
        makeAppState().open(workspace)
        let moved = root.appendingPathComponent("Eroi delle Terre di Confine")
        try FileManager.default.moveItem(at: workspace.url, to: moved)
        let relaunched = makeAppState()

        XCTAssertTrue(relaunched.isRecentWorkspaceAvailable(workspace.url))
        _ = relaunched.openRecentWorkspace(workspace.url)

        XCTAssertEqual(relaunched.workspace, Workspace(url: moved))
        XCTAssertEqual(relaunched.recentWorkspaces.map(\.path), [Workspace(url: moved).url.path])
    }

    func testARecentWhoseFolderIsGoneIsUnavailableAndDoesNotOpen() throws {
        let workspace = try makeWorkspace("Eroi")
        makeAppState().open(workspace)
        try FileManager.default.removeItem(at: workspace.url)
        let relaunched = makeAppState()

        XCTAssertFalse(relaunched.isRecentWorkspaceAvailable(workspace.url))
        XCTAssertThrowsError(try relaunched.openRecentWorkspace(workspace.url).get())
        XCTAssertNil(relaunched.workspace)
        XCTAssertEqual(relaunched.recentWorkspaces.map(\.path), [workspace.url.path])
    }
}

// MARK: - A Map lives inside the Workspace (ADR-0026)

extension WorkspaceAppStateTests {
    /// A small PNG at `url`, in a folder made for it.
    private func writeMap(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    func testAMapInsideTheWorkspaceOpens() throws {
        let workspace = try makeWorkspace("Eroi")
        let map = workspace.url.appendingPathComponent("Dungeons/crypt.png")
        try writeMap(at: map)
        let app = makeAppState()
        app.open(workspace)

        app.openMap(at: map)

        XCTAssertEqual(app.mapURL, map)
        XCTAssertNil(app.mapOutsideWorkspace)
    }

    func testAMapOutsideTheWorkspaceIsRefusedAndTheDMIsTold() throws {
        let workspace = try makeWorkspace("Eroi")
        let map = root.appendingPathComponent("Elsewhere/crypt.png")
        try writeMap(at: map)
        let app = makeAppState()
        app.open(workspace)

        app.openMap(at: map)

        XCTAssertNil(app.mapURL)
        XCTAssertEqual(app.mapOutsideWorkspace, workspace)
    }

    func testARefusedMapLeavesTheOpenOneOpen() throws {
        let workspace = try makeWorkspace("Eroi")
        let inside = workspace.url.appendingPathComponent("crypt.png")
        let outside = root.appendingPathComponent("Elsewhere/tower.png")
        try writeMap(at: inside)
        try writeMap(at: outside)
        let app = makeAppState()
        app.open(workspace)
        app.openMap(at: inside)

        app.openMap(at: outside)

        XCTAssertEqual(app.mapURL, inside)
    }
}
