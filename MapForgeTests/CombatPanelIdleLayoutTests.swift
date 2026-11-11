import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// The Combat tab with a Pawn selected, and the page of the DM's notes it opens.
///
/// The roster before Play was a plain stack while the Order is a ScrollView. A fight's long
/// Order scrolled; a long roster before it could not, so selecting one of 34 Pawns put the
/// Stat Block editor under a list that already filled the tab. The panel overflowed — Play
/// clipped off the top, the editor off the bottom — and the Monster's page under the
/// editor, a ScrollView with nothing left to share, was squeezed to nothing. The roster
/// scrolls now, and the page is a popover with no list to share the height with.
///
/// Measured against the real SwiftUI layout, hosted at a tab's size: what is on screen is
/// the defect, and nothing short of laying the panel out says what is on screen.
@MainActor
final class CombatPanelIdleLayoutTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let ogre = Monster(name: "Ogre", armorClass: 11, hitPoints: 59, initiativeBonus: -1)
    private let tab = CGSize(width: 440, height: 900)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CombatPanelIdleLayoutTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// No Session, as in the report: the roster is shown under the refusal, not under Play.
    private func makeAppState(ogres count: Int, monsters: [Monster]? = nil) -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.open(Workspace(url: directory))
        state.mapURL = directory.appendingPathComponent("cave.png")
        state.bestiary = Bestiary(monsters: monsters ?? [ogre])
        state.fog.pawns = (0..<count).map {
            Pawn(at: MapPoint(x: 100, y: 100), label: "O\($0)", colorHex: "#C81E1E",
                 brightSquares: 6, kind: .creature, monsterName: ogre.name)
        }
        return state
    }

    private func panel(_ state: AppState, selecting id: Pawn.ID?) -> some View {
        CombatPanel(selection: .constant(id)).environmentObject(state)
    }

    /// The height the panel asks for in a tab of `tab`'s size.
    private func height(of state: AppState, selecting id: Pawn.ID?) -> CGFloat {
        NSHostingController(rootView: panel(state, selecting: id).frame(width: tab.width))
            .sizeThatFits(in: tab).height
    }

    /// The panel's ScrollViews as AppKit lays them out, top to bottom.
    private func scrollViewHeights(of state: AppState, selecting id: Pawn.ID?) -> [CGFloat] {
        let host = NSHostingView(rootView: panel(state, selecting: id))
        host.frame = NSRect(origin: .zero, size: tab)
        host.layoutSubtreeIfNeeded()
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
            .sorted { $0.convert($0.bounds, to: host).minY < $1.convert($1.bounds, to: host).minY }
            .map(\.frame.height)
    }

    /// A 1080p screen's visible height, under the menu bar and above a Dock.
    private let screenHeight: CGFloat = 1000

    /// The popover's size: a popover is as big as its content asks to be.
    private func popoverSize(of page: PawnPage, in state: AppState) -> CGSize {
        NSHostingView(rootView: page.inPopover(onScreenOfHeight: screenHeight)
            .environmentObject(state)).fittingSize
    }

    // MARK: The panel

    func testALongRosterWithAPawnSelectedStillFitsTheTab() {
        let state = makeAppState(ogres: 34)

        XCTAssertLessThanOrEqual(height(of: state, selecting: state.fog.pawns[0].id), tab.height,
                                 "the idle panel overflows: Play and the editor are clipped")
    }

    /// The Monster's page is not drawn in the tab: the roster's is its only ScrollView.
    func testTheSelectedMonstersPageIsNotUnderTheEditor() {
        let state = makeAppState(ogres: 34)

        XCTAssertEqual(scrollViewHeights(of: state, selecting: state.fog.pawns[0].id).count, 1)
    }

    /// Nor during the fight, where the Order's is the only one.
    func testTheActiveCombatantsPageIsNotUnderTheEditorDuringAFight() {
        let state = makeAppState(ogres: 34)
        state.startSession()
        state.startEncounter()
        XCTAssertNotNil(state.encounter)

        XCTAssertEqual(scrollViewHeights(of: state, selecting: nil).count, 1)
    }

    /// A short roster is not given more than its rows, so the editor sits right under them.
    func testAShortRosterTakesOnlyTheHeightOfItsRows() {
        let state = makeAppState(ogres: 3)

        let heights = scrollViewHeights(of: state, selecting: state.fog.pawns[0].id)

        XCTAssertEqual(heights.count, 1, "\(heights)")
        XCTAssertLessThan(heights.first ?? .infinity, 100, "the roster takes more than its rows: \(heights)")
    }

    // MARK: The page

    func testAMonstersPawnHasAPage() {
        let state = makeAppState(ogres: 1)

        XCTAssertNotNil(PawnPage(pawn: state.fog.pawns[0], appState: state))
    }

    /// Even when its Monster has left the notes: the page then says so, and the DM learns it
    /// from the button rather than wondering why there is none.
    func testAPawnWhoseMonsterLeftTheNotesStillHasAPage() {
        let state = makeAppState(ogres: 1, monsters: [])

        XCTAssertNotNil(PawnPage(pawn: state.fog.pawns[0], appState: state))
    }

    func testAPlainPawnHasNoPage() {
        let state = makeAppState(ogres: 0)
        let plain = Pawn(at: MapPoint(x: 100, y: 100), label: "Barkeep", colorHex: "#C81E1E",
                         brightSquares: 6, kind: .creature)

        XCTAssertNil(PawnPage(pawn: plain, appState: state))
    }

    /// Nearly the whole screen, short only of a margin above and below.
    func testThePageMayBeNearlyAsTallAsTheScreen() {
        XCTAssertEqual(PawnPage.maxHeight(onScreenOfHeight: 1000),
                       1000 - 2 * PawnPage.screenMargin - 2 * PawnPage.padding)
    }

    /// With no screen to measure, a cap that fits any screen a Mac has.
    func testWithNoScreenThePageHasAFixedCap() {
        XCTAssertEqual(PawnPage.maxHeight(onScreenOfHeight: nil), PawnPage.fallbackMaxHeight)
    }

    /// A Caos Orb's page is longer than any screen is tall: past the cap it scrolls inside
    /// the popover instead of running the popover off the screen.
    func testALongPageIsCappedAndScrolls() throws {
        var orb = ogre
        orb.actions = (1...40).map {
            Monster.Feature(name: "Attack \($0)",
                            desc: "Melee Weapon Attack: +6 to hit, reach 5 ft., one target. Hit: 13 (2d8 + 4) bludgeoning damage.")
        }
        let state = makeAppState(ogres: 1, monsters: [orb])
        let page = try XCTUnwrap(PawnPage(pawn: state.fog.pawns[0], appState: state))

        XCTAssertEqual(popoverSize(of: page, in: state).height, screenHeight - 2 * PawnPage.screenMargin,
                       accuracy: 1, "the popover, padding and all, stops short of the margins")
    }

    /// A page that scrolls, but has less to say than the cap, is not stretched to it.
    func testAShortMonstersPageIsNotPaddedToTheCap() throws {
        let state = makeAppState(ogres: 1)
        let page = try XCTUnwrap(PawnPage(pawn: state.fog.pawns[0], appState: state))

        XCTAssertLessThan(popoverSize(of: page, in: state).height, PawnPage.fallbackMaxHeight)
    }

    /// And a caption is not padded out to the cap: the popover is as tall as what it says.
    func testAShortPageIsAsTallAsItsText() throws {
        let state = makeAppState(ogres: 1, monsters: [])
        let page = try XCTUnwrap(PawnPage(pawn: state.fog.pawns[0], appState: state))

        let size = popoverSize(of: page, in: state)
        XCTAssertGreaterThan(size.height, 10)
        XCTAssertLessThan(size.height, 120)
    }
}
