import SwiftUI

/// Which fog concept a click places.
///
/// One mode for all of them rather than a mode each: the DM needs to see a torch against
/// the room they traced to know the room works, and the Control Window's top row should
/// not grow a button per fog concept.
enum FogTool: CaseIterable, Hashable {
    case walls, lights, pawns

    var label: String {
        switch self {
        case .walls: "Walls"
        case .lights: "Lights"
        case .pawns: "Pawns"
        }
    }

    var hint: String {
        switch self {
        case .walls:
            "Click to place Wall corners, double-click to end a chain, Esc to cancel it. ⇧ frees the angle; corners weld to nearby Wall ends. Click a Wall then ⌫ to delete. Scroll to zoom, ⌥-drag to pan."
        case .lights:
            "Click to place a Light exactly where you click, drag one to move it. Click a Light then ⌫ to delete; radii are set below. Scroll to zoom, ⌥-drag to pan."
        case .pawns:
            "Click to place a Pawn, drag one to move it — dragging works outside this mode too. Click a Pawn then ⌫ to delete; label, colour and range are set below."
        }
    }
}

/// Fog authoring on the Control Window preview: Walls traced as chains, Lights placed and
/// dragged. All fog is drawn whatever the tool — the tool decides only what a click does.
///
/// Zoom and pan come from `PreviewTransform`, exactly as Grid Fit uses them — precision is
/// the point here, and one Grid square of a 3000 px Map is ~15 pt at fit-to-window.
struct FogOverlay: View {
    let transform: PreviewTransform
    let containerSize: CGSize
    let tool: FogTool
    /// Grid square side in image pixels, or nil when no Grid has been declared. Sizes a
    /// Pawn token, which reads as occupying its square — nothing snaps to it.
    let gridPixels: CGFloat?
    @Binding var edits: FogEdits
    /// Bound out to the Control Window, which shows the selected Light's radii beside the
    /// preview — there is no room for a numeric editor inside the overlay itself.
    @Binding var selectedLight: Light.ID?
    @Binding var selectedPawn: Pawn.ID?
    let onChange: () -> Void
    let onTransform: (PreviewTransform) -> Void

    private var walls: [Wall] { edits.document.walls }
    private var lights: [Light] { edits.document.lights }
    private var pawns: [Pawn] { edits.document.pawns }

