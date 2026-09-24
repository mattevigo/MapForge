import SwiftUI
import AppKit

/// Middle-button drag reporting for SwiftUI, whose `DragGesture` only ever sees the
/// primary button.
///
/// The press has to land over the modified view, and the caller says whether it does:
/// `isOverView` comes from `onContinuousHover`, because an `NSEvent`'s location cannot be
/// converted into a SwiftUI space — see `RightClickModifier`. The *difference* between two
/// event locations needs no conversion, only a flipped y, so the translation is read from
/// the events themselves.
///
/// While the button is held the cursor is the closed hand, and the drag is followed
/// wherever it goes — leaving the view does not end it, releasing does.
struct MiddleMouseDragModifier: ViewModifier {
    let isOverView: Bool
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    /// Read by the monitor at event time. The monitor is installed once and would
    /// otherwise capture the first render's state forever — the bug `ScrollWheelModifier`
    /// documents at length.
    private final class Handler {
        var isOverView = false
        var onChanged: (CGSize) -> Void = { _ in }
        var onEnded: () -> Void = {}
        weak var window: NSWindow?
        /// Where the button went down, in window coordinates. Non-nil for the length of
        /// the drag, which is also what says the closed hand is on the cursor stack.
        var pressed: CGPoint?
    }

    /// The wheel button. Buttons 3 and up are the thumb buttons, which are not this.
    private static let middleButton = 2

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        handler.isOverView = isOverView
        handler.onChanged = onChanged
        handler.onEnded = onEnded
        return content
            .background(WindowReader { handler.window = $0 })
            .onAppear { start() }
            .onDisappear { stop() }
    }

    /// Cumulative, as `DragGesture` reports it, in SwiftUI's y-down sense.
    static func translation(from pressed: CGPoint, to current: CGPoint) -> CGSize {
        CGSize(width: current.x - pressed.x, height: pressed.y - current.y)
    }

    private func start() {
        guard monitor == nil else { return }
        let handler = self.handler
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            guard event.buttonNumber == Self.middleButton else { return event }
            switch event.type {
            case .otherMouseDown:
                // Only this view's own window — the monitor is global to the process.
                guard handler.pressed == nil, handler.isOverView,
                      let window = handler.window, event.window === window else { return event }
                handler.pressed = event.locationInWindow
                NSCursor.closedHand.push()
                return nil
            case .otherMouseDragged:
                guard let pressed = handler.pressed else { return event }
                // Re-asserted every move: the views the cursor crosses have cursor rects
                // of their own and would take it back mid-drag.
                NSCursor.closedHand.set()
                handler.onChanged(Self.translation(from: pressed, to: event.locationInWindow))
                return nil
            case .otherMouseUp:
                guard handler.pressed != nil else { return event }
                Self.release(handler)
                return nil
            default:
                return event
            }
        }
    }

    private func stop() {
        // Torn down mid-drag — a Map closed by shortcut with the button still held. The
        // up event will find no monitor, so the hand has to come off the stack here.
        if handler.pressed != nil { Self.release(handler) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func release(_ handler: Handler) {
        handler.pressed = nil
        NSCursor.pop()
        handler.onEnded()
    }
}

extension View {
    /// Reports a drag made with the middle mouse button that began while `isOverView`,
    /// as a cumulative translation. The cursor is the closed hand until release.
    func onMiddleMouseDrag(isOverView: Bool,
                           onChanged: @escaping (CGSize) -> Void,
                           onEnded: @escaping () -> Void = {}) -> some View {
        modifier(MiddleMouseDragModifier(isOverView: isOverView,
                                         onChanged: onChanged, onEnded: onEnded))
    }
}
