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
