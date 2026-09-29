import XCTest
import SwiftUI
import AppKit
@testable import MapForge

/// `NumberField` hosted in a real window, focused as a DM's click focuses it.
final class NumberFieldFocusTests: XCTestCase {

    /// Stands in for the Roll sheet: a draft value the field shows and something else
    /// (the segmented Picker) can change.
    final class Box: ObservableObject {
        @Published var value: Int? = 15 { didSet { writes.append(value) } }
        var writes: [Int?] = []
    }

    struct Harness: View {
        @ObservedObject var box: Box
        var body: some View {
            HStack {
                NumberField(value: box.value, identifier: "dc", width: 60) { box.value = $0 }
                // Where the segmented control sits in the Roll sheet.
                Color.gray.frame(width: 60, height: 20)
            }
            .padding(20)
        }
    }

    private var window: NSWindow!

    private func host(_ box: Box) -> NSTextField {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Harness(box: box))
        window.makeKeyAndOrderFront(nil)
        spin()
        let field = textFields(in: window.contentView!).first!
        return field
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(textFields(in:))
    }

    /// Typed as keystrokes are, through the field editor, so SwiftUI hears each change.
    private func type(_ text: String, into field: NSTextField) {
        let editor = field.currentEditor()!
        editor.selectAll(nil)
        editor.insertText(text)
        spin()
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    /// The user's symptom: the DC field was clicked into, then a common DC chosen from the
    /// segmented control beside it. The field must show the chosen DC.
    func testAValueChosenElsewhereShowsWhileTheFieldHasFocus() {
        let box = Box()
        let field = host(box)
        XCTAssertEqual(field.stringValue, "15")

        window.makeFirstResponder(field)
        spin()

        box.value = 10
        spin()

        XCTAssertEqual(field.stringValue, "10")
    }

    /// Return commits, and the field then shows what it committed.
    func testReturnCommitsAndShowsTheCommittedValue() {
        let box = Box()
        let field = host(box)
        window.makeFirstResponder(field)
        spin()

        type("13", into: field)
        field.currentEditor()!.insertNewline(nil)
        spin()

        XCTAssertEqual(box.value, 13)
        XCTAssertEqual(field.stringValue, "13")
    }

    /// A mouse-down at a point in the field's window, as the monitor receives it.
    private func mouseDown(at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                           timestamp: 0, windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func center(of view: NSView) -> CGPoint {
        let frame = view.convert(view.bounds, to: nil)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The request behind the fix: a click on a button lets go of the field. A number typed
    /// and not yet committed is committed by that, before the button's own action runs —
    /// so picking 10 after typing 13 ends at 10.
    func testAClickElsewhereCommitsTheFieldAndLetsGo() {
        let box = Box()
        let field = host(box)
        window.makeFirstResponder(field)
        spin()
        type("13", into: field)

        let beside = CGPoint(x: center(of: field).x + 70, y: center(of: field).y)
        ClickDeselects.handle(mouseDown(at: beside))
        spin()
        box.value = 10
        spin()

        XCTAssertFalse(window.firstResponder is NSTextView, "the field should have let go")
        XCTAssertEqual(box.writes, [13, 10])
        XCTAssertEqual(field.stringValue, "10")
    }

    /// A click inside the field is the DM placing the caret, not leaving.
    func testAClickInsideTheFieldKeepsIt() {
        let box = Box()
        let field = host(box)
        window.makeFirstResponder(field)
        spin()
        type("13", into: field)

        ClickDeselects.handle(mouseDown(at: center(of: field)))
        spin()

        XCTAssertTrue(field.currentEditor() != nil, "the field should still be edited")
        XCTAssertEqual(box.writes, [])
    }
}
