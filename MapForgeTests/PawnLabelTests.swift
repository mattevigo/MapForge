import XCTest
@testable import MapForge

/// A Pawn's label: how it is chosen, and whether it can be read at the table.
final class PawnLabelTests: XCTestCase {

    // MARK: Auto-numbering

    func testTheFirstPawnIsOne() {
        XCTAssertEqual(Pawn.nextLabel(after: []), "1")
    }

    func testEachPawnTakesTheNextNumber() {
        XCTAssertEqual(Pawn.nextLabel(after: [pawn("1"), pawn("2")]), "3")
    }

    func testDeletingAPawnDoesNotCauseACollision() {
        // The defect: `pawns.count + 1` reuses a label after a delete. Place three,
        // delete the second, and the next Pawn is also "3" — two tokens with one name,
        // in the middle of a fight.
        XCTAssertEqual(Pawn.nextLabel(after: [pawn("1"), pawn("3")]), "4")
    }

    func testRenamedPawnsDoNotBlockTheNumbering() {
        // A DM renames "2" to "Goblin B". The next auto-label counts from the numbers
        // that are left, not from how many Pawns there are.
        XCTAssertEqual(Pawn.nextLabel(after: [pawn("1"), pawn("Goblin B")]), "2")
    }

    func testAllNamedPawnsStartTheNumberingOver() {
        // Nothing numeric to count from. "1" is right — and it is unused.
        XCTAssertEqual(Pawn.nextLabel(after: [pawn("Vex"), pawn("Goblin B")]), "1")
    }

    func testAnAbsurdLabelDoesNotCrashTheNextPlacement() {
        // The live rename field takes any text. `highest + 1` on Int.max traps, so a DM
        // who types it would crash the app on the next Pawn they place.
        XCTAssertEqual(Pawn.nextLabel(after: [pawn("\(Int.max)")]), "\(Int.max)")
    }

    // MARK: Legibility

    func testALabelIsDrawnAtTheSizesAMapActuallyProduces() {
        // The real defect behind "Pawns should have labels": they have them, and at the
        // diameters all three call sites floor to (10-12 pt) they were suppressed
        // entirely, so a Pawn rendered as an unlabelled dot — on the Player Display too.
        for diameter in [10.0, 12.0, 14.0] as [CGFloat] {
            XCTAssertTrue(PawnToken.showsLabel(atDiameter: diameter),
                          "a \(diameter) pt token drew no label")
        }
    }

    func testALabelIsSuppressedOnlyWhenItCouldNotBeReadAtAll() {
        // Not "never suppress": below a few points the glyph is one or two pixels of
        // grey and only muddies the disc's colour, which is what a player identifies a
        // token by.
        XCTAssertFalse(PawnToken.showsLabel(atDiameter: 6))
    }

    // MARK: Who the label is for

    func testTheTableNeverReadsALabel() {
        // A label is the DM's own bookkeeping — "Goblin B", "3", "Ambusher (hidden)". The
        // Player Display is the world, and the world does not caption itself.
        for diameter in [10.0, 12.0, 14.0, 40.0] as [CGFloat] {
            XCTAssertFalse(PawnToken.showsLabel(atDiameter: diameter, toPlayers: true),
                           "a \(diameter) pt token captioned itself at the table")
        }
    }

    func testTheDMStillReadsLabelsAtEverySizeTheyUsedTo() {
        // The suppression is about who is looking, not about giving up the legibility
        // floor that `testALabelIsDrawnAtTheSizesAMapActuallyProduces` bought.
        for diameter in [10.0, 12.0, 14.0, 40.0] as [CGFloat] {
            XCTAssertTrue(PawnToken.showsLabel(atDiameter: diameter, toPlayers: false),
                          "the DM lost the label on a \(diameter) pt token")
        }
    }

    func testWhetherTheTableReadsLabelsIsSettledWhereEveryOtherLeakIs() {
        // `PlayerVisibility` is the one place that answers "what do the players get to
        // see", and a label crossing the room is that kind of leak. Asking it here means
        // the rule cannot be lost by someone editing a view.
        XCTAssertFalse(PlayerVisibility.showsPawnLabelToPlayers)
    }

    func testTheDMIsWhoTheTokenDrawsForUnlessToldOtherwise() {
        // Three of the four call sites are DM chrome — the preview, the live row, the
        // roster. Defaulting to the DM means none of them can silently lose their labels,
        // and the one screen that must stay silent says so explicitly.
        XCTAssertEqual(PawnToken.showsLabel(atDiameter: 12),
                       PawnToken.showsLabel(atDiameter: 12, toPlayers: false))
    }

    // MARK: Helpers

    private func pawn(_ label: String) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0), label: label,
             colorHex: Pawn.defaultColorHex, brightSquares: 6)
    }
}
