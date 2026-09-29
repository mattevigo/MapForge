import SwiftUI
import AppKit

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
    /// Whether the DM has armed the rectangle to be moved.
    ///
    /// It is drawn either way — the DM always needs to know what their players are being
    /// shown. Idle it is a **readout**: outlined rather than filled, and hit-testing off so
    /// the clicks that drag a Pawn or open the right-click menu pass through to the Map
    /// beneath. Armed it becomes a **control**, filled to say so.
    ///
    /// Without that split the rectangle could not be permanent: one sitting over the middle
    /// of the Map would swallow every gesture aimed at the Pawns under it, which is why this
    /// used to be confined to a mode of its own.
    let isDraggable: Bool
    /// Reports the desired new origin (map inches, unclamped) while dragging.
    let onDrag: (CGPoint) -> Void

    @State private var dragStartOrigin: CGPoint?
    /// Set for the length of a drag that began with ⌥ held: that drag is the Magnifier's,
    /// and stays the Magnifier's if ⌥ is let go halfway — see
    /// `ViewportToggle.dragMovesViewport`.
    @State private var dragBelongsToMagnifier = false

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
            // Idle it is unfilled: the rectangle sits over the Map for the whole session, and
            // a permanent tint over the part the players can see would be a permanent lie
            // about the artwork's colours — the one thing a DM reads the Map for. A fill
            // appears only while it is armed, to say the rectangle has become a control.
            //
            // Green in both states, and a brighter green while armed. White was the original
            // and is the wrong choice over a battle map: the artwork is greys and browns with
            // white highlights, so a white rectangle reads as part of it. Green reads as an
            // instrument, and matches the Wall Editor's snap indicator.
            .fill(isDraggable ? Color.green.opacity(0.12) : Color.clear)
            .overlay(Rectangle()
                .stroke(isDraggable ? Color.green : Color.green.opacity(0.65),
                        lineWidth: isDraggable ? 2 : 1.5)
                .shadow(radius: 1))
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            // The whole reason the rectangle can be permanent. Off, every click goes to the
            // Map underneath — the Pawn drags, the right-click menu, the armed placements.
            .allowsHitTesting(isDraggable)
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
                if dragStartOrigin == nil, !dragBelongsToMagnifier {
                    let isOptionHeld = NSEvent.modifierFlags.contains(.option)
                    guard ViewportToggle.dragMovesViewport(isOptionHeld: isOptionHeld) else {
                        dragBelongsToMagnifier = true
                        return
                    }
                    dragStartOrigin = originInches
                }
                guard let start = dragStartOrigin else { return }
                onDrag(CGPoint(x: start.x + value.translation.width / previewPointsPerMapInch,
                               y: start.y + value.translation.height / previewPointsPerMapInch))
            }
            .onEnded { _ in
                dragStartOrigin = nil
                dragBelongsToMagnifier = false
            }
    }
}
