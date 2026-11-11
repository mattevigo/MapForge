import XCTest
@testable import MapForge

/// What remains on the machine after ADR-0012: the recents list, and nothing else until
/// Calibration. The Player Display and active Party this file used to cover moved into
/// `WorkspaceSettings` and are covered in `WorkspacePreferencesTests`.
final class DisplayPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func preferences() -> DisplayPreferences {
        DisplayPreferences(defaults: defaults)
    }

    private func workspace(_ path: String) -> Workspace {
        Workspace(url: URL(fileURLWithPath: path))
    }

    func testNothingRememberedInitially() {
        XCTAssertTrue(preferences().recentWorkspaces.isEmpty)
    }

    func testTheLastWorkspaceSurvivesANewInstance() {
        // The point of the type: a relaunch reopens the game the DM was running, with no
        // interaction. The same promise the remembered Player Display used to make.
        preferences().noteWorkspaceOpened(workspace("/Users/dm/DM Workspace"))

        XCTAssertEqual(preferences().recentWorkspaces.first?.path, "/Users/dm/DM Workspace")
    }

    func testTheMostRecentComesFirst() {
        let preferences = preferences()
        preferences.noteWorkspaceOpened(workspace("/a"))
        preferences.noteWorkspaceOpened(workspace("/b"))

        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), ["/b", "/a"])
    }

    func testReopeningAWorkspaceMovesItUpRatherThanDuplicating() {
        let preferences = preferences()
        preferences.noteWorkspaceOpened(workspace("/a"))
        preferences.noteWorkspaceOpened(workspace("/b"))
        preferences.noteWorkspaceOpened(workspace("/a"))

        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), ["/a", "/b"])
    }

    func testTwoSpellingsOfOneFolderAreOneEntry() {
        // A picker that lists the same campaign twice under two spellings is telling the DM
        // something untrue about their own disk.
        let preferences = preferences()
        preferences.noteWorkspaceOpened(workspace("/Users/dm/Maps"))
        preferences.noteWorkspaceOpened(workspace("/Users/dm/Maps/"))

        XCTAssertEqual(preferences.recentWorkspaces.count, 1)
    }

    func testTheListIsCapped() {
        let preferences = preferences()
        for index in 0..<(DisplayPreferences.recentsLimit + 5) {
            preferences.noteWorkspaceOpened(workspace("/workspace-\(index)"))
        }

        XCTAssertEqual(preferences.recentWorkspaces.count, DisplayPreferences.recentsLimit)
        XCTAssertEqual(preferences.recentWorkspaces.first?.path,
                       "/workspace-\(DisplayPreferences.recentsLimit + 4)")
    }

    func testNothingIsForgottenAutomatically() {
        // A Workspace on an unplugged drive must stay listed: the DM should see an entry
        // marked unavailable, not a campaign that has silently disappeared.
        let preferences = preferences()
        preferences.noteWorkspaceOpened(workspace("/Volumes/Backup/Campaigns"))
        preferences.noteWorkspaceOpened(workspace("/Users/dm/Maps"))

        XCTAssertEqual(preferences.recentWorkspaces.count, 2)
        XCTAssertTrue(preferences.recentWorkspaces.contains {
            $0.path == "/Volumes/Backup/Campaigns"
        })
    }

    func testForgettingIsTheDMsGesture() {
        let preferences = preferences()
        preferences.noteWorkspaceOpened(workspace("/a"))
        preferences.noteWorkspaceOpened(workspace("/b"))

        preferences.forgetWorkspace(URL(fileURLWithPath: "/a"))

        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), ["/b"])
    }

    func testAGarbledListDegradesToEmptyRatherThanCrashing() {
        // Hand-edited or corrupted defaults must not stop the app launching. The recents list
        // is a convenience; losing it costs one folder pick.
        defaults.set([1, 2, 3], forKey: "recentWorkspaces")

        XCTAssertTrue(preferences().recentWorkspaces.isEmpty)
    }
}

