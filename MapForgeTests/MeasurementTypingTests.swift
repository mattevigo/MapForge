import XCTest
@testable import MapForge

/// Typing a distance, and — more importantly — the three gates that stop the key monitor
/// eating keystrokes that belong to somebody else.
///
/// The gates are the regression tests that matter more than the feature. `DeleteKey`
/// exists in its current shape because a global monitor once ate ⌫ from a text field and
/// deleted a Wall mid-word; digits collide with far more than ⌫ does, since "Grid squares
/// wide" and every Pawn label are digit-friendly fields in the same window.
final class MeasurementTypingTests: XCTestCase {
    // MARK: The gates

    func testAKeyIsIgnoredWhileNoMeasurementIsArmed() {
        // The narrowest gate, and the reason this monitor is tolerable at all: it is live
        // only in a state the DM entered deliberately.
        XCTAssertEqual(MeasurementTyping.decide(for: "5", isArmed: false,
                                                isInFrame: true, isEditingText: false),
                       .passThrough)
    }

    func testAKeyIsIgnoredOutsideTheMapFrame() {
        XCTAssertEqual(MeasurementTyping.decide(for: "5", isArmed: true,
                                                isInFrame: false, isEditingText: false),
                       .passThrough)
    }

    func testAKeyIsIgnoredWhileTextIsBeingEdited() {
        // The gate DeleteKey learned the hard way. A DM typing "24" into Grid squares wide
        // must not also be sizing a cone.
        XCTAssertEqual(MeasurementTyping.decide(for: "5", isArmed: true,
                                                isInFrame: true, isEditingText: true),
                       .passThrough)
    }

    func testANonDigitIsPassedThrough() {
        // Command shortcuts, arrow keys and everything else keep working while armed.
        for key: Character in ["a", "z", " ", "-", "."] {
            XCTAssertEqual(MeasurementTyping.decide(for: key, isArmed: true,
                                                    isInFrame: true, isEditingText: false),
                           .passThrough, "\(key) should not be claimed")
        }
    }

    func testADigitIsClaimedWhenAllThreeGatesOpen() {
        XCTAssertEqual(MeasurementTyping.decide(for: "5", isArmed: true,
                                                isInFrame: true, isEditingText: false),
                       .digit("5"))
    }

    func testReturnCommitsAndEscapeAbandons() {
        XCTAssertEqual(MeasurementTyping.decide(for: "\r", isArmed: true,
                                                isInFrame: true, isEditingText: false),
                       .commit)
        XCTAssertEqual(MeasurementTyping.decide(for: "\u{1B}", isArmed: true,
                                                isInFrame: true, isEditingText: false),
                       .abandon)
    }

    func testBackspaceEditsTheBufferRatherThanDeletingGeometry() {
        // The direct collision with DeleteKey: while a Measurement is armed and the buffer
        // has content, ⌫ belongs to the buffer.
        XCTAssertEqual(MeasurementTyping.decide(for: "\u{7F}", isArmed: true,
                                                isInFrame: true, isEditingText: false),
                       .backspace)
    }

    // MARK: The buffer

    func testTypingAccumulatesDigits() {
        var buffer = MeasurementTyping.Buffer()
        buffer.append("1")
        buffer.append("2")
        XCTAssertEqual(buffer.text, "12")
        XCTAssertEqual(buffer.value, 12)
    }

    func testBackspaceRemovesTheLastDigit() {
        var buffer = MeasurementTyping.Buffer()
        buffer.append("1")
        buffer.append("2")
        buffer.backspace()
        XCTAssertEqual(buffer.text, "1")
    }

    func testAnEmptyBufferHasNoValue() {
        XCTAssertNil(MeasurementTyping.Buffer().value)
    }

    func testABufferRefusesToGrowWithoutBound() {
        // A stuck key must not build a distance with more digits than any Map has squares.
        var buffer = MeasurementTyping.Buffer()
        for _ in 0..<20 { buffer.append("9") }
        XCTAssertLessThanOrEqual(buffer.text.count, MeasurementTyping.Buffer.maxDigits)
    }

    // MARK: Committing

    func testACommittedDistanceIsNotSnapped() {
        // Dragged distances snap to whole squares; a typed one does not. You typed it, you
        // meant it — and 10 m is not a whole number of 1.5 m squares.
        var buffer = MeasurementTyping.Buffer()
        buffer.append("1")
        buffer.append("0")
        let squares = buffer.squares(in: .metres)
        XCTAssertEqual(squares!, 10 / 1.5, accuracy: 1e-9)
        XCTAssertNotEqual(squares!, Measurement.snap(squares: squares!))
    }

    func testTheMouseCannotOverwriteATypedDistance() {
        // The failure this feature would most likely ship with, because it only shows up
        // between typing a distance and looking at it: the next hover tick resizes the
        // shape from the cursor and the exact number is gone.
        let origin = MapPoint(x: 0, y: 0)
        var typed = MapForge.Measurement(origin: .point(origin), shape: .cone,
                                         distance: 6, direction: 0)
        typed.isDistanceTyped = true

        let aimed = typed.aimed(at: MapPoint(x: 500, y: 0), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 6, "a typed distance holds")
        XCTAssertEqual(aimed.direction, 0, accuracy: 1e-9, "but the aim still follows")
    }

    func testADraggedDistanceDoesFollowTheMouse() {
        let origin = MapPoint(x: 0, y: 0)
        let dragged = MapForge.Measurement(origin: .point(origin), shape: .cone,
                                           distance: 6, direction: 0)
        let aimed = dragged.aimed(at: MapPoint(x: 500, y: 0), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 50, "50 squares to the cursor")
    }

    func testAnAimedDistanceSnapsButATypedOneDoesNot() {
        let origin = MapPoint(x: 0, y: 0)
        let dragged = MapForge.Measurement(origin: .point(origin), shape: .line,
                                           distance: 0, direction: 0)
        // 43 pixels at 10 to the square is 4.3 squares, which must land on 4.
        let aimed = dragged.aimed(at: MapPoint(x: 43, y: 0), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 4)
    }

    func testACommittedDistanceReadsBackAsTyped() {
        // The round-trip a DM actually checks: type 9, read "9 m".
        var buffer = MeasurementTyping.Buffer()
        buffer.append("9")
        let measurement = MapForge.Measurement(origin: .point(MapPoint(x: 0, y: 0)),
                                               shape: .cone,
                                               distance: buffer.squares(in: .metres)!,
                                               direction: 0)
        XCTAssertEqual(measurement.readout(in: .metres), "9 m")
    }
}
