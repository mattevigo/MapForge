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

    func testTheMouseCannotOverwriteASettledDistance() {
        // The failure this feature would most likely ship with, because it only shows up
        // between reading a distance and moving the mouse: the next hover tick resizes the
        // shape from the cursor and the number is gone.
        //
        // A Measurement that never settles is the option ADR 0005 rejected under another
        // name — evidence that vanishes the moment the table wants to discuss it — so a
        // dragged Measurement must be committable, not only a typed one.
        let origin = MapPoint(x: 0, y: 0)
        var typed = MapForge.Measurement(origin: .point(origin), shape: .cone,
                                         distance: 6, direction: 0)
        typed.isDistanceTyped = true

        let aimed = typed.aimed(at: MapPoint(x: 0, y: 500), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 6, "a typed distance holds")
        XCTAssertEqual(aimed.direction, .pi / 2, accuracy: 1e-9,
                       "but a typed one still swings, which is the point of typing it")
    }

    func testASettledConeStopsSwinging() {
        // Reported: a Cone kept turning after its second click, so the shape moved out
        // from under the DM as they took their hand off the mouse. Settled now means
        // settled — aim included — for every shape alike. Pointing is the first click's
        // job; the second is for stopping.
        let origin = MapPoint(x: 0, y: 0)
        var settled = MapForge.Measurement(origin: .point(origin), shape: .cone,
                                           distance: 6, direction: 0)
        settled.isDistanceSettled = true

        let aimed = settled.aimed(at: MapPoint(x: 0, y: 500), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.direction, 0, accuracy: 1e-9, "the aim holds too")
        XCTAssertEqual(aimed.distance, 6)
    }

    func testEveryShapeHoldsStillOnceSettled() {
        // The rule is uniform now: no shape follows the cursor after its second click.
        let origin = MapPoint(x: 0, y: 0)
        for shape in MeasurementShape.allCases {
            var settled = MapForge.Measurement(origin: .point(origin), shape: shape,
                                               distance: 6, direction: 0)
            settled.isDistanceSettled = true
            let aimed = settled.aimed(at: MapPoint(x: 300, y: 400), from: origin,
                                      pixelsPerSquare: 10)
            XCTAssertEqual(aimed, settled, "\(shape) should be inert once settled")
        }
    }

    func testASettledMeasurementSurvivesRepeatedMouseMovement() {
        // The DM reads "9 m", then moves the mouse to point at the shape. The number must
        // still say 9 m when they get there.
        let origin = MapPoint(x: 0, y: 0)
        var settled = MapForge.Measurement(origin: .point(origin), shape: .circle,
                                           distance: 6, direction: 0)
        settled.isDistanceSettled = true

        var current = settled
        for x in stride(from: CGFloat(10), through: 500, by: 10) {
            current = current.aimed(at: MapPoint(x: x, y: x), from: origin, pixelsPerSquare: 10)
        }
        XCTAssertEqual(current.distance, 6)
    }

    func testADraggedDistanceDoesFollowTheMouse() {
        let origin = MapPoint(x: 0, y: 0)
        let dragged = MapForge.Measurement(origin: .point(origin), shape: .cone,
                                           distance: 6, direction: 0)
        let aimed = dragged.aimed(at: MapPoint(x: 500, y: 0), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 50, "50 squares to the cursor")
    }

    func testAnAimedRadiusShapeSnapsButATypedOneDoesNot() {
        let origin = MapPoint(x: 0, y: 0)
        let dragged = MapForge.Measurement(origin: .point(origin), shape: .circle,
                                           distance: 0, direction: 0)
        // 43 pixels at 10 to the square is 4.3 squares, which must land on 4.
        let aimed = dragged.aimed(at: MapPoint(x: 43, y: 0), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 4)
    }

    func testALineDoesNotSnap() {
        // A Line is a chain of points the DM placed deliberately, and rounding each vertex
        // would compound the error along a long path. Deliberately unlike the radius
        // shapes, which round to whole squares.
        let origin = MapPoint(x: 0, y: 0)
        let dragged = MapForge.Measurement(origin: .point(origin), shape: .line,
                                           distance: 0, direction: 0)
        let aimed = dragged.aimed(at: MapPoint(x: 43, y: 0), from: origin, pixelsPerSquare: 10)
        XCTAssertEqual(aimed.distance, 4.3, accuracy: 1e-9)
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
