import AppKit

/// Clicking into a field selects what is in it, so the DM types the new value over the old
/// one rather than deleting it first.
///
/// AppKit already does this for a field reached with Tab; a click puts a caret where it
/// landed instead. Nearly every field here holds a short value that is replaced whole — hit
/// points, a bonus, a name — and "click, select all, type" at the table is two steps too
/// many.
///
/// App-wide for the reason `ReturnDeselects` is, and with the same exception: the fields
/// that write to the log hold a sentence in progress, and selecting it is one keystroke
/// from losing it.
enum ClickSelectsAll {
    private static var monitor: Any?

    /// Whether the click that just landed selects the field's text.
    ///
    /// Only the click that *enters* a field. A second click in the same field is the DM
    /// placing the caret, and must be left to. A click that already selected something was
    /// a drag across part of the text, which is a more specific request than this one.
    static func selectsAll(enteredField: Bool, isSendingField: Bool, selectionLength: Int) -> Bool {
        enteredField && !isSendingField && selectionLength == 0
    }

    /// The field an editor is editing for. The editor itself is one shared view per
    /// window, so it cannot say whether the focus moved — its delegate can.
    private static func field(in window: NSWindow) -> AnyObject? {
        guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor.delegate
    }

    /// Idempotent — the Control Window calls it on every appearance.
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window else { return event }
            let before = field(in: window)
            // After the click is *over*, not merely delivered. A field editor handles
            // mouse-down by tracking the mouse until it comes up, and the main queue keeps
            // draining all the while — so a `DispatchQueue.main.async` selected the text
            // mid-click, and the mouse-up that followed put a caret through it: selected,
            // then not, as reported. That loop runs the run loop in its event-tracking
            // mode; a block asked for in the default mode waits for it to finish.
            RunLoop.main.perform(inModes: [.default]) { [weak window] in
                guard let window, let after = field(in: window),
                      let editor = window.firstResponder as? NSTextView,
                      selectsAll(enteredField: after !== before,
                                 isSendingField: SendingFieldMarker.marks(editor),
                                 selectionLength: editor.selectedRange().length) else { return }
                editor.selectAll(nil)
            }
            return event
        }
    }
}
