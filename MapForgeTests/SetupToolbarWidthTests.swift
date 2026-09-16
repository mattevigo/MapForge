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

    /// The narrowest the toolbars can ever be asked to draw in.
    ///
    /// This was a bare 380 standing for "a Control Window narrow enough to be uncomfortable",
    /// which was the right measure while the toolbars spanned the whole window. They now sit
    /// in the Map column, beside the live panel, so the width they get is the column's — and
    /// the constant is read off the view rather than restated here, or the two drift and the
    /// tests keep passing while the real toolbar wraps.
    private let narrowWindow = ControlView.minimumMapColumnWidth

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

    // MARK: The window minimum and the column must agree

    /// The defect this pins: the toolbars moved into the Map column when the seam moved to
    /// the top of the window, but the window's minimum width still described the old layout
    /// — window minus nothing. At that minimum the column came out around 215 pt, and the
    /// Live Toolbar's "Measurements" broke into four stacked one-word lines while every
    /// button truncated to a stub.
    ///
    /// Nothing caught it: the width tests measured the toolbar against a 380 pt window, and
    /// a 380 pt window was no longer a 380 pt toolbar. So the arithmetic is asserted here,
    /// against the same constant the `.frame` uses.
    func testTheWindowMinimumLeavesTheMapColumnWideEnoughForItsToolbars() {
        let columnAtMinimum = ControlView.minimumWindowWidth
            - ControlView.livePanelWidth
            - ControlView.columnSpacing
            - ControlView.windowPadding * 2

        XCTAssertGreaterThanOrEqual(
            columnAtMinimum, ControlView.minimumMapColumnWidth,
            "at its minimum width the window leaves the Map column \(columnAtMinimum) pt, "
            + "under the \(ControlView.minimumMapColumnWidth) pt its toolbars are tested at — "
            + "the toolbars will wrap and truncate")
    }

    /// And the Live Toolbar specifically, because it is the row that failed visibly: its
    /// labels are words, not glyphs, and a word that does not fit wraps rather than
    /// truncating — four stacked lines where there should be one.
    @MainActor
    func testTheLiveToolbarsLabelsFitTheColumnOnOneLine() {
        // The row as `ControlView` builds it, minus the state it needs a live AppState for:
        // two labelled switches, a button, and the Session button pushed to the far end.
        let row = HStack(spacing: 16) {
            Toggle("Fog", isOn: .constant(true))
            Toggle("Measurements", isOn: .constant(true))
            Button("Viewport") {}
            Spacer()
            Button("Start Session") {}
        }

        let needed = width(of: row)
        XCTAssertLessThanOrEqual(
            needed, ControlView.minimumMapColumnWidth,
            "the Live Toolbar needs \(needed) pt but the Map column can be as narrow as "
            + "\(ControlView.minimumMapColumnWidth) pt — \"Measurements\" wraps instead of "
            + "sitting on one line")
    }
}
