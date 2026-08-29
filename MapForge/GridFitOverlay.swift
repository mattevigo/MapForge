import SwiftUI

/// The square being aligned to one artwork grid square, in image-pixel coordinates
/// so a preview resize cannot silently change the derived scale.
struct GridFitSquare: Equatable {
    var center: CGPoint
    var side: CGFloat
}

/// Interactive Grid Fit overlay on the Control Window preview: drag to draw a square
/// over one grid square, then adjust via corner handles or arrow keys (⇧ resizes).
struct GridFitOverlay: View {
    let fittedRect: CGRect
    let imagePixelSize: CGSize
    @Binding var square: GridFitSquare?

    @State private var dragStart: GridFitSquare?
    @FocusState private var focused: Bool

    private let minSideImagePixels: CGFloat = 2
    private var viewScale: CGFloat { fittedRect.width / imagePixelSize.width }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(drawGesture)

            if let s = square {
                let r = viewRect(of: s)

                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: r.width, height: r.height)
                    .contentShape(Rectangle())
                    .gesture(moveGesture)
                    .position(x: r.midX, y: r.midY)

                ForEach(0..<corners.count, id: \.self) { i in
                    let (dx, dy) = corners[i]
                    ZStack {
                        Circle().fill(Color.white)
                        Circle().stroke(Color.accentColor, lineWidth: 1.5)
                    }
                    .frame(width: 9, height: 9)
                    .padding(4)
                    .contentShape(Rectangle())
                    .gesture(handleGesture(dx: dx, dy: dy))
                    .position(x: r.midX + dx * r.width / 2, y: r.midY + dy * r.height / 2)
                }

                if let squaresWide = GridFit.squaresWide(imageWidth: imagePixelSize.width,
                                                        squareSide: s.side) {
                    Text("≈ \(squaresWide, specifier: "%.1f") squares wide")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .position(x: r.midX, y: max(r.minY - 16, 12))
                        .allowsHitTesting(false)
                }
            }
        }
        .coordinateSpace(name: "gridFit")
        .focusable()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], action: nudge)
        .onAppear { focused = true }
    }

    private let corners: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]

    private func viewRect(of s: GridFitSquare) -> CGRect {
        let side = s.side * viewScale
        return CGRect(x: fittedRect.minX + (s.center.x - s.side / 2) * viewScale,
                      y: fittedRect.minY + (s.center.y - s.side / 2) * viewScale,
                      width: side,
                      height: side)
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - fittedRect.minX) / viewScale,
                y: (viewPoint.y - fittedRect.minY) / viewScale)
    }

    /// A fresh drag on empty preview (re)draws the square from its start corner.
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("gridFit"))
            .onChanged { value in
                let start = imagePoint(from: value.startLocation)
                let current = imagePoint(from: value.location)
                square = squareBetween(anchor: start, dragged: current)
            }
            .onEnded { _ in
                if let s = square, s.side < minSideImagePixels { square = nil }
                focused = true
            }
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil { dragStart = square }
                guard let origin = dragStart else { return }
                square?.center = CGPoint(x: origin.center.x + value.translation.width / viewScale,
                                         y: origin.center.y + value.translation.height / viewScale)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Resize by dragging corner (dx, dy); the opposite corner stays anchored.
    private func handleGesture(dx: CGFloat, dy: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .named("gridFit"))
            .onChanged { value in
                if dragStart == nil { dragStart = square }
                guard let origin = dragStart else { return }
                let anchor = CGPoint(x: origin.center.x - dx * origin.side / 2,
                                     y: origin.center.y - dy * origin.side / 2)
                square = squareBetween(anchor: anchor, dragged: imagePoint(from: value.location))
            }
            .onEnded { _ in dragStart = nil }
    }

    /// The aspect-constrained square with one corner at `anchor`, extended toward `dragged`.
    private func squareBetween(anchor: CGPoint, dragged: CGPoint) -> GridFitSquare {
        let side = max(abs(dragged.x - anchor.x), abs(dragged.y - anchor.y))
        let signX: CGFloat = dragged.x >= anchor.x ? 1 : -1
        let signY: CGFloat = dragged.y >= anchor.y ? 1 : -1
        return GridFitSquare(center: CGPoint(x: anchor.x + signX * side / 2,
                                             y: anchor.y + signY * side / 2),
                             side: max(side, minSideImagePixels))
    }

    /// Arrow keys move by 1 preview point; ⇧+up/right grows, ⇧+down/left shrinks.
    private func nudge(_ press: KeyPress) -> KeyPress.Result {
        guard square != nil else { return .ignored }
        let step = 1 / viewScale
        if press.modifiers.contains(.shift) {
            let grows = press.key == .upArrow || press.key == .rightArrow
            square?.side = max(minSideImagePixels, (square?.side ?? 0) + (grows ? step : -step))
        } else {
            switch press.key {
            case .leftArrow: square?.center.x -= step
            case .rightArrow: square?.center.x += step
            case .upArrow: square?.center.y -= step
            case .downArrow: square?.center.y += step
            default: return .ignored
            }
        }
        return .handled
    }
}
