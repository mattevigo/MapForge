import SwiftUI

/// Wall authoring on the Control Window preview: Walls traced as chains, and nothing else.
///
/// Pawns and Light Markers are still drawn — a Wall is traced against the room its tokens
/// stand in, and hiding them would make tracing harder — but they are **inert**: no
/// hit-testing at all, so a click meant for a Wall corner is never eaten by a token
/// standing on it. That is what lets the mode drop its tool picker: with only one thing
/// clickable there is nothing for a click to be ambiguous between. See ADR-0013 for why
/// Pawn and Light authoring left for the Live View.
///
/// Zoom and pan come from `PreviewTransform`, exactly as Grid Fit uses them — precision is
/// the point here, and one Grid square of a 3000 px Map is ~15 pt at fit-to-window.
struct FogOverlay: View {
    let transform: PreviewTransform
    let containerSize: CGSize
    /// Grid square side in image pixels, or nil when no Grid has been declared. Sizes a
    /// Pawn token, which reads as occupying its square — nothing snaps to it.
    let gridPixels: CGFloat?
    @Binding var edits: FogEdits
    /// Whether a Pawn is currently invisible to players. Drawn faded rather than dropped:
    /// this is the DM's surface, and it is while authoring an encounter that they most
    /// need to see which Creatures the table can and cannot see.
    let isDimmed: (Pawn) -> Bool
    let onChange: () -> Void
    let onTransform: (PreviewTransform) -> Void

    private var walls: [Wall] { edits.document.walls }
    private var lights: [Light] { edits.document.lights }
    private var pawns: [Pawn] { edits.document.pawns }

    @State private var chain = WallChain()
    @State private var cursor: CGPoint?
    @State private var selectedWall: Wall.ID?
    @State private var panStart: PreviewTransform?
    @State private var pinchStart: PreviewTransform?
    /// Escapes the angle constraint, which is otherwise held: most Walls on a battle map
    /// are axis-aligned, so free angles are the exception.
    @State private var freeAngle = false
    @FocusState private var focused: Bool

