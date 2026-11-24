import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// The Scene tab's Pawn row with the DM's Health Bar in it.
///
/// The name field is that row's one flexible member, and the buttons beside it already leave
/// it little room, so the hit points must not take any of it. Measured in the real Control
/// Window at its minimum width — the panel's width is fixed, so this is the width the row
/// always has — by comparing a Pawn that has hit points with one that has none.
@MainActor
final class ScenePawnRowHealthBarLayoutTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ScenePawnRowHealthBarLayoutTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// The name fields in the hosted window, by the name in them.
    private func nameFieldWidths(in state: AppState) -> [String: CGFloat] {
        let host = NSHostingView(rootView: ControlView().environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: ControlView.minimumWindowWidth, height: 900)
        host.layoutSubtreeIfNeeded()
        var widths: [String: CGFloat] = [:]
        func walk(_ view: NSView) {
            if let field = view as? NSTextField, field.isEditable {
                widths[field.stringValue] = field.frame.width
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return widths
    }

    func testHitPointsTakeNoWidthFromThePawnsName() throws {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.open(Workspace(url: directory))
        state.mapURL = directory.appendingPathComponent("cave.png")
        let wounded = Pawn(at: MapPoint(x: 100, y: 100), label: "Goblin B", colorHex: "#C81E1E",
                           brightSquares: 0, kind: .creature)
        let unnumbered = Pawn(at: MapPoint(x: 200, y: 100), label: "Goblin C", colorHex: "#C81E1E",
                              brightSquares: 0, kind: .creature)
        state.fog.pawns = [wounded, unnumbered]
        state.setStatBlock(StatBlock(currentHP: 30, maxHP: 60, temporaryHP: 5), for: wounded.id)

        let widths = nameFieldWidths(in: state)
        let withHitPoints = try XCTUnwrap(widths["Goblin B"], "no name field found: \(widths)")
        let without = try XCTUnwrap(widths["Goblin C"], "no name field found: \(widths)")

        XCTAssertGreaterThan(without, 0)
        XCTAssertEqual(withHitPoints, without, accuracy: 0.5,
                       "the hit points squeeze the name field from \(without) to \(withHitPoints) pt")
    }
}
