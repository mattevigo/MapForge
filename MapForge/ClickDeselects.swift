import AppKit

/// A click anywhere but the field being typed in finishes it: the edit is applied and the
/// field lets go of the keyboard — the click's half of what `ReturnDeselects` does for
/// Return.
///
/// AppKit leaves a field focused through a click on a button or a segmented control,
/// because neither takes the keyboard itself. So a number typed and not yet committed
/// stayed that way while the DM pressed the button beside it, and the Map's keys stayed
/// the field's. It reached the table as the Roll sheet's DC field, which went on showing
/// the old DC after one of the common four was picked beside it.
///
/// It lets go on the mouse-*down*, before the click is delivered, so a field that commits
/// on focus loss has committed before the button's action runs. A DM who types 13 and then
/// picks 10 has chosen 10, and the later write is the one that stands.
///
/// App-wide for the reason `ReturnDeselects` is, and with the same exception: a field that
/// sends keeps the keyboard, so the DM can press its send button and type the next line.
enum ClickDeselects {
    private static var monitor: Any?

    /// Idempotent — the Control Window calls it on every appearance.
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handle(event)
            return event
        }
    }

    /// Lets go of the field being edited in the click's window, unless the click is in it.
    static func handle(_ event: NSEvent) {
        guard let window = event.window,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSView,
              !SendingFieldMarker.marks(editor),
              let frame = window.contentView?.superview else { return }
        // `hitTest` takes a point in the receiver's superview; the frame view's is the
        // window's own space once converted.
        let point = frame.convert(event.locationInWindow, from: nil)
        if let hit = frame.hitTest(point), hit === field || hit.isDescendant(of: field) {
            return
        }
        window.makeFirstResponder(nil)
    }
}
