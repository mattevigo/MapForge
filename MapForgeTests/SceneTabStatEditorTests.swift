import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// The Scene tab's Pawn rows and the Stat Editor at the tab's foot, in the real Control
/// Window at its minimum width — the panel's width is fixed, so this is the width it always
/// has. The Scene tab is the one the window opens on.
///
/// Read through the AppKit fields SwiftUI draws: a Pawn's label typed into a field is an
/// editable `NSTextField` holding it, and the editor's hit points are two more.
@MainActor
final class SceneTabStatEditorTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SceneTabStatEditorTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private let goblin = Pawn(at: MapPoint(x: 100, y: 100), label: "Goblin B", colorHex: "#C81E1E",
                              brightSquares: 0, kind: .creature)

    private func makeAppState() -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.open(Workspace(url: directory))
        state.mapURL = directory.appendingPathComponent("cave.png")
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20
        state.fog.pawns = [goblin]
        state.setStatBlock(StatBlock(currentHP: 31, maxHP: 47), for: goblin.id)
        return state
    }

    /// The editable fields in the hosted window: their text, and whether they take typing.
    private func fields(in state: AppState) -> [(text: String, isEnabled: Bool)] {
        let host = NSHostingView(rootView: ControlView().environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: ControlView.minimumWindowWidth, height: 900)
        host.layoutSubtreeIfNeeded()
        var found: [(String, Bool)] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField, field.isEditable {
                found.append((field.stringValue, field.isEnabled))
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
    }

    /// Renaming is the Edit Pawn sheet's: the row shows the label, and a field there was a
    /// second, unrecorded way to rename a Pawn beside a row that is now a click target.
    func testTheRowShowsItsLabelAsTextNotAField() {
        let texts = fields(in: makeAppState()).map(\.text)

        XCTAssertFalse(texts.contains("Goblin B"), "a name field is still in the row: \(texts)")
    }

    func testWithNothingPointedAtTheSceneTabShowsNoEditor() {
        let texts = fields(in: makeAppState()).map(\.text)

        XCTAssertFalse(texts.contains("31"), "an editor with nobody pointed at: \(texts)")
    }

    func testTheSceneTabsEditorShowsThePawnPointedAt() {
        let state = makeAppState()
        state.statEditorPawn = goblin.id

        let found = fields(in: state)

        XCTAssertTrue(found.contains { $0.text == "31" && $0.isEnabled }, "fields: \(found)")
        XCTAssertTrue(found.contains { $0.text == "47" && $0.isEnabled }, "fields: \(found)")
    }

    /// ADR-0010: an edit in the wrong mode is silent and wrong, and the Scene tab has no
    /// correcting bar to say which mode it is in.
    func testWhileCorrectingTheSceneTabsEditorTakesNoTyping() {
        let state = makeAppState()
        state.startSession()
        state.startEncounter()
        state.endTurn()
        state.stepBackForCorrection()
        XCTAssertNotNil(state.encounter?.correctionTarget, "precondition: correcting")
        state.statEditorPawn = goblin.id

        let hitPoints = fields(in: state).filter { $0.text == "31" }

        XCTAssertFalse(hitPoints.isEmpty, "the editor should still show whom it would edit")
        XCTAssertTrue(hitPoints.allSatisfy { !$0.isEnabled }, "fields: \(hitPoints)")
    }
}
