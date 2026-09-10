import SwiftUI
import AppKit

/// Secondary-click reporting for SwiftUI, which has no gesture for it.
///
/// Built the way `ScrollWheelModifier` is, and for the same reasons: a local event monitor
/// rather than an `NSViewRepresentable`, because a representable in a `.position()`-based
/// ZStack never gets a non-zero frame and so never receives events; and a `Handler`
/// reference the body refreshes each render, because a monitor installed once in
/// `onAppear` otherwise captures the closure — and the frame — it had at install time.
///
/// A `.contextMenu` would be the obvious alternative and is deliberately not used: this
/// render layer has produced four defects from gesture composition, and right-click here
/// means "start a Measurement", not "offer a menu".
struct RightClickModifier: ViewModifier {
    /// The click, in the modified view's own coordinates.
    let onRightClick: (CGPoint) -> Void

    private final class Handler {
        var onRightClick: (CGPoint) -> Void = { _ in }
        var frame: CGRect = .zero
    }

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        handler.onRightClick = onRightClick
        return content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { handler.frame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, new in handler.frame = new }
                }
            )
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        let handler = self.handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window else { return event }
            // The monitor is global to the process, so only claim clicks landing inside
            // this view; everything else must pass through untouched.
            let inWindow = event.locationInWindow
            let flipped = CGPoint(x: inWindow.x, y: window.contentLayoutRect.height - inWindow.y)
            guard handler.frame.contains(flipped) else { return event }
            handler.onRightClick(CGPoint(x: flipped.x - handler.frame.minX,
                                         y: flipped.y - handler.frame.minY))
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    func onRightClick(_ onRightClick: @escaping (CGPoint) -> Void) -> some View {
        modifier(RightClickModifier(onRightClick: onRightClick))
    }
}
