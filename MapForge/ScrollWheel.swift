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

    @State private var monitor: Any?
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, new in frame = new }
                }
            )
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let window = event.window else { return event }
            // The monitor is global to the process, so only claim scrolls that land
            // inside this view; everything else must pass through.
            let inWindow = event.locationInWindow
            let flipped = CGPoint(x: inWindow.x, y: window.contentLayoutRect.height - inWindow.y)
            guard frame.contains(flipped) else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
            onScroll(delta, CGPoint(x: flipped.x - frame.minX, y: flipped.y - frame.minY))
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
