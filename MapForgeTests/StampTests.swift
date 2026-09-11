import XCTest
@testable import MapForge

/// Stamping: dragging a Character onto the Map creates a Pawn copied from it.
///
/// The decision the drop makes — where it landed, whether that is on the Map at all, and what
/// Pawn results — kept out of the SwiftUI drop handler so it can be tested at all.
final class StampTests: XCTestCase {
    /// A 1000×800 Map drawn into a 500×400 frame at the origin: one image pixel per half
    /// point, so a drop at (100, 80) is image pixel (200, 160).
    private let map = MapScale(imagePixelSize: CGSize(width: 1000, height: 800),
                               physicalWidthInches: 20)
    private let frame = CGRect(x: 0, y: 0, width: 500, height: 400)

    private let thorin = PartyCharacter(name: "Thorin", colorHex: "#1E90C8",
                                        sightSquares: 9, isBig: true)

    func testTheStampLandsWhereItWasDropped() {
        // Free-form, under the cursor: no Grid snapping, as click-to-place and dragging a
        // Pawn have never snapped either.
        let pawn = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 100, y: 80),
                              map: map, frame: frame)
        XCTAssertEqual(pawn?.at.x ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(pawn?.at.y ?? 0, 160, accuracy: 0.001)
    }

    func testTheStampCopiesTheCharacter() {
        let pawn = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 100, y: 80),
                              map: map, frame: frame)
        XCTAssertEqual(pawn?.label, "Thorin")
        XCTAssertEqual(pawn?.colorHex, "#1E90C8")
        XCTAssertEqual(pawn?.light.brightSquares, 9)
        XCTAssertEqual(pawn?.isBig, true)
        XCTAssertEqual(pawn?.characterID, thorin.id)
    }

    func testAStampIsAlwaysAPartyMemberAndNeverHidden() {
        // The roster holds Players only, and a Pawn arriving hidden would be a Pawn the DM
        // cannot see they have just placed.
        let pawn = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 10, y: 10),
                              map: map, frame: frame)
        XCTAssertEqual(pawn?.kind, .player)
        XCTAssertEqual(pawn?.isHidden, false)
    }

    func testAStampedPawnLightsAsAHandPlacedOneDoes() {
        // The feature must not create a second way for a Pawn to be lit: dim is derived from
        // sight, never carried over from the Character.
        let pawn = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 10, y: 10),
                              map: map, frame: frame)
        XCTAssertEqual(pawn?.light.dimSquares, Pawn.dimSquares(forSight: 9))
        XCTAssertEqual(pawn?.light.isOn, true)
    }

    func testADropOutsideTheMapStampsNothing() {
        // Refused, not clamped. A Pawn outside the image is meaningless to Visibility, whose
        // four implicit boundary Walls sit at exactly those bounds.
        for point in [CGPoint(x: -1, y: 50), CGPoint(x: 50, y: -1),
                      CGPoint(x: 501, y: 50), CGPoint(x: 50, y: 401)] {
            XCTAssertNil(Stamp.pawn(from: thorin, droppedAt: point, map: map, frame: frame),
                         "a drop at \(point) should have been refused")
        }
    }

    func testTheMapsEdgesAreOnTheMap() {
        // The boundary itself is a legal place to stand — a character with their back to the
        // wall is the ordinary case, not an error.
        XCTAssertNotNil(Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 0, y: 0),
                                   map: map, frame: frame))
        XCTAssertNotNil(Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 500, y: 400),
                                   map: map, frame: frame))
    }

    func testADropIntoAPannedFrameLandsCorrectly() {
        // At True Scale most Maps exceed the screen, so the frame carries the pan and its
        // origin is negative. Getting this wrong would land every token plausibly but wrong.
        let panned = CGRect(x: -250, y: -200, width: 500, height: 400)
        let pawn = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 0, y: 0),
                              map: map, frame: panned)
        XCTAssertEqual(pawn?.at.x ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(pawn?.at.y ?? 0, 400, accuracy: 0.001)
    }

    func testStampingTwiceGivesTwoPawnsSharingALabel() {
        // Duplicates are deliberate and are never auto-renamed: a summon or a mirror image is
        // real, and editing the name the DM chose would be the app second-guessing them.
        let first = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 10, y: 10),
                               map: map, frame: frame)
        let second = Stamp.pawn(from: thorin, droppedAt: CGPoint(x: 20, y: 20),
                                map: map, frame: frame)
        XCTAssertEqual(first?.label, second?.label)
        XCTAssertNotEqual(first?.id, second?.id)
        XCTAssertEqual(first?.characterID, second?.characterID)
    }

    func testADegenerateFrameStampsNothing() {
        // A zero frame is a view that has not laid out yet. Dividing by it would put the Pawn
        // at a NaN that then poisons every distance measured from it.
        XCTAssertNil(Stamp.pawn(from: thorin, droppedAt: .zero, map: map, frame: .zero))
    }
}
