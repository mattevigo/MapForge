import XCTest
@testable import MapForge

/// Which click and which Esc reach the **Selection**, and which go to whatever is armed.
///
/// Picking happens only while nothing is armed — no Add, no Measurement, no Viewport. While
/// something is, every click belongs to it as before, ⇧ or not; and Esc backs out of it
/// first, so the DM who armed a tool and changed their mind does not lose the Selection
/// they had picked (`CONTEXT.md`, **Selection**; the `pawn-selection` spec).
final class SelectionRoutingTests: XCTestCase {
    private let rogue = Pawn(at: MapPoint(x: 100, y: 100), label: "Rogue",
                             colorHex: Pawn.defaultColorHex, brightSquares: 6)
    private let lantern = Light(at: MapPoint(x: 300, y: 300), brightSquares: 4, name: "lantern")

    // MARK: Clicks

    func testShiftClickOnAPawnWithNothingArmedTogglesIt() {
        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: true,
                                           on: .pawn(rogue.id)),
                       .toggle(.pawn(rogue.id)))
    }

    func testShiftClickOnALightMarkerWithNothingArmedTogglesIt() {
        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: true,
                                           on: .light(lantern.id)),
                       .toggle(.light(lantern.id)))
    }

    /// The Pawn is drawn above the Light Marker it stands on, and is what the DM means —
    /// the order `LiveHitTest` already keeps for the right-click menu.
    func testShiftClickOnAPawnStandingOnALightPicksThePawn() {
        let brazier = Light(at: rogue.at, brightSquares: 2, name: "brazier")
        let target = LiveHitTest.hit(at: rogue.at, pawns: [rogue], lights: [brazier],
                                     gridPixels: 20)

        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: true, on: target),
                       .toggle(.pawn(rogue.id)))
    }

    /// With Add armed, ⇧-click on a token still places the new Pawn — the click is the
    /// armed tool's, exactly as a plain one is.
    func testShiftClickWithSomethingArmedGoesToTheArmedTool() {
        XCTAssertEqual(ArmedTool.State(hasArmedAdd: true).leftClick(isShiftDown: true,
                                           on: .pawn(rogue.id)),
                       .armedTool)
        XCTAssertEqual(ArmedTool.State(hasArmedAdd: true).leftClick(isShiftDown: false, on: nil),
                       .armedTool)
    }

    func testAPlainClickOnTheBareMapWithNothingArmedEndsTheSelection() {
        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: false, on: nil),
                       .clearSelection)
    }

    /// A plain click on a token is the start of its drag, or nothing; it neither picks it
    /// nor drops the rest.
    func testAPlainClickOnATokenWithNothingArmedDoesNothing() {
        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: false,
                                           on: .pawn(rogue.id)),
                       .nothing)
        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: false,
                                           on: .light(lantern.id)),
                       .nothing)
    }

    /// A ⇧-click that misses every token is the DM adding one more and missing — not a
    /// reason to let the rest go.
    func testAShiftClickOnTheBareMapKeepsTheSelection() {
        XCTAssertEqual(ArmedTool.State().leftClick(isShiftDown: true, on: nil),
                       .nothing)
    }

    /// The Viewport counts as armed: a click with the rectangle armed is for moving what the
    /// table sees, and must not end the Selection on the way.
    func testTheArmedViewportKeepsClicksFromPicking() {
        XCTAssertEqual(ArmedTool.State(isViewportArmed: true).leftClick(isShiftDown: false,
                                                                        on: nil),
                       .armedTool)
    }

    // MARK: Esc

    /// Esc peels back one layer at a time: the armed tool first, then the Selection. The DM
    /// who armed Add and thought better of it keeps the Selection they had picked.
    func testEscDisarmsAddFirstAndClearsTheSelectionOnTheNextPress() {
        XCTAssertEqual(escape(add: true), .disarmAdd)
        // `ControlView` has disarmed Add; the next press finds nothing armed.
        XCTAssertEqual(escape(), .clearSelection)
    }

    func testEscDisarmsAnArmedShapeFirstAndClearsTheSelectionOnTheNextPress() {
        XCTAssertEqual(escape(shape: true), .disarmShape)
        XCTAssertEqual(escape(), .clearSelection)
    }

    func testEscPutsTheArmedViewportAwayFirstAndClearsTheSelectionOnTheNextPress() {
        XCTAssertEqual(escape(viewport: true), .putViewportAway)
        XCTAssertEqual(escape(), .clearSelection)
    }

    /// A Measurement on screen keeps Esc for itself — it abandons typed digits, and never
    /// the Measurement (right-click is the one dismissal, after ADR-0005). It never falls
    /// through to the Selection: an Esc meant for the digits must not lose the Selection.
    func testEscWithAMeasurementOnScreenIsTheMeasurements() {
        XCTAssertEqual(escape(measurement: true), .measurement)
        XCTAssertEqual(escape(measurement: true, viewport: true), .measurement)
    }

    private func escape(add: Bool = false, shape: Bool = false, measurement: Bool = false,
                        viewport: Bool = false) -> ArmedTool.Escape {
        ArmedTool.State(hasArmedAdd: add, hasArmedShape: shape, hasMeasurement: measurement,
                        isViewportArmed: viewport).escape
    }

    /// The key monitor is narrower than the Map's other keys: with only a Selection, or the
    /// Viewport, to back out of, Esc is claimed and every digit still passes through to
    /// whatever else wants it.
    func testEscIsClaimedForTheSelectionWhileDigitsPassThrough() {
        XCTAssertEqual(MeasurementTyping.decide(for: "\u{1B}", isArmed: false,
                                                claimsEscape: true, isInFrame: true,
                                                isEditingText: false),
                       .abandon)
        XCTAssertEqual(MeasurementTyping.decide(for: "9", isArmed: false,
                                                claimsEscape: true, isInFrame: true,
                                                isEditingText: false),
                       .passThrough)
        XCTAssertEqual(MeasurementTyping.decide(for: "\u{1B}", isArmed: false,
                                                claimsEscape: true, isInFrame: true,
                                                isEditingText: true),
                       .passThrough, "Esc in a text field is the field's")
    }
}
