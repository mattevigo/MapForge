import XCTest
@testable import MapForge

/// The one-time move out of Application Support.
///
/// Every test here points the migration at a temp file. It has no default source and cannot
/// acquire one by omission — see `testTheRealRosterIsNeverTheDefaultSource`, which exists
/// because the first version of this code had a default and deleted the developer's own party.
final class WorkspaceMigrationTests: XCTestCase {
    private var root: URL!
    private var legacyURL: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    private let thorin = PartyCharacter(name: "Thorin", colorHex: "#C81E1E",
                                        sightSquares: 6, isBig: false)

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspaceMigrationTests.\(UUID().uuidString)")
        let legacyDirectory = root.appendingPathComponent("LegacyApplicationSupport")
        try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        legacyURL = legacyDirectory.appendingPathComponent("parties.json")
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeWorkspace(_ name: String = "Eroi") throws -> Workspace {
        let url = root.appendingPathComponent(name)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return try WorkspaceStore().adopt(url)
    }

    private func migration() -> WorkspaceMigration {
        WorkspaceMigration(preferences: DisplayPreferences(defaults: defaults),
                           legacyURL: legacyURL,
                           defaults: defaults)
    }

    @discardableResult
    private func writeLegacyRoster(
        _ book: PartyBook = PartyBook(parties: [Party(name: "Lost Boys", characters: [])])
    ) throws -> PartyBook {
        try PartyStore(directory: legacyURL.deletingLastPathComponent()).save(book)
        return book
    }

    private func run(into workspace: Workspace,
                     using migration: WorkspaceMigration? = nil) -> WorkspaceMigration.Outcome? {
        var outcome: WorkspaceMigration.Outcome?
        (migration ?? self.migration()).runIfNeeded(into: workspace) { outcome = $0 }
        return outcome
    }

    // MARK: - The safety property that was learned the hard way

    func testTheRealRosterIsNeverTheDefaultSource() {
        // `WorkspaceMigration` has no default `legacyURL`, so no caller can start deleting the
        // DM's real roster by forgetting to say where it is. This test is a statement about the
        // API's shape; if it stops compiling because a default was added, that default is the
        // bug.
        let explicit = migration()

        XCTAssertEqual(explicit.legacyURL, legacyURL)
        XCTAssertNotEqual(explicit.legacyURL, WorkspaceMigration.legacyPartiesURL)
    }

    // MARK: - The happy path

    func testTheRosterMovesIntoTheWorkspace() throws {
        let book = try writeLegacyRoster(
            PartyBook(parties: [Party(name: "Lost Boys", characters: [thorin])])
        )
        let workspace = try makeWorkspace()

        let outcome = run(into: workspace)

        XCTAssertEqual(outcome, .migrated(partyNames: ["Lost Boys"], workspaceName: "Eroi"))
        XCTAssertEqual(PartyStore(directory: workspace.supportDirectory).load(), book)
    }