/// The bookmark beside each recent Workspace, which is how one is reached on a later launch
/// under the App Sandbox (ADR-0025).
///
/// Real folders and real bookmarks where the system can be had unsandboxed — the round trip,
/// a moved folder, a deleted one. A stand-in only where it cannot: the sandbox refusing a
/// bookmark for a path, and telling one bookmark from the next.
final class RecentWorkspaceBookmarkTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RecentWorkspaceBookmarkTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func preferences(bookmarks: WorkspaceBookmarks = .securityScoped)
        -> DisplayPreferences {
        DisplayPreferences(defaults: defaults, bookmarks: bookmarks)
    }

    private func folder(_ name: String) throws -> Workspace {
        let url = root.appendingPathComponent(name)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return Workspace(url: url)
    }

    private var storedBookmarks: [String: Data] {
        defaults.dictionary(forKey: "recentWorkspaceBookmarks") as? [String: Data] ?? [:]
    }

    /// Bookmarks that are the path they point at, numbered so each one made is new.
    private final class Counter { var made = 0 }

    private func countingBookmarks(_ counter: Counter) -> WorkspaceBookmarks {
        WorkspaceBookmarks(
            make: { url in
                counter.made += 1
                return Data("\(counter.made)|\(url.path)".utf8)
            },
            resolve: { data in
                let path = String(decoding: data, as: UTF8.self).split(separator: "|")[1]
                return URL(fileURLWithPath: String(path))
            })
    }

    /// The sandbox, as far as an old entry is concerned: no grant, so no bookmark.
    private struct Refused: Error {}
    private let sandboxed = WorkspaceBookmarks(make: { _ in throw Refused() },
                                               resolve: { _ in throw Refused() })

    func testAnOpenedWorkspaceIsReachedThroughItsBookmarkAfterARelaunch() throws {
        let workspace = try folder("Eroi")
        preferences().noteWorkspaceOpened(workspace)

        let relaunched = preferences()

        XCTAssertNotNil(storedBookmarks[workspace.url.path])
        let located = try XCTUnwrap(relaunched.locateWorkspace(workspace.url))
        XCTAssertEqual(Workspace(url: located), workspace)
    }

    func testAMovedWorkspaceIsFoundWhereItWent() throws {
        // A DM who renames the campaign folder in Finder has not lost the campaign.
        let workspace = try folder("Eroi")
        preferences().noteWorkspaceOpened(workspace)
        let moved = root.appendingPathComponent("Eroi delle Terre di Confine")
        try fileManager.moveItem(at: workspace.url, to: moved)

        let located = try XCTUnwrap(preferences().locateWorkspace(workspace.url))

        XCTAssertEqual(Workspace(url: located), Workspace(url: moved))
    }

    func testAGoneWorkspaceCannotBeReachedButStaysListed() throws {
        let workspace = try folder("Eroi")
        preferences().noteWorkspaceOpened(workspace)
        try fileManager.removeItem(at: workspace.url)

        let preferences = preferences()

        XCTAssertNil(preferences.locateWorkspace(workspace.url))
        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), [workspace.url.path])
    }

    func testAnEntryFromBeforeBookmarksIsUpgradedQuietly() throws {
        // Unsandboxed, a DM updating the app must find every recent exactly where it was.
        let workspace = try folder("Eroi")
        defaults.set([workspace.url.path], forKey: "recentWorkspaces")

        let located = preferences().locateWorkspace(workspace.url)

        XCTAssertEqual(located.map(Workspace.init(url:)), workspace)
        XCTAssertNotNil(storedBookmarks[workspace.url.path])
    }

    func testAnEntryFromBeforeBookmarksThatCannotBeBookmarkedIsUnavailable() throws {
        // Under the sandbox: no grant for the old path. Unavailable, still listed, and one
        // folder pick from working again.
        let workspace = try folder("Eroi")
        defaults.set([workspace.url.path], forKey: "recentWorkspaces")

        let preferences = preferences(bookmarks: sandboxed)

        XCTAssertNil(preferences.locateWorkspace(workspace.url))
        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), [workspace.url.path])
        XCTAssertTrue(storedBookmarks.isEmpty)
    }

    func testAnUnlistedFolderIsNotLocated() throws {
        // Only the DM's own recents are bookmarked; locating is not a way to add one.
        let workspace = try folder("Eroi")

        XCTAssertNil(preferences().locateWorkspace(workspace.url))
        XCTAssertTrue(storedBookmarks.isEmpty)
    }

    func testEveryOpenStoresAFreshBookmark() throws {
        // The refresh a stale bookmark needs, done on every open rather than when asked.
        let counter = Counter()
        let preferences = preferences(bookmarks: countingBookmarks(counter))
        let workspace = try folder("Eroi")

        preferences.noteWorkspaceOpened(workspace)
        let first = storedBookmarks[workspace.url.path]
        preferences.noteWorkspaceOpened(workspace)

        XCTAssertNotNil(first)
        XCTAssertNotEqual(storedBookmarks[workspace.url.path], first)
    }

    func testAnOpenThatCannotBookmarkKeepsTheLastBookmark() throws {
        let workspace = try folder("Eroi")
        preferences().noteWorkspaceOpened(workspace)
        let kept = storedBookmarks[workspace.url.path]

        preferences(bookmarks: sandboxed).noteWorkspaceOpened(workspace)

        XCTAssertNotNil(kept)
        XCTAssertEqual(storedBookmarks[workspace.url.path], kept)
    }

    func testOpeningAMovedEntryReplacesIt() throws {
        let preferences = preferences()
        let old = try folder("Eroi")
        preferences.noteWorkspaceOpened(old)
        let moved = try folder("Eroi delle Terre di Confine")

        preferences.noteWorkspaceOpened(moved, replacing: old.url)

        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), [moved.url.path])
        XCTAssertNil(storedBookmarks[old.url.path])
    }

    func testForgettingDropsTheBookmark() throws {
        let preferences = preferences()
        let workspace = try folder("Eroi")
        preferences.noteWorkspaceOpened(workspace)

        preferences.forgetWorkspace(workspace.url)

        XCTAssertTrue(preferences.recentWorkspaces.isEmpty)
        XCTAssertNil(storedBookmarks[workspace.url.path])
        XCTAssertNil(preferences.locateWorkspace(workspace.url))
    }

    func testTheCapDropsTheBookmarksOfWhatItDrops() throws {
        let preferences = preferences(bookmarks: countingBookmarks(Counter()))
        let oldest = Workspace(url: URL(fileURLWithPath: "/workspace-0"))
        preferences.noteWorkspaceOpened(oldest)
        for index in 1...DisplayPreferences.recentsLimit {
            preferences.noteWorkspaceOpened(Workspace(url: URL(fileURLWithPath: "/workspace-\(index)")))
        }

        XCTAssertEqual(storedBookmarks.count, DisplayPreferences.recentsLimit)
        XCTAssertNil(storedBookmarks[oldest.url.path])
    }

    func testTwoSpellingsOfOneFolderShareOneBookmark() throws {
        let preferences = preferences()
        let workspace = try folder("Eroi")
        preferences.noteWorkspaceOpened(Workspace(url: URL(fileURLWithPath: workspace.url.path + "/")))

        XCTAssertNotNil(preferences.locateWorkspace(URL(fileURLWithPath: workspace.url.path + "/")))
        XCTAssertEqual(storedBookmarks.count, 1)
    }

    func testAGarbledBookmarkStoreDegradesToNone() throws {
        let workspace = try folder("Eroi")
        defaults.set([workspace.url.path], forKey: "recentWorkspaces")
        defaults.set([workspace.url.path: 42], forKey: "recentWorkspaceBookmarks")

        let preferences = preferences()

        XCTAssertEqual(preferences.recentWorkspaces.map(\.path), [workspace.url.path])
        // Treated as an entry from before bookmarks, and upgraded.
        XCTAssertNotNil(preferences.locateWorkspace(workspace.url))
    }
}
