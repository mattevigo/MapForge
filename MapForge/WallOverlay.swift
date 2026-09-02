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
                // ONE .gesture() call. `.onTapGesture` is itself a gesture modifier, so
                // chaining them does not compose — the outermost simply wins, and the
                // single tap would claim every click while the double-click never fired.
                // GridFitOverlay paid for this lesson with its ⌥-drag; the remedy is the
                // same, an explicit `exclusively` chain that states the priority.
                // SpatialTapGesture, not TapGesture, because placing a vertex needs the
                // location and `.onTapGesture(count: 2)` supplies none.
                .gesture(
                    panGesture
                        .exclusively(before: doubleTapGesture)
                        .exclusively(before: singleTapGesture)
                )
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
        // `.delete` IS U+007F — backspace on macOS. One registration covers it.
        .onKeyPress(.delete) { deleteSelected() }
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
                // Only selectable between chains: mid-trace, a click near an existing Wall
                // means "place a vertex here", which is exactly where a DM joins onto one.
                .onTapGesture { if !chain.isDrawing { selected = wall.id } }
                .allowsHitTesting(!chain.isDrawing)
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
        if let cursor {
            let resolved = resolve(viewPoint: cursor)
            if resolved.target != .none {
                let p = viewPoint(resolved.point)
                Circle()
                    .stroke(resolved.target == .endpoint ? Color.green : Color.secondary,
                            lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .position(x: p.x, y: p.y)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Ends the chain. First refusal over the single tap, so a double-click commits
    /// rather than placing a third vertex on top of the second.
    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .named(Self.coordinateSpace))
            .onEnded { value in
                // The second click still places its vertex before committing — a DM who
                // double-clicks the last corner means to include it.
                place(at: value.location)
                finishChain()
            }
    }

    private var singleTapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpace))
            .onEnded { value in place(at: value.location) }
    }

    // MARK: Geometry

    private func viewPoint(_ point: MapPoint) -> CGPoint {
        transform.viewPoint(from: point.cgPoint)
    }

    /// Where a click at `viewPoint` lands: angle-constrained against the chain, then
    /// snapped. Snapping runs last so a snap target always wins over the constraint —
    /// closing the chain matters more than keeping it at 45°.
    private func resolve(viewPoint: CGPoint) -> WallSnap.Result {
        let raw = MapPoint(transform.imagePoint(from: viewPoint))
        let constrained = (!freeAngle && chain.lastVertex != nil)
            ? WallSnap.constrainAngle(from: chain.lastVertex!, to: raw)
            : raw
        return WallSnap.snap(constrained, to: snapCandidates,
                             gridPixels: gridPixels, tolerance: snapTolerance)
    }

    /// Existing Wall endpoints, plus the chain's *first* vertex — that is how a DM closes
    /// a room back onto where they started. Deliberately not every vertex of the chain:
    /// each one a magnet would silently swallow vertices when tracing a narrow corridor,
    /// where the tolerance in image pixels can exceed the corridor's own width.
    private var snapCandidates: [MapPoint] {
        WallSnap.endpoints(of: walls) + (chain.vertices.first.map { [$0] } ?? [])
    }

    private var rubberBandTarget: MapPoint? {
        cursor.map { resolve(viewPoint: $0).point }
    }

    // MARK: Actions

    private func place(at location: CGPoint) {
        selected = nil
        chain.place(resolve(viewPoint: location).point)
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
