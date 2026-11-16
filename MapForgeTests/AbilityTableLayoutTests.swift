import SwiftUI
import XCTest
@testable import MapForge

/// The ability table's two blocks of three sit side by side where the Page is wide enough for
/// them at body size, and stack where it is not — never shrunk or truncated to fit.
///
/// Measured at the two widths the Page is drawn at, read off the views that draw it, so the
/// popover or the panel cannot change width without these noticing.
final class AbilityTableLayoutTests: XCTestCase {
    private let table = PageText.abilities(AbilityScores([18, 14, 16, 10, 13, 8]),
                                                   saves: [.init(name: "Saggezza ●", bonus: 13)])!

    @MainActor
    private func height(at width: CGFloat) -> CGFloat {
        NSHostingView(rootView: AbilityTableView(table: table).frame(width: width)
            .environment(\.locale, .interface)).fittingSize.height
    }

    @MainActor
    func testInThePopoverTheBlocksSitSideBySide() {
        // As tall as one block of three: as tall as on a Page with all the room it wants.
        XCTAssertEqual(height(at: PawnPage.width), height(at: 2000), accuracy: 0.5)
    }

    @MainActor
    func testInAPanelAtItsNarrowestTheBlocksStack() {
        // Two blocks of three, one above the other: about twice as tall.
        XCTAssertGreaterThan(height(at: PawnPage.minimumPanelSize.width),
                             1.8 * height(at: 2000))
    }
}
