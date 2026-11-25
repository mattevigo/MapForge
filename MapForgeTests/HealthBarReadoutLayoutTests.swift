import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// The DM's hit points and Health Bar: the bar in the Scene tab's Pawn rows and the Encounter
/// tab's rows, the numbers in the Encounter tab's alone.
///
/// The numbers stay where the Encounter tab always had them, and the bar runs under the
/// whole row: as wide as the row less its margins, so a fraction is readable, and costing the
/// row height only — the name is the column that would give way to anything wider.
///
/// Measured against the real SwiftUI layout, because what is on screen is the defect.
@MainActor
final class HealthBarReadoutLayoutTests: XCTestCase {
    private func size(of view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    /// The hit point column as the Encounter tab drew it before there was a bar — the
    /// formatting the readout keeps, written out once here as the baseline.
    private func columnAsItWas(current: Int, temporary: Int = 0, max: Int) -> some View {
        HStack(spacing: 1) {
            Text("\(current)")
            if temporary > 0 { Text("+\(temporary)") }
            Text("/\(max)")
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func readout(_ stats: StatBlock, kind: PawnKind = .creature) -> some View {
        HealthBarReadout(kind: kind, stats: stats, areHealthBarsOn: true)
    }

    /// A stand-in row of a known width, with the bar under it.
    private static let rowWidth: CGFloat = 300
    private func row(_ stats: StatBlock, kind: PawnKind = .creature,
                     areHealthBarsOn: Bool = true) -> some View {
        Color.clear.frame(width: Self.rowWidth, height: 20)
            .healthBarUnderRow(kind: kind, stats: stats, areHealthBarsOn: areHealthBarsOn)
    }

    // MARK: The numbers

    func testTheNumbersAreTheColumnAsItWas() {
        XCTAssertEqual(size(of: readout(StatBlock(currentHP: 30, maxHP: 60))),
                       size(of: columnAsItWas(current: 30, max: 60)))
    }

    func testWithTemporaryHitPointsToo() {
        XCTAssertEqual(size(of: readout(StatBlock(currentHP: 30, maxHP: 60, temporaryHP: 5))),
                       size(of: columnAsItWas(current: 30, temporary: 5, max: 60)))
    }

    /// A missing number is flagged, never left blank: it would stop a fight.
    func testWithNoHitPointsItIsFlagged() {
        XCTAssertGreaterThan(size(of: readout(StatBlock())).width, 0)
    }

    // MARK: The bar under the row

    /// It runs under the row: a few points taller, never a point wider.
    func testTheBarMakesTheRowTallerByItselfAndNoWider() {
        let row = size(of: row(StatBlock(currentHP: 30, maxHP: 60)))

        XCTAssertEqual(row.width, Self.rowWidth, accuracy: 0.5)
        XCTAssertEqual(row.height, 20 + HealthBarRowBar.gap + HealthBarRowBar.height, accuracy: 0.5)
    }

    /// The track takes the row's whole width less a margin each side, not the width of the
    /// numbers — the fault this layout replaces.
    func testTheTrackSpansTheRowLessItsMargins() {
        let bar = HealthBarRowBar(bar: HealthBar(kind: .creature,
                                                 stats: StatBlock(currentHP: 13, maxHP: 13))!,
                                  withholding: nil)
        let host = NSHostingView(rootView: bar.frame(width: Self.rowWidth))
        host.frame = NSRect(x: 0, y: 0, width: Self.rowWidth, height: HealthBarRowBar.height)
        host.layoutSubtreeIfNeeded()
        let rendered = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rendered)

        let middle = rendered.pixelsHigh / 2
        let scale = CGFloat(rendered.pixelsWide) / Self.rowWidth
        let painted = (0..<rendered.pixelsWide).filter {
            (rendered.colorAt(x: $0, y: middle)?.alphaComponent ?? 0) > 0.5
        }
        let first = CGFloat(painted.first ?? -1) / scale
        let last = CGFloat((painted.last ?? -1) + 1) / scale

        XCTAssertEqual(first, HealthBarRowBar.margin, accuracy: 1)
        XCTAssertEqual(last, Self.rowWidth - HealthBarRowBar.margin, accuracy: 1)
    }

    /// The withheld bar is drawn faded rather than with a glyph, so it is the same size.
    func testAWithheldBarTakesTheSameRoom() {
        XCTAssertEqual(size(of: row(StatBlock(currentHP: 30, maxHP: 60), areHealthBarsOn: false)),
                       size(of: row(StatBlock(currentHP: 30, maxHP: 60))))
    }

    /// A Treasure's row is unchanged: it never carries a bar.
    func testATreasuresRowGetsNoBar() {
        XCTAssertEqual(size(of: row(StatBlock(currentHP: 30, maxHP: 60), kind: .treasure)).height,
                       20, accuracy: 0.5)
    }

    /// Nor a Pawn with no hit points to be a fraction of.
    func testARowWithoutHitPointsGetsNoBar() {
        XCTAssertEqual(size(of: row(StatBlock())).height, 20, accuracy: 0.5)
    }
}
