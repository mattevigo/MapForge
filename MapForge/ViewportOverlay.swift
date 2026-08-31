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

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartOrigin == nil { dragStartOrigin = originInches }
                guard let start = dragStartOrigin else { return }
                onDrag(CGPoint(x: start.x + value.translation.width / previewPointsPerMapInch,
                               y: start.y + value.translation.height / previewPointsPerMapInch))
            }
            .onEnded { _ in dragStartOrigin = nil }
    }
}
