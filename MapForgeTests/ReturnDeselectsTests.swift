import XCTest
import AppKit
@testable import MapForge

/// Which key presses make a field let go of the keyboard. The monitor sees every key
/// press in the app, so what it leaves alone matters as much as what it claims.
final class ReturnDeselectsTests: XCTestCase {

    private func endsEdit(keyCode: UInt16 = 36, modifiers: NSEvent.ModifierFlags = [],
                          isFieldEditor: Bool = true, hasMarkedText: Bool = false) -> Bool {
        ReturnDeselects.endsEdit(keyCode: keyCode, modifiers: modifiers,
                                 isFieldEditor: isFieldEditor, hasMarkedText: hasMarkedText)
    }

    func testReturnAndTheKeypadEnterBothEndTheEdit() {
        XCTAssertTrue(endsEdit(keyCode: 36))
        // The keypad's Enter arrives flagged as a keypad key, which is not a modifier.
        XCTAssertTrue(endsEdit(keyCode: 76, modifiers: [.numericPad]))
    }

    func testOtherKeysAreLeftAlone() {
        XCTAssertFalse(endsEdit(keyCode: 48), "Tab moves to the next field")
        XCTAssertFalse(endsEdit(keyCode: 53), "Esc is the modes' own")
    }

    func testAModifiedReturnIsNotTheEndOfTheEdit() {
        XCTAssertFalse(endsEdit(modifiers: [.option]), "⌥Return types a line break")
        XCTAssertFalse(endsEdit(modifiers: [.command]))
        XCTAssertFalse(endsEdit(modifiers: [.shift]))
    }

    func testReturnInATextEditorIsANewLine() {
        XCTAssertFalse(endsEdit(isFieldEditor: false))
    }

    func testReturnMidCompositionBelongsToTheInputMethod() {
        XCTAssertFalse(endsEdit(hasMarkedText: true))
    }
}
