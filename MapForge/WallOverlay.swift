import SwiftUI

/// Wall drawing on the Control Window preview: click to place vertices, double-click or
/// Esc to end the chain, click a Wall to select it for deletion.
///
/// Zoom and pan come from `PreviewTransform`, exactly as Grid Fit uses them — precision is
/// the point here, and one Grid square of a 3000 px Map is ~15 pt at fit-to-window.
struct WallOverlay: View {
    let transform: PreviewTransform
    let containerSize: CGSize
    let walls: [Wall]
    /// Grid square side in image pixels, or nil when no Grid has been declared.
    let gridPixels: CGFloat?
    let onCommit: ([Wall]) -> Void
    let onDelete: (Wall) -> Void
    let onTransform: (PreviewTransform) -> Void

    @State private var chain = WallChain()
    @State private var cursor: CGPoint?
    @State private var selected: Wall.ID?
    @State private var panStart: PreviewTransform?
    @State private var pinchStart: PreviewTransform?
    /// Escapes the angle constraint, which is otherwise held: most Walls on a battle map
    /// are axis-aligned, so free angles are the exception.
    @State private var freeAngle = false
    @FocusState private var focused: Bool

    static let coordinateSpace = "wallOverlay"

    /// Snap radius in preview points, converted to image pixels per zoom level — so it
    /// stays "a few points" under the cursor however far the DM has zoomed in.
    private let snapRadiusPoints: CGFloat = 12
    private let zoomSensitivity: CGFloat = 0.01

    private var snapTolerance: CGFloat {
        transform.scale > 0 ? snapRadiusPoints / transform.scale : snapRadiusPoints
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                // One .gesture() call, with the ⌥-filtered pan given first refusal:
                // two chained calls do not compose, as GridFitOverlay found the hard way.
                .gesture(panGesture)
                .onTapGesture(count: 2) { finishChain() }
                .onTapGesture { location in place(at: location) }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): cursor = location
                    case .ended: cursor = nil
                    }
                }

            wallShapes
            chainInProgress
            snapIndicator
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .focusable()
        .focused($focused)
        .onKeyPress(.escape) { chain.cancel(); return .handled }
        .onKeyPress(.delete) { deleteSelected() }
        .onKeyPress(keys: [.init("\u{7F}")]) { _ in deleteSelected() }
        .onModifierKeysChanged { _, new in freeAngle = new.contains(.shift) }
        .onAppear { focused = true }
        .onScrollWheel { delta, location in zoom(by: delta, at: location) }
        .gesture(magnifyGesture)
    }

    // MARK: Drawing

    private var wallShapes: some View {
        ForEach(walls) { wall in
            let a = viewPoint(wall.from), b = viewPoint(wall.to)
            Path { $0.move(to: a); $0.addLine(to: b) }
                .stroke(wall.id == selected ? Color.accentColor : Color.orange,
                        style: StrokeStyle(lineWidth: wall.id == selected ? 4 : 2.5, lineCap: .round))
                .contentShape(Path { path in
                    // A 2.5 pt line is far too thin to click. Widen the hit area only.
                    path.move(to: a); path.addLine(to: b)
                }.strokedPath(StrokeStyle(lineWidth: 12)))
                .onTapGesture { selected = wall.id }
        }
    }

    /// The chain placed so far, plus a rubber band to the cursor.
    @ViewBuilder
    private var chainInProgress: some View {
        if chain.isDrawing {
            Path { path in
                let points = chain.vertices.map(viewPoint)
                path.addLines(points)
                if let last = points.last, let target = rubberBandTarget {
                    path.move(to: last)
                    path.addLine(to: viewPoint(target))
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            .allowsHitTesting(false)

            ForEach(chain.vertices.indices, id: \.self) { i in
                let p = viewPoint(chain.vertices[i])
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .position(x: p.x, y: p.y)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Where a click would land, shown before it happens — snapping is visible, never silent.
    @ViewBuilder
    private var snapIndicator: some View {
        if let cursor, let resolved = resolve(viewPoint: cursor), resolved.target != .none {
            let p = viewPoint(resolved.point)
            Circle()
                .stroke(resolved.target == .endpoint ? Color.green : Color.secondary, lineWidth: 2)
                .frame(width: 12, height: 12)
                .position(x: p.x, y: p.y)
                .allowsHitTesting(false)
        }
    }

    // MARK: Geometry

    private func viewPoint(_ point: MapPoint) -> CGPoint {
        transform.viewPoint(from: point.cgPoint)
    }

    /// Where a click at `viewPoint` lands: angle-constrained against the chain, then
    /// snapped. Snapping runs last so a snap target always wins over the constraint —
    /// closing the chain matters more than keeping it at 45°.
    private func resolve(viewPoint: CGPoint) -> WallSnap.Result? {
        let raw = MapPoint(transform.imagePoint(from: viewPoint))
        let constrained = (!freeAngle && chain.lastVertex != nil)
            ? WallSnap.constrainAngle(from: chain.lastVertex!, to: raw)
            : raw
        return WallSnap.snap(constrained, to: walls + chainWalls,
                             gridPixels: gridPixels, tolerance: snapTolerance)
    }

    /// The chain's own vertices are snap targets too — that is how a DM closes a room
    /// back onto its first corner.
    private var chainWalls: [Wall] {
        chain.vertices.map { Wall(from: $0, to: $0) }
    }

    private var rubberBandTarget: MapPoint? {
        cursor.flatMap { resolve(viewPoint: $0)?.point }
    }

    // MARK: Actions

    private func place(at location: CGPoint) {
        selected = nil
        guard let resolved = resolve(viewPoint: location) else { return }
        chain.place(resolved.point)
        focused = true
    }

    private func finishChain() {
        let walls = chain.finish()
        guard !walls.isEmpty else { return }
        onCommit(walls)
    }

    private func deleteSelected() -> KeyPress.Result {
        guard let id = selected, let wall = walls.first(where: { $0.id == id }) else { return .ignored }
        onDelete(wall)
        selected = nil
        return .handled
    }

    // MARK: Zoom and pan

    /// ⌥-drag pans. `.modifiers(.option)` also stops a plain drag matching it, so clicks
    /// to place vertices stay unfiltered.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpace))
            .modifiers(.option)
            .onChanged { value in
                if panStart == nil { panStart = transform }
                guard let start = panStart else { return }
                onTransform(start.panned(by: value.translation, container: containerSize))
            }
            .onEnded { _ in panStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? {
                    pinchStart = transform
                    return transform
                }()
                onTransform(start.zoomed(to: start.scale * value.magnification,
                                         anchoringViewPoint: value.startLocation,
                                         container: containerSize))
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func zoom(by delta: CGFloat, at location: CGPoint) {
        guard delta != 0 else { return }
        onTransform(transform.zoomed(to: transform.scale * exp(delta * zoomSensitivity),
                                     anchoringViewPoint: location, container: containerSize))
    }
}
