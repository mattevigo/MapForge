import SwiftUI

/// Viewport mode overlay on the Control Window preview: a rectangle sized to
/// exactly what the Player Display shows at True Scale, draggable to pan it.
/// Never resizable — resizing would zoom and break True Scale.
/// Unlike GridFitOverlay's binding, this reports desired origins via a callback:
/// clamping is policy that lives with the owner, so the overlay never holds a
/// value the Map bounds would reject.
struct ViewportOverlay: View {
    let fittedRect: CGRect
    let map: MapScale
    let viewportSizeInches: CGSize
    /// Clamped current origin (map inches).
    let originInches: CGPoint
    /// Reports the desired new origin (map inches, unclamped) while dragging.
    let onDrag: (CGPoint) -> Void

    @State private var dragStartOrigin: CGPoint?

    /// A stable space for the drag, anchored to the preview rather than the moving rectangle.
    static let coordinateSpace = "viewportOverlay"

    private var previewPointsPerMapInch: CGFloat { fittedRect.width / map.physicalWidthInches }

    var body: some View {
        let scale = previewPointsPerMapInch
        let rect = CGRect(x: fittedRect.minX + originInches.x * scale,
                          y: fittedRect.minY + originInches.y * scale,
                          width: viewportSizeInches.width * scale,
                          height: viewportSizeInches.height * scale)

        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay(Rectangle().stroke(Color.white, lineWidth: 2).shadow(radius: 1))
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .position(x: rect.midX, y: rect.midY)
    }

    /// The drag is measured in the container's coordinate space, never the default —
    /// which is the *rectangle's own*, and the rectangle moves as you drag it. Each
    /// point of movement was subtracted from the next event's `translation`, so the
    /// reported translation oscillated (18.75 → 4.92 → 18.96 → 10.17 …) instead of
    /// growing, and the Viewport visibly jumped back and drifted off the cursor.
    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if dragStartOrigin == nil { dragStartOrigin = originInches }
                guard let start = dragStartOrigin else { return }
                onDrag(CGPoint(x: start.x + value.translation.width / previewPointsPerMapInch,
                               y: start.y + value.translation.height / previewPointsPerMapInch))
            }
            .onEnded { _ in dragStartOrigin = nil }
    }
}
