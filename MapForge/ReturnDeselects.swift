import SwiftUI
import AppKit

/// Return finishes a field: the edit is applied and the field lets go of the keyboard,
/// with nothing else taking it.
///
/// AppKit's own answer to Return is to commit and then *stay*, with the text selected —
/// right for a form, wrong at a table, where the DM types a number and goes back to the
/// Map. While a field holds the keyboard the Map's keys are not the Map's: digits meant
/// for a Measurement go into the field instead.
///
/// One monitor for the whole app rather than an `.onSubmit` on every field. There are
/// seventeen fields and the next one would be forgotten; and `.onSubmit` cannot do it for
/// the `TextField(value:format:)` ones without a `@FocusState` apiece.
///
/// The Return itself is passed through untouched, so whatever the field does with it —
/// `.onSubmit`, a formatter's commit, a sheet's default button — happens first, exactly as
/// before. Letting go comes a runloop turn later, and is itself a commit for the fields
/// that treat focus loss as one.
///
/// The fields that write to the log are the exception — the Comment bar and the Turn's
/// note. Return there *sends*, and the DM recording a fight line after line must not click
/// back in between each. They opt out with `.keepsKeyboardOnReturn()`.
enum ReturnDeselects {
    private static var monitor: Any?

    /// Whether this key press ends the edit.
    ///
    /// Only a bare Return or Enter, and only in a field editor: a `TextEditor` is a text
    /// view of its own and Return there is a new line. ⌥Return is how a line break is typed
    /// into a field, so any modifier leaves the press alone. Marked text is an input method
    /// mid-composition, where Return accepts the candidate rather than the field.
    static func endsEdit(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                         isFieldEditor: Bool, hasMarkedText: Bool) -> Bool {
        let isReturn = keyCode == 36 || keyCode == 76
        let held = modifiers.intersection([.shift, .option, .control, .command])
        return isReturn && held.isEmpty && isFieldEditor && !hasMarkedText
    }

    /// Idempotent — the Control Window calls it on every appearance.
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window,
                  let editor = window.firstResponder as? NSTextView,
                  !SendingFieldMarker.marks(editor),
                  endsEdit(keyCode: event.keyCode, modifiers: event.modifierFlags,
                           isFieldEditor: editor.isFieldEditor,
                           hasMarkedText: editor.hasMarkedText()) else { return event }
            DispatchQueue.main.async { [weak window] in
                // Still a field, a turn later: a sheet whose OK this Return pressed has
                // taken its fields with it, and there is nothing left to let go of.
                guard let window,
                      (window.firstResponder as? NSTextView)?.isFieldEditor == true else { return }
                window.makeFirstResponder(nil)
            }
            return event
        }
    }
}

/// Marks a field as one that sends. An invisible view laid exactly behind the field, which
/// is how the monitors tell it apart: nothing on the `NSTextView` they see says which
/// SwiftUI field it is editing for, but the `NSTextField` it edits for has a frame, and
/// so does this. Not a `@FocusState` flag — that is set a SwiftUI update after the click
/// that focused the field, which is after `ClickSelectsAll` has already had to decide.
struct SendingFieldMarker: NSViewRepresentable {
    private static let markers = NSHashTable<NSView>.weakObjects()

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Self.markers.add(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    /// Whether the field this editor is editing for sits on a marker.
    static func marks(_ editor: NSTextView) -> Bool {
        guard let field = editor.delegate as? NSView, let window = field.window else { return false }
        let frame = field.convert(field.bounds, to: nil)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return markers.allObjects.contains {
            $0.window === window && $0.convert($0.bounds, to: nil).contains(center)
        }
    }
}

extension View {
    /// For a field whose Return sends what was typed and waits for the next — see
    /// `ReturnDeselects`. Such a field is also left out of `ClickSelectsAll`: what is in
    /// it is a sentence half written, not a value to replace.
    func keepsKeyboardOnReturn() -> some View {
        background(SendingFieldMarker())
    }
}
