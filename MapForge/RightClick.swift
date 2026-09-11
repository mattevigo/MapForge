import SwiftUI
import AppKit

/// Secondary-click notification for SwiftUI, which has no gesture for it.
///
/// Reports only *that* a right-click happened in this view's window — deliberately not
/// where. An `NSEvent`'s `locationInWindow` cannot be converted into the coordinate space
/// SwiftUI's `GeometryReader` reports: measured on a plain window, a `GeometryReader`
/// under 80pt of chrome gives its `.global` origin as y=120 with a height 88pt short of
/// the content view, so `.global` is neither the window's space nor the content view's.
/// Flipping an event point against `contentLayoutRect` or converting it through the
/// content view both land hundreds of points out, and both were shipped and reverted here
/// before that was measured.
///
/// Callers that need the location read it from `onContinuousHover`, which reports in the
/// modified view's own space. The cursor cannot right-click somewhere it is not.
///
/// Pairs with `.contextMenu`: this fires first, the menu opens second.
struct RightClickModifier: ViewModifier {
    let onRightClick: () -> Void

    /// The live closure and this view's window, read at event time. The monitor is
    /// installed once and would otherwise capture the first render's state forever — the
    /// bug `ScrollWheelModifier` documents at length.
    private final class Handler {
        var onRightClick: () -> Void = {}
        weak var window: NSWindow?
    }

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        handler.onRightClick = onRightClick
        return content
            .background(WindowReader { handler.window = $0 })
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        let handler = self.handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Only this view's own window. The monitor is global to the process, and the
            // Player window is borderless, fullscreen and perfectly capable of being key.
            guard let window = handler.window, event.window === window else { return event }
            handler.onRightClick()
            // REPORTED, not consumed: the `.contextMenu` on the same view needs this very
            // click to open.
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// Calls `onRightClick` when a secondary click lands in this view's window, before any
    /// `.contextMenu` opens. Carries no location — see `RightClickModifier`.
    func onRightClick(_ onRightClick: @escaping () -> Void) -> some View {
        modifier(RightClickModifier(onRightClick: onRightClick))
    }
}
