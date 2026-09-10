import AppKit
import SwiftUI

/// Digit reporting for the Map, so a DM can type an exact distance instead of hunting for
/// the pixel that happens to be 9 m away.
///
/// A process-global `NSEvent` monitor, like `DeleteKeyModifier` and `ScrollWheelModifier`,
/// because SwiftUI focus does not reach a `.position()`-based ZStack. That mechanism has a
/// bad record here — `DeleteKey` exists in its current shape because a monitor once ate ⌫
/// from a text field and deleted a Wall mid-word — so every keystroke is put to
/// `MeasurementTyping.decide`, which is pure and tested, and anything not positively
/// claimed is handed straight back to AppKit.
///
/// Scoped by frame like `ScrollWheelModifier` rather than by window like `DeleteKey`: the
/// Control Window is full of digit-friendly fields, and only the Map should claim digits.
struct MeasurementKeysModifier: ViewModifier {
    /// Whether a Measurement is armed. The narrowest of the three gates, and the reason
    /// this monitor is tolerable at all: it is live only in a state the DM entered
    /// deliberately, and torn down with the Measurement.
    let isArmed: Bool
    let onDecision: (MeasurementTyping.Decision) -> Void

    private final class Handler {
        var isArmed = false
        var onDecision: (MeasurementTyping.Decision) -> Void = { _ in }
        var frame: CGRect = .zero
        weak var window: NSWindow?
    }

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        // Every render, before any event can arrive — the stale-capture bug both sibling
        // modifiers document at length.
        handler.isArmed = isArmed
        handler.onDecision = onDecision
        return content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { handler.frame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, new in handler.frame = new }
                }
            )
            .background(MeasurementWindowReader { handler.window = $0 })
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        let handler = self.handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let key = event.charactersIgnoringModifiers?.first else { return event }
            // A modified key is somebody's shortcut, never a distance.
            guard !event.modifierFlags.intersects([.command, .control, .option]) else {
                return event
            }
            guard let window = handler.window, event.window === window else { return event }

            // Gate two: the cursor is over the Map. The monitor is global to the process
            // and the window is full of other controls.
            let inWindow = window.mouseLocationOutsideOfEventStream
            let flipped = CGPoint(x: inWindow.x, y: window.contentLayoutRect.height - inWindow.y)

            // Gate three: nothing is taking text input. Tested through `NSTextInputClient`
            // and the field editor rather than `NSText`/`NSTextView`, because a SwiftUI
            // `TextField` is neither — the distinction `DeleteKey` records.
            let responder = window.firstResponder
            let isEditingText = responder is NSTextInputClient
                || (responder != nil && responder === window.fieldEditor(false, for: nil))

            let decision = MeasurementTyping.decide(for: key, isArmed: handler.isArmed,
                                                    isInFrame: handler.frame.contains(flipped),
                                                    isEditingText: isEditingText)
            guard decision != .passThrough else { return event }
            handler.onDecision(decision)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Reports the `NSWindow` hosting a SwiftUI view, so the monitor can tell this window's
/// keystrokes from the Player window's — which is borderless, fullscreen and perfectly
/// capable of being key.
private struct MeasurementWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

private extension NSEvent.ModifierFlags {
    func intersects(_ other: NSEvent.ModifierFlags) -> Bool { !intersection(other).isEmpty }
}

extension View {
    /// Reports digits, ⌫, Return and Esc to a Measurement being typed. Claims nothing
    /// unless a Measurement is armed, the cursor is over this view, and no text field has
    /// focus — see `MeasurementTyping.decide`.
    func onMeasurementKeys(isArmed: Bool,
                           perform onDecision: @escaping (MeasurementTyping.Decision) -> Void)
    -> some View {
        modifier(MeasurementKeysModifier(isArmed: isArmed, onDecision: onDecision))
    }
}