    static let coordinateSpace = "fogOverlay"

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
            lightMarkers
            pawnMarkers
            chainInProgress
            snapIndicator
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .focusable()
        .focused($focused)
        .onKeyPress(.escape) { chain.cancel(); return .handled }
        // `.delete` IS U+007F — backspace on macOS. One registration covers it.
        //
        // Kept, but not relied on. This ZStack's children are all `.position()`-placed, so
        // it carries no focusable region of its own and `.onKeyPress` never fired for a
        // selection made by clicking a Wall — ⌫ just beeped. `onDeleteKey` below is the
        // one that actually works; if focus ever does land here, this consumes the event
        // first and the monitor never sees it.
        .onKeyPress(.delete) { deleteSelected() }
        .onDeleteKey(canHandle: { hasSelection }) { _ = deleteSelected() }
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
                .stroke(wall.id == selectedWall ? Color.accentColor : Color.orange,
                        style: StrokeStyle(lineWidth: wall.id == selectedWall ? 4 : 2.5,
                                           lineCap: .round))
                .contentShape(Path { path in
                    // A 2.5 pt line is far too thin to click. Widen the hit area only.
                    path.move(to: a); path.addLine(to: b)
                }.strokedPath(StrokeStyle(lineWidth: 12)))
                // A child gesture beats an ancestor's, so this would eat the base layer's
                // double-click — and "close the room by finishing on an existing Wall" is
                // exactly the motion that lands there. Hit-testing is therefore off during
                // a chain, and off for the very first click too: selection is what the DM
                // wants between chains, placement is what they want during one.
                .gesture(TapGesture().onEnded { select(wall: wall.id) })
                .allowsHitTesting(!chain.isDrawing)
        }
    }

    /// Every Light, drawn so a DM tracing a room can see the torch in it — and inert, so a
    /// Wall corner placed near one is never stolen by it. Lights are placed, moved and
    /// edited in the Live View (ADR-0013).
    private var lightMarkers: some View {
        ForEach(lights) { light in
            let p = viewPoint(light.at)
            ZStack {
                Circle()
                    .fill(light.isOn ? Color.yellow.opacity(0.9) : Color.gray.opacity(0.6))
                Circle()
                    .stroke(Color.black.opacity(0.5), lineWidth: 1.5)
            }
            .frame(width: 14, height: 14)
            .position(x: p.x, y: p.y)
            .allowsHitTesting(false)
        }
    }

    /// Every Pawn, drawn as the reference a Wall is traced against — and inert, for the
    /// same reason a Light is: a token standing on a corner must not eat the click that
    /// places it. `PawnLayer` handles dragging in the Live View, which is now the only
    /// place a Pawn is touched at all (ADR-0013).
    private var pawnMarkers: some View {
        ForEach(pawns) { pawn in
            let p = viewPoint(pawn.at)
            PawnToken(pawn: pawn, squareSide: pawnDiameter, isSelected: false)
                .opacity(isDimmed(pawn) ? 0.4 : 1)
                .position(x: p.x, y: p.y)
                .allowsHitTesting(false)
        }
    }

    /// A token reads as occupying its Grid square, so it is sized in squares — falling
    /// back to a fixed size when no Grid has been declared.
    private var pawnDiameter: CGFloat {
        guard let grid = gridPixels else { return 18 }
        return max(10, grid * transform.scale)
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

    /// Where a click would land when it will not land under the cursor — the endpoint
    /// weld is the only thing that moves a vertex now, and it stays visible, never silent.
    @ViewBuilder
    private var snapIndicator: some View {
        if let cursor {
            let resolved = resolve(viewPoint: cursor)
            if resolved.target == .endpoint {
                let p = viewPoint(resolved.point)
                Circle()
                    .stroke(Color.green, lineWidth: 2)
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
    /// welded to a nearby endpoint. The weld runs last so it always wins over the
    /// constraint — closing the chain matters more than keeping it at 45°.
    private func resolve(viewPoint: CGPoint) -> WallSnap.Result {
        let raw = MapPoint(transform.imagePoint(from: viewPoint))
        let constrained = (!freeAngle && chain.lastVertex != nil)
            ? WallSnap.constrainAngle(from: chain.lastVertex!, to: raw)
            : raw
        return WallSnap.snap(constrained, to: snapCandidates, tolerance: snapTolerance)
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
        focused = true
        selectedWall = nil
        chain.place(resolve(viewPoint: location).point)
    }

    private func finishChain() {
        let newWalls = chain.finish()
        guard !newWalls.isEmpty else { return }
        edits.addWalls(newWalls)
        onChange()
    }

    // MARK: Selection
    //
    // Every one of these takes keyboard focus back, and that is the whole point of their
    // existing. `.onKeyPress(.delete)` only fires while the overlay is focused, and focus
    // was previously claimed in just two places — `.onAppear` and `place()`. Selecting a
    // Wall did not, so the sequence a DM actually performs — enter the mode, touch the
    // "Grid squares wide" field beside the preview, come back and click a Wall — left
    // focus in that text field. The Wall highlighted and ⌫ went to the text field, so
    // deletion looked implemented and dead. Selecting is an act of "I am working in here";
    // it has to move focus, or the keyboard half of every select-then-key interaction is
    // unreachable.

    private func select(wall id: Wall.ID) {
        focused = true
        selectedWall = id
    }

    /// Whether ⌫ has anything to act on. Gates the event monitor, which is global to the
    /// process — with nothing selected the key must pass through to whatever else wants it.
    private var hasSelection: Bool {
        selectedWall != nil
    }

    private func deleteSelected() -> KeyPress.Result {
        guard let id = selectedWall else { return .ignored }
        edits.deleteWall(id: id)
        selectedWall = nil
        onChange()
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
