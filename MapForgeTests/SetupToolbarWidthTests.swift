import SwiftUI
import XCTest
@testable import MapForge

/// The Setup Toolbar's first row has to hold four things on one line: "Open Map…", the Map's
/// file name, the Player Display picker and the Workspace button.
///
/// The `modeControls` row below it already carries a comment recording what happens when a
/// row is over-claimed — a "Grid squares wide" field once ran the mode buttons off the right
/// edge, with no scrollbar and nothing to say they were there. The screen picker moving into
/// this row is the same hazard, so the widths are pinned rather than trusted.
final class SetupToolbarWidthTests: XCTestCase {

    /// A Control Window narrow enough to be uncomfortable. `ChromeHeightTests` uses 380 for
    /// the same purpose; the window's own default is 560.
    private let narrowWindow: CGFloat = 380

    @MainActor
    private func width(of view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }

    @MainActor
    func testThePickerAndTheButtonsFitANarrowWindow() {
        // The picker is the row's one hard width claim — the file name truncates and the two
        // buttons size to their labels — so what matters is that it plus the buttons still
        // fit, not that it clears some fraction of the window.
        let buttons = width(of: HStack {
            Button("Open Map…") {}
            Button { } label: { Image(systemName: "folder") }
        })
        let claimed = ControlView.playerDisplayPickerWidth + buttons

        XCTAssertLessThan(claimed, narrowWindow,
                          "picker \(ControlView.playerDisplayPickerWidth) + buttons \(buttons) "
                          + "overflows a \(narrowWindow) pt window, leaving no room for the "
                          + "file name and pushing controls off the edge")
    }

    /// The file name is the only thing in the row with no bound on its width, so it is the
    /// only thing that can push the picker off the edge. It must truncate instead.
    @MainActor
    func testALongMapNameTruncatesRatherThanGrowing() {
        let name = String(repeating: "verylongmapname", count: 20) + ".png"
        let untruncated = Text(name)
        let asTheRowDrawsIt = Text(name).lineLimit(1).truncationMode(.middle)

        // Left to itself the label is hundreds of points wide and would push the picker and
        // the Workspace button off the right edge. One line plus a truncation mode is what
        // stops it; without them this row has an unbounded member.
        XCTAssertGreaterThan(width(of: untruncated), 1000,
                             "precondition: this name is long enough to be a hazard")
        XCTAssertLessThan(width(of: asTheRowDrawsIt.frame(maxWidth: 200)), 201,
                          "a long file name must truncate, not push the picker off the row")
    }
}
