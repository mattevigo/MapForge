import XCTest
@testable import MapForge

/// The settings that travel with a Workspace: which Party the panel offers, and which screen
/// this game presents on. These moved out of `UserDefaults` in ADR-0012.
final class WorkspacePreferencesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspacePreferencesTests.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func store() -> WorkspacePreferencesStore {
        WorkspacePreferencesStore(directory: directory)
    }

    func testNothingRememberedInitially() {
        XCTAssertEqual(store().load(), WorkspaceSettings())
    }

    func testTheActivePartySurvivesARelaunch() {
        // The DM runs one game per sitting: the app must reopen on the Party they were last
        // using, not make them pick it again.
        let id = UUID()
        store().save(WorkspaceSettings(activePartyID: id))

        XCTAssertEqual(store().load().activePartyID, id)
    }

    func testThePlayerDisplaySurvivesARelaunch() {
        let identity = DisplayIdentity(uuid: "uuid-tv", name: "LG TV")
        store().save(WorkspaceSettings(playerDisplay: identity))

        XCTAssertEqual(store().load().playerDisplay, identity)
    }

    func testAChoiceCanBeCleared() {
        store().save(WorkspaceSettings(activePartyID: UUID(),
                                       playerDisplay: DisplayIdentity(uuid: "tv", name: "TV")))
        store().save(WorkspaceSettings())

        XCTAssertEqual(store().load(), WorkspaceSettings())
    }

    func testTwoWorkspacesRememberSeparately() {
        // The whole point of moving these out of `UserDefaults`.
        let other = directory.appendingPathComponent("other")
        let mine = UUID()
        store().save(WorkspaceSettings(activePartyID: mine))
        WorkspacePreferencesStore(directory: other).save(WorkspaceSettings(activePartyID: UUID()))

        XCTAssertEqual(store().load().activePartyID, mine)
    }

    func testADamagedFileDegradesToDefaultsRatherThanLatching() {
        // Deliberately unlike `PartyStore`, which refuses every later write once it fails to
        // read. These are choices a DM remakes with one click; losing which screen was picked
        // costs a click, and losing the roster costs an evening.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("{ not json".utf8).write(to: store().fileURL)

        XCTAssertEqual(store().load(), WorkspaceSettings())

        let id = UUID()
        store().save(WorkspaceSettings(activePartyID: id))
        XCTAssertEqual(store().load().activePartyID, id, "a later choice must still stick")
    }

    func testTheFileIsReadableAndStableOnDisk() throws {
        store().save(WorkspaceSettings(activePartyID: UUID()))

        let text = try String(contentsOf: store().fileURL, encoding: .utf8)

        XCTAssertTrue(text.contains("\n"), "pretty-printed, as PartyStore writes")
    }
}
