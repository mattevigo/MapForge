import SwiftUI
import AppKit

/// Scroll-wheel reporting for SwiftUI, which has no native modifier for it.
///
/// Uses a local event monitor rather than an `NSViewRepresentable`: a representable
/// placed in Grid Fit's `.position()`-based ZStack never gets a non-zero frame, so it
/// never reaches a window and never receives events at all.
///
/// Reports the vertical delta together with the cursor's location in the modified
/// view's own coordinates — Grid Fit's zoom is cursor-anchored, so the location is as
/// much the point as the delta. Events outside the view are passed through untouched.
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat, CGPoint) -> Void

    /// The live handler, read by the monitor at event time.
    ///
    /// Load-bearing indirection. The monitor is installed once in `onAppear` and its
    /// closure captures whatever `onScroll` was at that moment — and callers build
    /// `onScroll` around the transform of the render that created it. So the monitor kept
    /// zooming from the *first* transform forever: every scroll recomputed the scale from
    /// fit-to-window instead of from the current zoom, which read as "no zoom limit, then
    /// it resets" because a large scroll delta clamped at 1:1 and the next small one
    /// dropped straight back near the floor. A reference the body refreshes each render
    /// keeps the monitor pointed at the current closure.
    /// `frame` lives here for the same reason: the monitor's closure would otherwise
    /// capture the zero rect it had at install time and reject every event as outside
    /// the view.
    private final class Handler {
        var onScroll: (CGFloat, CGPoint) -> Void = { _, _ in }
        var frame: CGRect = .zero
    }

    @State private var handler = Handler()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        // Every render, before any event can arrive.
        handler.onScroll = onScroll
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let window = event.window else { return event }
            // The monitor is global to the process, so only claim scrolls that land
            // inside this view; everything else must pass through.
            let inWindow = event.locationInWindow
            let flipped = CGPoint(x: inWindow.x, y: window.contentLayoutRect.height - inWindow.y)
            guard handler.frame.contains(flipped) else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
            handler.onScroll(delta, CGPoint(x: flipped.x - handler.frame.minX,
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
    func onScrollWheel(_ onScroll: @escaping (CGFloat, CGPoint) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: onScroll))
    }
}
