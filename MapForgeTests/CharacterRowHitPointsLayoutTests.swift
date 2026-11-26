import AppKit
import SwiftUI
import XCTest
@testable import MapForge

/// A Character's row in the Party panel with its hit points in it: the Encounter tab's
/// numbers, the DM's Health Bar under the whole row as the Scene and Encounter rows draw it,
/// and never faded — a Character has no switch of its own for what the table sees.
///
/// Measured against the real SwiftUI layout, because what is on screen is the defect.
@MainActor
final class CharacterRowHitPointsLayoutTests: XCTestCase {
    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    private func shown(currentHP: Int, temporaryHP: Int = 0, exhaustion: Int = 0) throws
        -> CharacterHitPoints {
        try XCTUnwrap(CharacterHitPoints(
            character: PartyCharacter(name: "Durga", noteName: "Durga Pietraferma",
                                      sharedNumbers: SharedNumbers(currentHP: currentHP,
                                                                   temporaryHP: temporaryHP,
                                                                   exhaustion: exhaustion)),
            note: durgaNote))
    }

    private func size(of view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    private static let rowWidth: CGFloat = 300
    private func row(_ shown: CharacterHitPoints?) -> some View {
        Color.clear.frame(width: Self.rowWidth, height: 20)
            .characterHitPointsUnderRow(shown)
    }

    /// The same view as the Encounter tab's, so the roster cannot write them differently.
    func testTheNumbersAreTheEncounterTabs() throws {
        let durga = try shown(currentHP: 24, temporaryHP: 5)

        XCTAssertEqual(size(of: CharacterHitPointsLabel(shown: durga)),
                       size(of: HealthBarReadout(kind: .player,
                                                 stats: StatBlock(currentHP: 24, maxHP: 48,
                                                                  temporaryHP: 5),
                                                 areHealthBarsOn: true)))
    }

    /// The exhaustion marker sits beside the numbers, on their line.
    func testTheExhaustionMarkerKeepsToTheNumbersLine() throws {
        let tired = size(of: CharacterHitPointsLabel(shown: try shown(currentHP: 24, exhaustion: 2)))
        let rested = size(of: CharacterHitPointsLabel(shown: try shown(currentHP: 24)))

        XCTAssertGreaterThan(tired.width, rested.width)
        XCTAssertEqual(tired.height, rested.height, accuracy: 0.5)
    }

    /// Under the row, as the Scene and Encounter rows carry it: taller, never wider.
    func testTheBarRunsUnderTheRow() throws {
        let row = size(of: row(try shown(currentHP: 24)))

        XCTAssertEqual(row.width, Self.rowWidth, accuracy: 0.5)
        XCTAssertEqual(row.height, 20 + HealthBarRowBar.gap + HealthBarRowBar.height, accuracy: 0.5)
    }

    func testACharacterWithNothingToShowKeepsItsRowAsItWas() {
        XCTAssertEqual(size(of: row(nil)).height, 20, accuracy: 0.5)
    }

    /// Drawn at full strength: the faded look says the table is not shown a bar, which is
    /// each Pawn's to say, not the Character's.
    func testTheBarIsNeverFaded() throws {
        let host = NSHostingView(rootView: row(try shown(currentHP: 48)))
        let height = 20 + HealthBarRowBar.gap + HealthBarRowBar.height
        host.frame = NSRect(x: 0, y: 0, width: Self.rowWidth, height: height)
        host.layoutSubtreeIfNeeded()
        let rendered = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rendered)

        // Halfway along the bar, halfway down it — the bitmap's rows run top-down.
        let scale = CGFloat(rendered.pixelsHigh) / height
        let y = Int((height - HealthBarRowBar.height / 2) * scale)
        let alpha = rendered.colorAt(x: rendered.pixelsWide / 2, y: y)?.alphaComponent ?? 0

        XCTAssertGreaterThan(alpha, 0.9)
    }
}