    func testTheOldRosterIsRetiredButRecoverable() throws {
        // "Removed" as far as the app is concerned — nothing reads it, it never comes back —
        // and still on disk for a DM whose roster went missing to a bug we have not found.
        try writeLegacyRoster()
        let workspace = try makeWorkspace()

        run(into: workspace)

        XCTAssertFalse(fileManager.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(fileManager.fileExists(
            atPath: legacyURL.appendingPathExtension("migrated").path))
    }

    func testThePreferencesComeWithIt() throws {
        try writeLegacyRoster()
        let partyID = UUID()
        defaults.set(partyID.uuidString, forKey: "activePartyID")
        defaults.set("uuid-tv", forKey: "playerDisplayUUID")
        defaults.set("LG TV", forKey: "playerDisplayName")
        let workspace = try makeWorkspace()

        run(into: workspace)

        let settings = WorkspacePreferencesStore(directory: workspace.supportDirectory).load()
        XCTAssertEqual(settings.activePartyID, partyID)
        XCTAssertEqual(settings.playerDisplay, DisplayIdentity(uuid: "uuid-tv", name: "LG TV"))
    }

    func testTheStaleKeysAreCleared() throws {
        // A `playerDisplayUUID` left in `UserDefaults` is what a future reader wires back up
        // by mistake.
        try writeLegacyRoster()
        defaults.set(UUID().uuidString, forKey: "activePartyID")
        defaults.set("uuid-tv", forKey: "playerDisplayUUID")
        defaults.set("LG TV", forKey: "playerDisplayName")

        run(into: try makeWorkspace())

        XCTAssertNil(defaults.string(forKey: "activePartyID"))
        XCTAssertNil(defaults.string(forKey: "playerDisplayUUID"))
        XCTAssertNil(defaults.string(forKey: "playerDisplayName"))
    }

    func testTheRecentsListSurvives() throws {
        // It is machine state by necessity — the bootstrap pointer — so the migration must not
        // take it with the rest of `UserDefaults`.
        try writeLegacyRoster()
        let preferences = DisplayPreferences(defaults: defaults)
        preferences.noteWorkspaceOpened(Workspace(url: URL(fileURLWithPath: "/somewhere")))

        run(into: try makeWorkspace())

        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), ["/somewhere"])
    }

    func testACharacterWithNoMaxHPSurvivesByteForByte() throws {
        // `maxHP` is `Int?` and omitted from the JSON when nil. A byte copy cannot lose it, or
        // any other field a later version adds and this one does not know about.
        var drusilla = thorin
        drusilla.name = "Drusilla"
        drusilla.maxHP = nil
        try writeLegacyRoster(PartyBook(parties: [Party(name: "Lost Boys",
                                                        characters: [drusilla])]))
        let before = try Data(contentsOf: legacyURL)
        let workspace = try makeWorkspace()

        run(into: workspace)

        XCTAssertEqual(try Data(contentsOf: workspace.partiesURL), before)
    }

    // MARK: - Nothing to do

    func testNoLegacyRosterMeansNothingHappens() throws {
        XCTAssertNil(run(into: try makeWorkspace()))
    }

    func testAnEmptyLegacyRosterMeansNothingHappens() throws {
        try Data(#"{"parties":[],"version":1}"#.utf8).write(to: legacyURL)

        XCTAssertNil(run(into: try makeWorkspace()))
    }

    func testAWorkspaceThatAlreadyHasARosterIsNeverOverwritten() throws {
        try writeLegacyRoster()
        let workspace = try makeWorkspace()
        let existing = PartyBook(parties: [Party(name: "Already Here", characters: [])])
        try PartyStore(directory: workspace.supportDirectory).save(existing)

        XCTAssertNil(run(into: workspace))
        XCTAssertEqual(PartyStore(directory: workspace.supportDirectory).load(), existing)
        XCTAssertTrue(fileManager.fileExists(atPath: legacyURL.path),
                      "and the source is untouched")
    }

    func testItRunsOnlyOnce() throws {
        // The absence of the source is the whole guard: no flag anywhere to fall out of step.
        try writeLegacyRoster()
        run(into: try makeWorkspace("First"))

        XCTAssertNil(run(into: try makeWorkspace("Second")))
    }

    // MARK: - Failure is never destructive

    func testAnUnreadableRosterIsLeftAloneAndReported() throws {
        let damaged = Data("{ not a roster".utf8)
        try damaged.write(to: legacyURL)
        let workspace = try makeWorkspace()

        guard case .failed = run(into: workspace) else {
            return XCTFail("an unreadable roster is a reported failure")
        }
        XCTAssertEqual(try Data(contentsOf: legacyURL), damaged)
        XCTAssertFalse(fileManager.fileExists(atPath: workspace.partiesURL.path))
    }

    func testAFailedMigrationIsRetriedOnTheNextWorkspace() throws {
        let damaged = Data("{ not a roster".utf8)
        try damaged.write(to: legacyURL)
        guard case .failed = run(into: try makeWorkspace("First")) else {
            return XCTFail("expected a failure")
        }

        // The DM repairs the file between sessions.
        try writeLegacyRoster()

        guard case .migrated = run(into: try makeWorkspace("Second")) else {
            return XCTFail("a repaired roster must be picked up on the next open")
        }
    }

    func testAnUnwritableDestinationLeavesTheSourceAlone() throws {
        try writeLegacyRoster()
        // A Workspace whose `.mapforge` is a *file*, so creating the directory fails.
        let url = root.appendingPathComponent("Hostile")
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let workspace = Workspace(url: url)
        try Data("in the way".utf8).write(to: workspace.supportDirectory)

        guard case .failed = run(into: workspace) else {
            return XCTFail("an unwritable destination is a reported failure")
        }
        XCTAssertTrue(fileManager.fileExists(atPath: legacyURL.path))
    }

    func testTheCopyIsVerifiedBeforeAnythingIsDeleted() throws {
        // The check that makes deletion safe. `PartyStore.save` deletes the file when the book
        // is empty, so a migration that round-tripped through load-and-save could destroy the
        // source while reporting success; a verified byte copy cannot.
        try writeLegacyRoster()
        let workspace = try makeWorkspace()

        let dryRun = WorkspaceMigration(preferences: DisplayPreferences(defaults: defaults),
                                        legacyURL: legacyURL,
                                        defaults: defaults,
                                        retiresLegacyData: false)
        run(into: workspace, using: dryRun)

        XCTAssertEqual(try Data(contentsOf: workspace.partiesURL),
                       try Data(contentsOf: legacyURL))
    }
}
