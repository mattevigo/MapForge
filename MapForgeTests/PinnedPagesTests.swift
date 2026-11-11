import AppKit
import XCTest
@testable import MapForge

/// A page pinned out of the Stat Block editor's popover into a panel of its own.
///
/// The popover goes with an outside click, which is right for a page glanced at and wrong for
/// the boss's page the DM wants open all fight. Pinned, the page stays on its Monster or
/// Character whatever is selected after, in a panel the DM can resize — and over a Control
/// Window in full screen, where a window of its own would open on another Space.
@MainActor
final class PinnedPagesTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var state: AppState!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PinnedPagesTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        state = AppState(preferences: DisplayPreferences(defaults: defaults),
                         fogStore: FogStore(),
                         partyStore: PartyStore(directory: directory))
        state.open(Workspace(url: directory))
        state.bestiary = Bestiary(monsters: [
            Monster(name: "Ogre", armorClass: 11, hitPoints: 59, initiativeBonus: -1),
            Monster(name: "Goblin", armorClass: 15, hitPoints: 7, initiativeBonus: 2),
        ])
    }

    override func tearDownWithError() throws {
        state.pinnedPages.closeAll()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var pages: PinnedPages { state.pinnedPages }

    // MARK: One panel per page

    func testPinningOpensThePageInAPanel() throws {
        pages.pin(.monster("Ogre"), appState: state)

        let panel = try XCTUnwrap(pages.panel(for: .monster("Ogre")))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.title, "Ogre")
    }

    /// O1 and O7 are both Ogres: the second pin brings the first's panel forward.
    func testPinningAPageAlreadyPinnedOpensNoSecondPanel() throws {
        pages.pin(.monster("Ogre"), appState: state)
        let first = try XCTUnwrap(pages.panel(for: .monster("Ogre")))

        pages.pin(.monster("Ogre"), appState: state)

        XCTAssertEqual(pages.pinned, [.monster("Ogre")])
        XCTAssertTrue(pages.panel(for: .monster("Ogre")) === first)
    }

    /// The boss's and the minions' pages, open side by side.
    func testDifferentPagesArePinnedSideBySide() {
        pages.pin(.monster("Ogre"), appState: state)
        pages.pin(.monster("Goblin"), appState: state)

        XCTAssertEqual(pages.pinned, [.monster("Ogre"), .monster("Goblin")])
    }

    func testClosingAPanelUnpinsItsPage() throws {
        pages.pin(.monster("Ogre"), appState: state)

        try XCTUnwrap(pages.panel(for: .monster("Ogre"))).close()

        XCTAssertTrue(pages.pinned.isEmpty)
    }

    /// The next Workspace's Ogre is another note: the old one's panel does not stay to show it.
    func testClosingTheWorkspaceClosesItsPinnedPages() {
        pages.pin(.monster("Ogre"), appState: state)

        state.closeWorkspace()

        XCTAssertTrue(pages.pinned.isEmpty)
    }

    // MARK: The panel

    func testThePanelCanBeResized() throws {
        pages.pin(.monster("Ogre"), appState: state)

        XCTAssertTrue(try XCTUnwrap(pages.panel(for: .monster("Ogre"))).styleMask.contains(.resizable))
    }

    /// Without it, a panel opened from a Control Window in full screen opens on a Space of
    /// its own and takes the DM away from the fight.
    func testThePanelOpensOverAControlWindowInFullScreen() throws {
        pages.pin(.monster("Ogre"), appState: state)

        let panel = try XCTUnwrap(pages.panel(for: .monster("Ogre")))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.isFloatingPanel)
    }

    // MARK: Where it opens

    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1050)
    private let size = CGSize(width: 404, height: 600)

    func testItOpensRightOfTheControlWindowWhenTheScreenHasRoom() {
        let control = NSRect(x: 100, y: 200, width: 1000, height: 800)

        let frame = PinnedPages.frame(of: size, beside: control, within: screen, cascade: 0)

        XCTAssertGreaterThanOrEqual(frame.minX, control.maxX)
        XCTAssertEqual(frame.maxY, control.maxY)
        XCTAssertEqual(frame.size, size)
    }

    /// The Control Window in full screen fills the screen: the panel goes inside its right
    /// edge, over the window, rather than off the screen.
    func testItOpensInsideTheScreenOverAControlWindowThatFillsIt() {
        let frame = PinnedPages.frame(of: size, beside: screen, within: screen, cascade: 0)

        XCTAssertTrue(screen.contains(frame), "\(frame)")
        XCTAssertGreaterThan(frame.minX, screen.midX)
    }

    func testEachFurtherPinStepsAside() {
        let first = PinnedPages.frame(of: size, beside: screen, within: screen, cascade: 0)
        let second = PinnedPages.frame(of: size, beside: screen, within: screen, cascade: 1)

        XCTAssertNotEqual(first.origin, second.origin)
    }

    /// A page taller than the screen opens no taller than the screen.
    func testItNeverOpensPastTheScreen() {
        let tall = CGSize(width: 404, height: 3000)

        let frame = PinnedPages.frame(of: tall, beside: nil, within: screen, cascade: 5)

        XCTAssertTrue(screen.contains(frame), "\(frame)")
    }
}
