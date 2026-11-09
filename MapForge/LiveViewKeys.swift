import AppKit
import SwiftUI

/// The Live View's keys: digits, ⌫ and Return for a Measurement being typed, so a DM can
/// type an exact distance instead of hunting for the pixel that happens to be 9 m away —
/// and Esc, which backs out of whatever the Live View has on: digits typed, an armed tool,
/// the Viewport, the Selection (`ArmedTool.State.escape` says which).
///
/// Named for the Live View rather than for the Measurement it began with, because Esc
/// reaches further than a Measurement. Which key is claimed is still
/// `MeasurementTyping.decide`'s alone; what a claimed key does is the caller's.
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
struct LiveViewKeysModifier: ViewModifier {
    /// Whether a Measurement is armed. The narrowest of the three gates, and the reason
    /// this monitor is tolerable at all: it is live only in a state the DM entered
    /// deliberately, and torn down with the Measurement.
    let isArmed: Bool
    /// Whether Esc alone is claimed with no Measurement armed — there is a Selection or the
    /// Viewport to back out of. Every other key still passes through.
    var claimsEscape = false
    /// Whether the cursor is over the Map. Passed in from `onContinuousHover` rather than
    /// computed here: an `NSEvent` location cannot be converted into the space a
    /// `GeometryReader` reports — see `RightClickModifier` for the measurements.
    let isOverMap: Bool
    let onDecision: (MeasurementTyping.Decision) -> Void

    private final class Handler {
        var isArmed = false
        var claimsEscape = false
        var isOverMap = false
        var onDecision: (MeasurementTyping.Decision) -> Void = { _ in }
        weak var window: NSWindow?
    }

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        // Every render, before any event can arrive — the stale-capture bug both sibling
        // modifiers document at length.
        handler.isArmed = isArmed
        handler.claimsEscape = claimsEscape
        handler.isOverMap = isOverMap
        handler.onDecision = onDecision
        return content
            .background(WindowReader { handler.window = $0 })
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

            // Whether something is taking text input. Tested through `NSTextInputClient`
            // and the field editor rather than `NSText`/`NSTextView`, because a SwiftUI
            // `TextField` is neither — the distinction `DeleteKey` records, and the reason
            // it records it is that a Wall got deleted mid-word.
            let responder = window.firstResponder
            let isEditingText = responder is NSTextInputClient
                || (responder != nil && responder === window.fieldEditor(false, for: nil))

            let decision = MeasurementTyping.decide(for: key, isArmed: handler.isArmed,
                                                    claimsEscape: handler.claimsEscape,
                                                    isInFrame: handler.isOverMap,
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

private extension NSEvent.ModifierFlags {
    func intersects(_ other: NSEvent.ModifierFlags) -> Bool { !intersection(other).isEmpty }
}

extension View {
    /// Reports the Live View's keys — digits, ⌫, Return and Esc. Claims nothing unless a
    /// Measurement is armed — or, for Esc alone, `claimsEscape` — the cursor is over this
    /// view, and no text field has focus — see `MeasurementTyping.decide`.
    func onLiveViewKeys(isArmed: Bool, claimsEscape: Bool = false, isOverMap: Bool,
                        perform onDecision: @escaping (MeasurementTyping.Decision) -> Void)
    -> some View {
        modifier(LiveViewKeysModifier(isArmed: isArmed, claimsEscape: claimsEscape,
                                      isOverMap: isOverMap, onDecision: onDecision))
    }
}
