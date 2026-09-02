import AppKit
import SwiftUI

/// ⌫ reporting for a view that owns a selection, independent of SwiftUI focus.
///
/// `.focusable()` + `.focused()` + `.onKeyPress(.delete)` is the idiomatic way to do this
/// and it did not work here. `FogOverlay` is a `ZStack` whose children are all placed with
/// `.position()`, so the stack has no hit-testable region of its own to carry focus — the
/// same shape that stopped an `NSViewRepresentable` ever getting a non-zero frame in Grid
/// Fit (see `ScrollWheelModifier`). The symptom was precise: selecting a Wall highlighted
/// it, ⌫ produced the system beep — AppKit finding no responder to consume the key — and
/// the Wall stayed. Deletion looked implemented and dead.
///
/// So this uses a local event monitor, exactly as scroll-wheel handling does, and for the
/// same reason: it is the mechanism that demonstrably reaches this layer. The trade-off is
/// that a monitor is process-global, so the handler must decline any key it should not
/// claim — see `canHandle`.
struct DeleteKeyModifier: ViewModifier {
    /// Whether there is anything to delete right now. Returning false lets the event pass
    /// through untouched, so ⌫ in a text field still edits text rather than being eaten by
    /// a fog overlay somewhere behind it.
    let canHandle: () -> Bool
    let onDelete: () -> Void

    /// The live closures and this view's window, read at event time. The monitor is
    /// installed once and would otherwise capture the first render's state forever — the
    /// bug `ScrollWheelModifier` documents at length.
    private final class Handler {
        var canHandle: () -> Bool = { false }
        var onDelete: () -> Void = {}
        /// The window this overlay is in. The monitor is global to the process, so an
        /// event from any other window — the Player window is borderless, fullscreen and
        /// perfectly capable of being key — must pass through, or a stray ⌫ there deletes
        /// the DM's geometry with players watching.
        weak var window: NSWindow?
    }

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        handler.canHandle = canHandle
        handler.onDelete = onDelete
        return content
            .background(WindowReader { handler.window = $0 })
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        let handler = self.handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // U+007F is macOS backspace — the key labelled ⌫ — and U+F728 is the forward
            // delete on a full-size keyboard. Both read as "delete this".
            let isDelete = event.charactersIgnoringModifiers.map {
                $0 == "\u{7F}" || $0 == "\u{F728}"
            } ?? false
            guard isDelete else { return event }
            // Only this overlay's own window. Scoped the way `ScrollWheelModifier` scopes
            // by frame, and for the identical reason.
            guard let window = handler.window, event.window === window else { return event }
            // Never steal ⌫ from text being edited: if the first responder takes text
            // input, the key belongs to it. The DM types into "Grid squares wide" and,
            // since this feature, a Pawn's label in the live row — both on screen while a
            // fog selection exists.
            //
            // Tested through `NSTextInputClient` and the window's field editor rather than
            // `NSText`/`NSTextView`: a SwiftUI `TextField` is neither, so those two classes
            // alone would let a Wall be deleted mid-word.
            if let responder = window.firstResponder,
               responder is NSTextInputClient || responder === window.fieldEditor(false, for: nil) {
                return event
            }
            guard handler.canHandle() else { return event }
            handler.onDelete()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Reports the `NSWindow` hosting a SwiftUI view, so an event monitor can tell this
/// window's keystrokes from every other window's.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window is nil until the view joins the hierarchy, so read it a runloop turn
        // later rather than in makeNSView.
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

extension View {
    /// Calls `onDelete` when ⌫ is pressed in this view's window and `canHandle` says there
    /// is a selection to act on. Independent of SwiftUI focus — see `DeleteKeyModifier`.
    func onDeleteKey(canHandle: @escaping () -> Bool,
                     perform onDelete: @escaping () -> Void) -> some View {
        modifier(DeleteKeyModifier(canHandle: canHandle, onDelete: onDelete))
    }
}