    @State private var chain = WallChain()
    @State private var cursor: CGPoint?
    @State private var selectedWall: Wall.ID?
    @State private var lightDragStart: MapPoint?
    @State private var pawnDragStart: MapPoint?
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
                .gesture(TapGesture().onEnded { selectedWall = wall.id; selectedLight = nil })
                .allowsHitTesting(tool == .walls && !chain.isDrawing)
        }
    }

    /// Every Light, whatever the tool — a DM tracing a room needs to see the torch in it.
    /// Draggable only with the Light tool, so a Wall click near one is not stolen.
    private var lightMarkers: some View {
        ForEach(lights) { light in
            let p = viewPoint(light.at)
            ZStack {
                Circle()
                    .fill(light.isOn ? Color.yellow.opacity(0.9) : Color.gray.opacity(0.6))
                Circle()
                    .stroke(light.id == selectedLight ? Color.accentColor : Color.black.opacity(0.5),
                            lineWidth: light.id == selectedLight ? 3 : 1.5)
            }
            .frame(width: 14, height: 14)
            .position(x: p.x, y: p.y)
            .gesture(lightDragGesture(light))
            .allowsHitTesting(tool == .lights)
        }
    }

    /// Drag to reposition. `beginLightDrag`/`endLightDrag` bracket it so the whole drag is
    /// one undo step rather than one per frame.
    private func lightDragGesture(_ light: Light) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if lightDragStart == nil {
                    lightDragStart = light.at
                    selectedLight = light.id
                    selectedWall = nil
                    edits.beginLightDrag()
                }
                guard let start = lightDragStart else { return }
                // minimumDistance is 0 so a plain click selects, which means .onChanged
                // fires on mouse-down with zero translation. This guard originally stopped
                // a select-click silently snapping an unsnapped Light onto the Grid; grid
                // snapping is gone, so that bug cannot recur, but the guard still earns its
                // place — without it selecting a Light writes a no-op move into the undo
                // stack, and the DM presses undo on a click that changed nothing.
                guard value.translation != .zero else { return }
                let moved = MapPoint(x: start.x + value.translation.width / transform.scale,
                                     y: start.y + value.translation.height / transform.scale)
                edits.moveLight(id: light.id, to: moved)
                onChange()
            }
            .onEnded { _ in
                lightDragStart = nil
                edits.endLightDrag()
                onChange()
            }
    }

    /// Every Pawn, whatever the tool — a Pawn is a token first and a Light second, so it
    /// is drawn even with the Fog Overlay off. Draggable only with the Pawn tool here;
    /// `PawnLayer` handles dragging outside the mode, where the party actually moves.
    private var pawnMarkers: some View {
        ForEach(pawns) { pawn in
            let p = viewPoint(pawn.at)
            PawnToken(pawn: pawn, diameter: pawnDiameter,
                      isSelected: pawn.id == selectedPawn)
                .position(x: p.x, y: p.y)
                .gesture(pawnDragGesture(pawn))
                .allowsHitTesting(tool == .pawns)
        }
    }

    /// A token reads as occupying its Grid square, so it is sized in squares — falling
    /// back to a fixed size when no Grid has been declared.
    private var pawnDiameter: CGFloat {
        guard let grid = gridPixels else { return 18 }
        return max(10, grid * transform.scale)
    }

    private func pawnDragGesture(_ pawn: Pawn) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if pawnDragStart == nil {
                    pawnDragStart = pawn.at
                    selectedPawn = pawn.id
                    selectedLight = nil
                    selectedWall = nil
                    edits.beginPawnDrag()
                }
                guard let start = pawnDragStart, value.translation != .zero else { return }
                edits.movePawn(id: pawn.id,
                               to: MapPoint(x: start.x + value.translation.width / transform.scale,
                                            y: start.y + value.translation.height / transform.scale))
                onChange()
            }
            .onEnded { _ in
                pawnDragStart = nil
                edits.endPawnDrag()
                onChange()
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

    /// Where a click would land when it will not land under the cursor — the endpoint
    /// weld is the only thing that moves a vertex now, and it stays visible, never silent.
    @ViewBuilder
    private var snapIndicator: some View {
        if let cursor, tool == .walls {
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
                guard tool == .walls else { return }
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
        switch tool {
        case .walls:
            selectedWall = nil
            chain.place(resolve(viewPoint: location).point)
        case .pawns:
            selectedPawn = nil
            // Free-form. Pawns never snapped; Walls and Lights no longer do either.
            let point = MapPoint(transform.imagePoint(from: location))
            let previous = pawns.last
            edits.addPawn(Pawn(at: point,
                               label: Pawn.nextLabel(after: pawns),
                               colorHex: previous?.colorHex ?? Pawn.defaultColorHex,
                               brightSquares: previous?.light.brightSquares ?? 6))
            onChange()
        case .lights:
            selectedLight = nil
            // Placed exactly where clicked. A new Light takes the radii of the last one
            // placed: a DM lighting a dungeon is usually placing the same torch over and
            // over.
            let point = MapPoint(transform.imagePoint(from: location))
            let previous = lights.last
            edits.addLight(Light(at: point,
                                 brightSquares: previous?.brightSquares ?? 4,
                                 dimSquares: previous?.dimSquares))
            onChange()
        }
    }

    private func finishChain() {
        let newWalls = chain.finish()
        guard !newWalls.isEmpty else { return }
        edits.addWalls(newWalls)
        onChange()
    }

    private func deleteSelected() -> KeyPress.Result {
        if let id = selectedWall {
            edits.deleteWall(id: id)
            selectedWall = nil
            onChange()
            return .handled
        }
        if let id = selectedLight {
            edits.deleteLight(id: id)
            selectedLight = nil
            onChange()
            return .handled
        }
        if let id = selectedPawn {
            edits.deletePawn(id: id)
            selectedPawn = nil
            onChange()
            return .handled
        }
        return .ignored
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
