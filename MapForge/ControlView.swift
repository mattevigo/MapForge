import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var appState: AppState

    private enum PreviewMode { case normal, gridFit, viewport, fog }

    @State private var mode: PreviewMode = .normal
    @State private var fitSquare: GridFitSquare?
    @State private var squaresWideBeforeFit: Double = 0
    /// Whether the Grid was already declared when Grid Fit started. Entering Grid Fit
    /// declares one as a side effect of moving the value, so cancelling has to put back
    /// the claim as well as the number.
    @State private var hadDeclaredGridBeforeFit = false
    @State private var viewportOriginBeforePan: CGPoint?
    /// Grid Fit's preview zoom/pan. Mode-local view state, not part of the Map — it is
    /// reset to fit-to-window on entering the mode.
    @State private var gridFitTransform: PreviewTransform?
    /// The fog mode's preview zoom/pan. Mode-local like Grid Fit's, and reset to
    /// fit-to-window on entering the mode.
    @State private var fogTransform: PreviewTransform?
    /// The fog as it was on entering the mode, so Cancel restores it wholesale — the
    /// same revert Grid Fit does with `squaresWideBeforeFit`. `FogEdits` also carries the
    /// undo history, which is mode-local and cannot unwind past this.
    @State private var fogEdits = FogEdits(document: FogDocument())
    /// Which fog concept a click places. One mode for all of them: the DM needs to see a
    /// torch against the room they traced to know the room works.
    @State private var tool: FogTool = .walls
    /// The Light whose radii the inspector edits. Owned here, not in the overlay, because
    /// the numeric editor lives beside the preview.
    @State private var selectedLight: Light.ID?
    /// The Pawn whose label, colour and range the inspector edits.
    @State private var selectedPawn: Pawn.ID?
    /// Which shape the last Measurement took, so the right-click menu opens on it.
    /// Session-local, like the Measurement itself.
    @State private var measurementShape: MeasurementShape = .circle
    /// The shape picked from the right-click menu, waiting for a left-click to say where
    /// it starts. Nil except between those two moments.
    ///
    /// The menu chooses *what* to measure; the click that follows chooses *where*. Taking
    /// the Origin from the right-click itself conflated the two, so the DM had to open the
    /// menu at exactly the point they meant to measure from — a menu is not a precise
    /// instrument.
    @State private var armedShape: MeasurementShape?
    /// Where the cursor last was on the mirror, in the mirror's own coordinates.
    ///
    /// SwiftUI reports this; an `NSEvent`'s `locationInWindow` is NOT convertible into it.
    /// `.global` is neither the window's nor the content view's space — measured on a
    /// plain window, a `GeometryReader` under 80pt of chrome reports its origin at y=120
    /// and its height 88pt short, so converting an AppKit point through the content view
    /// lands hundreds of points out. Right-click therefore reads the *hovered* point
    /// rather than the event's, which is the only figure in the right space.
    @State private var mirrorCursor: CGPoint?
    /// Digits typed towards an exact distance. Empty except between the first digit and
    /// Return, which is also the only window in which the key monitor claims anything.
    @State private var typedDistance = MeasurementTyping.Buffer()

    var body: some View {
        // `alignment: .top` on the row below, plus the preview claiming the remaining
        // height, keeps this stack's controls pinned to the top of the window whether or
        // not a Map is open.
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Open Map…") { appState.openMap() }
                if let url = appState.mapURL {
                    Text(url.lastPathComponent).foregroundStyle(.secondary)
                }
            }

            // Two rows, always. A single row with a `Spacer()` between the two halves ran
            // the mode buttons off the right edge — and they are the only way into every
            // mode the app has, so losing the last of them with no scrollbar and nothing to
            // say it was there is not a cosmetic problem.
            //
            // `ViewThatFits` cannot rescue that arrangement either: a `Spacer()` makes the
            // wide branch claim to fit at any width, so it is always chosen and always
            // clipped. Splitting them unconditionally is what actually keeps every button
            // on screen.
            HStack {
                gridSquaresField
                Spacer()
            }
            HStack(spacing: 8) {
                modeControls
                Spacer()
            }

            // Shown for the whole mode, not just before the first drag: the caption
            // vanishing mid-drag resized the preview under the cursor.
            if mode == .gridFit {
                Text("Drag a square over one grid square; scroll to zoom, ⌥-drag to pan, arrow keys nudge (⇧ resizes).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mode == .viewport {
                Text("Drag the rectangle to choose what the Player Display shows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mode == .fog {
                Text(tool.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The inspector row is ALWAYS here, empty or not.
                //
                // Both inspectors draw nothing until something is selected, so selecting a
                // Pawn used to insert a row into this VStack, steal its height from the
                // preview below, and shrink the GeometryReader the preview measures every
                // transform against — `fitted(container:)` then recomputed to a different
                // scale and the Map visibly jumped mid-click. That is the "the zoom changes
                // while I select" report, and it is the same defect as the caption above:
                // anything in this stack that appears or vanishes resizes the preview.
                //
                // Reserving the height unconditionally makes the container a constant
                // across selection, which is the property the preview's arithmetic needs.
                ZStack(alignment: .leading) {
                    lightInspector
                    pawnInspector
                }
                .frame(height: Self.fogInspectorRowHeight, alignment: .leading)
            }

            playerDisplayStatus

            fogLoadWarning

            undeclaredGridWarning

            fogSwitch

            HStack(alignment: .top, spacing: 12) {
                preview
                livePanel
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
        // The Control Window IS the app: its close button kept being hit during mode
        // work (it reads like "exit this mode"), killing the session — every "crash"
        // reported against Grid Fit/panning was this. Minimize stays; quit is ⌘Q.
        .onAppear {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("control") == true }) {
                window.styleMask.remove(.closable)
            }
        }
        .onChange(of: appState.playerScreen) { _, screen in
            // Losing the Player Display mid-pan would strand the mode with no overlay.
            if mode == .viewport, screen == nil { mode = .normal }
        }
        .onChange(of: appState.mapURL) { _, _ in
            // Every mode is authored against the Map that was open when it started, and
            // this @State survives the Map changing underneath it. Fog was the damaging
            // one: `fogEdits` still held the outgoing Map's document, so the next edit or
            // Cancel wrote it over the incoming Map's fog file. `AppState` refuses that
            // document now; closing the modes here is what the DM actually sees, instead
            // of a mode whose buttons have quietly stopped doing anything.
            //
            // `fogEdits` is deliberately NOT reset here. It is only ever read with the
            // mode open, and the only way back in is `startFogEditing`, which re-seeds it
            // from the incoming Map's `appState.fog` — after that Map's own fog has been
            // loaded. Seeding an empty document here would just assert, one line above the
            // code that overwrites it, that a Map's editing state starts empty.
            appState.endFogEditing()
            fitSquare = nil
            gridFitTransform = nil
            fogTransform = nil
            selectedLight = nil
            selectedPawn = nil
            // `AppState` drops the Measurement itself; the armed tool is view state, and a
            // crosshair left hunting on a Map the DM has closed is the same staleness.
            armedShape = nil
            typedDistance.clear()
            mode = .normal
        }
        .onChange(of: fitSquare) { _, square in
            guard let square, let image = appState.mapImage,
                  let squaresWide = GridFit.squaresWide(imageWidth: image.pixelSize.width,
                                                        squareSide: square.side) else { return }
            appState.squaresWide = Double(squaresWide)
        }
    }

    /// The Map's width in Grid squares — the one number that pins its physical size.
    @ViewBuilder
    private var gridSquaresField: some View {
        Text("Grid squares wide:")
        TextField("squares", value: $appState.squaresWide, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
        Stepper("squares", value: $appState.squaresWide, in: 1...500)
            .labelsHidden()
    }

    // MARK: Preview

    /// The Viewport resolved against the connected Player Display, or nil without one.
    private var resolvedViewport: Viewport? {
        guard let metrics = appState.playerMetrics,
              let screen = appState.playerScreen,
              let map = appState.mapScale else { return nil }
        return ScaleMath.resolvedViewport(map: map, display: metrics,
                                          screenSizePoints: screen.frame.size,
                                          desiredOrigin: appState.viewportOrigin)
    }

    private var mapOverflowsViewport: Bool {
        guard let viewport = resolvedViewport, let map = appState.mapScale else { return false }
        return map.physicalSizeInches.width > viewport.sizeInches.width
            || map.physicalSizeInches.height > viewport.sizeInches.height
    }

    @ViewBuilder
    private var preview: some View {
        if let image = appState.mapImage {
            GeometryReader { geo in
                if mode == .normal, let map = appState.mapScale, let viewport = resolvedViewport {
                    // Mirror: exactly the portion the Player Display shows, black
                    // letterbox and all — never adjacent map the players can't see.
                    let viewportPx = ViewportMath.viewportRectInImagePixels(originInches: viewport.originInches,
                                                                            sizeInches: viewport.sizeInches,
                                                                            map: map)
                    let frame = ViewportMath.mirrorImageFrame(imagePixelSize: image.pixelSize,
                                                              viewportRect: viewportPx,
                                                              container: geo.size)
                    let visible = ViewportMath.mirrorViewportRect(viewportRect: viewportPx,
                                                                  container: geo.size)
                    // The image frame rebased into the clipped container's coordinates.
                    // Every overlay on this mirror needs exactly this rect, and each one
                    // spelling it out again is how one of them ends up subtly offset from
                    // the Pawn it is drawn against.
                    let mirrorFrame = CGRect(x: frame.minX - visible.minX,
                                             y: frame.minY - visible.minY,
                                             width: frame.width, height: frame.height)
                    ZStack {
                        Color.black
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX - visible.minX, y: frame.midY - visible.minY)
                            // .clipped() below masks drawing only: this Image still owns
                            // its full, overflowing frame for hit-testing and would
                            // swallow clicks on the controls above. Disabled HERE rather
                            // than on the container, which would also disable the Pawn
                            // dragging overlaid on it — that is the live table action and
                            // the whole reason PawnLayer exists.
                            .allowsHitTesting(false)
                    }
                    .frame(width: visible.width, height: visible.height)
                    .overlay {
                        // The DM's view of the same Visibility: a tint they can read
                        // through, over a Map that stays fully lit. Weaker than the
                        // players' darkness by design — a DM as blind as the players
                        // cannot run the game.
                        FogCanvas(regions: appState.litRegions,
                                  map: map,
                                  frame: mirrorFrame) {
                            FogShading.control($0, isOverlayOn: appState.isFogOverlayOn)
                        }
                    }
                    .overlay {
                        // Dragging a Pawn is a LIVE action — the party moves during play,
                        // not during prep — so it works on the normal mirror, outside the
                        // fog editing mode entirely.
                        PawnLayer(map: map,
                                  frame: mirrorFrame,
                                  pawns: appState.fog.pawns,
                                  lights: appState.fog.lights,
                                  // Hoisted, not read per Pawn: `litRegions` is computed,
                                  // and rebuilding the cache key for every token every
                                  // frame of a drag is exactly the drag-rate work this
                                  // file's comments record a regression over.
                                  isDimmed: { [regions = appState.litRegions] pawn in
                                      isInvisibleToPlayers(pawn, regions: regions)
                                  },
                                  isLightDimmed: { [regions = appState.litRegions] light in
                                      PlayerVisibility.isLightMarkerDimmedForDM(
                                          light: light, regions: regions,
                                          isFogOverlayOn: appState.isFogOverlayOn,
                                          hasVisibility: appState.hasDeclaredGrid)
                                  },
                                  onMove: { appState.movePawn(id: $0, to: $1) },
                                  onCommit: { appState.flushPendingFogWrites() })
                    }
                    .overlay {
                        // Above the tokens: a Measurement is what the DM is pointing at,
                        // and a cone half-hidden behind the party is unreadable.
                        if let measurement = appState.resolvedMeasurement,
                           let origin = appState.measurementOriginPoint,
                           let pixelsPerSquare = appState.pixelsPerSquare {
                            MeasurementLayer(measurement: measurement, origin: origin,
                                             map: map, frame: mirrorFrame,
                                             pixelsPerSquare: pixelsPerSquare)
                        }
                    }
                    .overlay {
                        // An armed tool has nothing on the Map yet, so without this the
                        // DM cannot tell it apart from an idle one — and the click that
                        // would place an Origin looks like a click that does nothing.
                        // DM-only: the table has no use for a crosshair hunting a point.
                        if armedShape != nil, let cursor = mirrorCursor {
                            MeasurementCursor().position(cursor)
                        }
                    }
                    // Measuring is a live play action, so it lives on the mirror rather
                    // than behind an editing mode — beside dragging a Pawn, not beside
                    // authoring Walls.
                    //
                    // Every point these handlers use comes from `mirrorCursor`, never from
                    // an event's own location: an `NSEvent` position cannot be converted
                    // into the space `mirrorFrame` is expressed in. See `mirrorCursor`.
                    //
                    // Right-click only opens the menu — picking a shape arms the tool, and
                    // the left-click after that says where the Measurement starts.
                    .onRightClick { rightClick() }
                    // While a chain is being drawn right-click FINISHES it rather than
                    // offering the menu, so the menu is withheld for that one state — a
                    // menu appearing over the chain the DM just completed would bury it.
                    .contextMenu { if !isChaining { measurementMenu } }
                    // Live only while the tool is armed or a Measurement is up, and lower
                    // priority than the Pawn drag underneath: dragging a token is the
                    // other live action on this surface, and a tap that swallowed it would
                    // break the more common one.
                    .simultaneousGesture(
                        TapGesture().onEnded { leftClick(map: map, frame: mirrorFrame) },
                        including: isMeasuring ? .all : .subviews
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            // The only reliable cursor position on this surface — every
                            // measuring handler reads it rather than an event's own.
                            mirrorCursor = location
                            aim(at: location, map: map, frame: mirrorFrame)
                        case .ended:
                            mirrorCursor = nil
                        }
                    }
                    // Digits are claimed only while a Measurement is armed, the cursor is
                    // over the Map, and no text field has focus. See MeasurementTyping.
                    .onMeasurementKeys(isArmed: isMeasuring,
                                       isOverMap: mirrorCursor != nil) {
                        handleMeasurementKey($0)
                    }
                    .clipped()
                    .position(x: visible.midX, y: visible.midY)
                } else {
                    // Only Grid Fit carries a zoom; every other use of this branch is the
                    // plain aspect fit, which is that transform's floor.
                    let modeTransform = mode == .gridFit ? gridFitTransform
                                      : mode == .fog ? fogTransform : nil
                    // The container every transform is measured against. Captured once
                    // from the GeometryReader and then FORCED onto the ZStack below: an
                    // unconstrained ZStack grows to hold the zoomed Image, the reader
                    // measures that overflow, and the container feeds back into the next
                    // zoom — the preview spills out of the window instead of zooming, and
                    // snaps back when layout resettles.
                    let previewSize = geo.size
                    let transform = modeTransform
                        ?? PreviewTransform.fitted(imagePixelSize: image.pixelSize, container: previewSize)
                    let fitted = transform.imageRect
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)
                            // Zoomed in this frame is far larger than the preview, and an
                            // overflowing Image owns its full frame for hit-testing — the
                            // regression issue 09 hit with the mirror. Pure display; the
                            // overlays handle interaction.
                            .allowsHitTesting(false)
                        if mode == .gridFit {
                            GridFitOverlay(transform: transform,
                                           containerSize: previewSize,
                                           square: $fitSquare) { gridFitTransform = $0 }
                        }
                        if mode == .fog {
                            let fogRegions = appState.litRegions
                            FogOverlay(transform: transform,
                                       containerSize: previewSize,
                                       tool: tool,
                                       gridPixels: gridPixels,
                                       edits: $fogEdits,
                                       selectedLight: $selectedLight,
                                       selectedPawn: $selectedPawn,
                                       isDimmed: { isInvisibleToPlayers($0, regions: fogRegions) },
                                       onChange: { applyFogEdits() },
                                       onTransform: { fogTransform = $0 })
                        }
                        if mode == .viewport, let map = appState.mapScale, let viewport = resolvedViewport {
                            ViewportOverlay(fittedRect: fitted,
                                            map: map,
                                            viewportSizeInches: viewport.sizeInches,
                                            originInches: viewport.originInches) { desired in
                                appState.viewportOrigin = desired
                            }
                        }
                    }
                    // Pin to the preview and clip. Both are load-bearing: without the
                    // frame the ZStack sizes itself to the zoomed Image and the reader
                    // above measures that instead of the preview; without the clip the
                    // zoomed Image draws over the controls. Together they make
                    // `previewSize` a fixed point rather than a function of the zoom.
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
                    // The Viewport drag measures itself here. Without this space the
                    // gesture falls back to the dragged rectangle's own coordinates,
                    // which move with it — see ViewportOverlay.dragGesture.
                    .coordinateSpace(name: ViewportOverlay.coordinateSpace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .border(.separator)
        } else {
            // With no Map open this used to be a bare `Spacer()`, which inside the
            // preview's HStack pushed sideways instead of filling downwards — the controls
            // above it got shoved around rather than staying put at the top of the window.
            // An empty view that claims both axes keeps the header where it is and leaves
            // the space below it blank, which is what "no Map yet" should look like.
            VStack {
                Spacer(minLength: 0)
                Text("No Map open. Choose one with “Open Map…”.")
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Modes

    @ViewBuilder
    private var modeControls: some View {
        switch mode {
        case .normal:
            Button("Fit Grid…") { startGridFit() }
                .disabled(appState.mapImage == nil)
            Button("Pan Viewport…") { startViewportPan() }
                .disabled(!mapOverflowsViewport)
            Button("Edit Fog…") { startFogEditing() }
                .disabled(appState.mapImage == nil)
        case .gridFit:
            if fitSquare != nil, let snap = GridFit.snapSuggestion(for: appState.squaresWide) {
                Button("Snap to \(snap)") { applySnap(snap) }
            }
            Button("Cancel") { cancelGridFit() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { endGridFit() }
                .keyboardShortcut(.defaultAction)
        case .viewport:
            Button("Cancel") { cancelViewportPan() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { mode = .normal }
                .keyboardShortcut(.defaultAction)
        case .fog:
            Picker("Tool", selection: $tool) {
                ForEach(FogTool.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            Text(fogSummary)
                .foregroundStyle(.secondary)
            Button("Undo") { fogEdits.undo(); applyFogEdits() }
                .disabled(!fogEdits.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button("Cancel") { cancelFogEditing() }
            Button("Done") { appState.endFogEditing(); mode = .normal }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func startFogEditing() {
        appState.beginFogEditing()
        // `beginFogEditing` drops the Measurement; the armed tool is view state and has to
        // be dropped alongside it, or the crosshair follows the DM into authoring.
        armedShape = nil
        typedDistance.clear()
        fogEdits = FogEdits(document: appState.fog)
        // Open on the whole Map, as Grid Fit does: the zoomed-out view orients, and zoom
        // is opt-in for the precision moment.
        fogTransform = nil
        mode = .fog
    }

    /// Discard the whole session. `AppState` owns the merge — the Grid and any live Pawn
    /// rename are not what this mode was editing and must survive Cancel.
    private func cancelFogEditing() {
        appState.cancelFogEditing(fogEdits)
        mode = .normal
    }

    /// Push the edited fog onto the Map. Called after every action so the Player Display
    /// and the fog file stay in step with what the DM sees.
    private func applyFogEdits() {
        appState.applyFogEdits(fogEdits)
    }

    private var fogSummary: String {
        let walls = appState.fog.walls.count
        let lights = appState.fog.lights.count
        let pawns = appState.fog.pawns.count
        return "\(walls) \(walls == 1 ? "Wall" : "Walls"), "
             + "\(lights) \(lights == 1 ? "Light" : "Lights"), "
             + "\(pawns) \(pawns == 1 ? "Pawn" : "Pawns")"
    }

    /// Whether players currently cannot see this Pawn — a hidden one, a Creature standing
    /// in the dark, or, under Solo Sight, a party member the isolated Pawn's light does not
    /// reach. The DM's surfaces draw it faded rather than dropping it, which is what turns
    /// this mode into a readout: the DM sees Bardo standing just outside Ilyana's reach and
    /// knows the table cannot.
    private func isInvisibleToPlayers(_ pawn: Pawn, regions: [LitRegion]) -> Bool {
        PlayerVisibility.isDimmedForDM(pawn: pawn, regions: regions,
                                       isFogOverlayOn: appState.isFogOverlayOn,
                                       hasVisibility: appState.hasDeclaredGrid,
                                       soloSightPawnID: appState.resolvedSoloSightPawnID)
    }

    /// One Grid square in image pixels, or nil when no Grid has been declared. Nothing
    /// snaps to it any more; it survives because a Pawn token is sized in Grid squares —
    /// a token reads as occupying its square — and the Lights inspector uses its absence
    /// to say that radii have no physical size yet.
    private var gridPixels: CGFloat? {
        guard appState.hasDeclaredGrid,
              let image = appState.mapImage, appState.squaresWide > 0 else { return nil }
        return GridFit.squareSide(imageWidth: image.pixelSize.width,
                                  squaresWide: appState.squaresWide)
    }

    // MARK: Measuring

    /// Left-click on the mirror: settle the Measurement at the distance now shown, so it
    /// stops following the mouse.
    ///
    /// The original requirement — "left click on a point in the screen to see the amount"
    /// — and it is not optional polish. Without it a Measurement rubber-bands forever, so
    /// the DM has to hold the mouse perfectly still to read the number and destroys it by
    /// moving to point at the shape. That is the failure ADR 0005 rejected under another
    /// name: evidence that vanishes the moment the table wants to discuss it.
    ///
    /// A left-click on a settled Measurement dismisses it, because right-click now opens
    /// the shape menu and can no longer double as the dismissal.
    ///
    /// So one button drives the whole life of a Measurement, each click advancing it one
    /// step: place the Origin, settle the distance, clear it. The DM never has to remember
    /// which button does which.
    private func leftClick(map: MapScale, frame: CGRect) {
        // An armed tool is waiting for its Origin, and that comes first: until one is
        // placed there is no Measurement to settle.
        if let shape = armedShape {
            placeOrigin(shape: shape, map: map, frame: frame)
            return
        }
        guard let measurement = appState.resolvedMeasurement else { return }
        typedDistance.clear()

        // A Line being drawn takes another vertex instead of settling: the whole point of
        // a chain is that clicking does not end it. Right-click finishes it.
        if measurement.isChaining {
            guard let cursor = mirrorCursor else { return }
            let point = PlayerPlacement.mapPoint(cursor, map: map, frame: frame)
            appState.setMeasurement(measurement.extended(to: point))
            return
        }

        appState.setMeasurement(measurement.clicked())
    }

    /// The left-click that says where an armed Measurement starts.
    ///
    /// Hit-tests the Pawns itself: a click on a token measures from that token, anything
    /// else from exactly the point clicked.
    private func placeOrigin(shape: MeasurementShape, map: MapScale, frame: CGRect) {
        guard let pixelsPerSquare = appState.pixelsPerSquare,
              let point = mirrorCursor else { return }
        let mapPoint = PlayerPlacement.mapPoint(point, map: map, frame: frame)
        let origin = MeasurementControl.origin(forClickAt: mapPoint,
                                               pawns: appState.fog.pawns,
                                               pixelsPerSquare: pixelsPerSquare)
        armedShape = nil
        typedDistance.clear()
        appState.setMeasurement(Measurement(origin: origin, shape: shape,
                                            distance: 0, direction: 0))
    }

    /// The shapes offered by the right-click menu. Picking one arms the tool; the next
    /// left-click says where the Measurement starts.
    ///
    /// The menu replaced a picker in the window chrome: choosing the shape belongs where
    /// the DM is already pointing, not at the top of the window, and a menu keeps the whole
    /// interaction on the Map. `.contextMenu` is a modifier rather than a composed gesture,
    /// so it does not run into the composition defects this render layer has a record of.
    @ViewBuilder
    private var measurementMenu: some View {
        if appState.measurementAvailability == .available {
            ForEach(MeasurementShape.allCases, id: \.self) { shape in
                Button(shape.label) { startMeasurement(shape) }
            }
        } else if case .disabled(let reason) = appState.measurementAvailability {
            // A menu that is merely empty teaches the DM nothing, and they are reading it
            // in front of players.
            Text(reason.explanation)
        }
    }

    /// Arm the tool with a shape and wait for the click that places it.
    ///
    /// Any Measurement already on screen goes now rather than when the Origin is placed:
    /// the DM has said they are measuring something else, and leaving the old shape up
    /// while a crosshair hunts for a new one puts two answers on the table's screen.
    private func startMeasurement(_ shape: MeasurementShape) {
        // Sticky, so the menu opens on the shape the DM last used.
        measurementShape = shape
        armedShape = shape
        typedDistance.clear()
        appState.setMeasurement(nil)
    }

    /// Right-click: finish a chain if one is being drawn, otherwise back out of an armed
    /// tool and let the shape menu open.
    private func rightClick() {
        if let measurement = appState.resolvedMeasurement, measurement.isChaining {
            // Frees the cursor: the chain stops following it and stays on screen until the
            // next click, so the DM can read the total and point at the route.
            guard let origin = appState.measurementOriginPoint,
                  let pixelsPerSquare = appState.pixelsPerSquare else { return }
            appState.setMeasurement(measurement.finished(origin: origin,
                                                         pixelsPerSquare: pixelsPerSquare))
            typedDistance.clear()
            return
        }
        armedShape = nil
    }

    /// Whether a Line is mid-chain, which changes what both buttons mean.
    private var isChaining: Bool {
        appState.resolvedMeasurement?.isChaining ?? false
    }

    /// Whether the DM is in the middle of measuring — either waiting to place an Origin,
    /// or with a Measurement on screen. The gate for the click and key handlers, which
    /// must stay inert the rest of the time.
    private var isMeasuring: Bool {
        armedShape != nil || appState.measurement != nil
    }

    /// Follow the cursor: an armed Measurement rubber-bands as the mouse moves, so the
    /// shape is live before it is committed. Distance snaps to whole squares — every DnD
    /// distance is a multiple of one, and nobody reads "8.7 m" off a screen.
    private func aim(at point: CGPoint, map: MapScale, frame: CGRect) {
        guard let measurement = appState.resolvedMeasurement,
              let origin = appState.measurementOriginPoint,
              let pixelsPerSquare = appState.pixelsPerSquare, pixelsPerSquare > 0 else { return }

        let cursor = PlayerPlacement.mapPoint(point, map: map, frame: frame)
        // `aimed` keeps a typed distance and follows the cursor with the aim either way.
        appState.setMeasurement(measurement.aimed(at: cursor, from: origin,
                                                  pixelsPerSquare: pixelsPerSquare))
    }

    /// A keystroke the Map claimed while a Measurement is armed. Which keystrokes those
    /// are is decided by `MeasurementTyping.decide`, not here.
    private func handleMeasurementKey(_ decision: MeasurementTyping.Decision) {
        // An armed tool has no Measurement yet, and the only key that means anything to it
        // is the one that backs out.
        if armedShape != nil, appState.measurement == nil {
            if decision == .abandon { armedShape = nil }
            return
        }
        guard var measurement = appState.resolvedMeasurement else { return }
        switch decision {
        case .passThrough:
            return
        case .digit(let digit):
            typedDistance.append(digit)
        case .backspace:
            typedDistance.backspace()
            // Back to an empty buffer is back to a dragged Measurement, so the next mouse
            // move sizes it again rather than leaving it frozen at the typed value.
            if typedDistance.isEmpty {
                measurement.isDistanceTyped = false
                measurement.distance = 0
                appState.setMeasurement(measurement)
            }
            return
        case .commit:
            guard let squares = typedDistance.squares(in: DistanceUnit.current) else { return }
            measurement.distance = squares
            measurement.isDistanceTyped = true
            appState.setMeasurement(measurement)
            typedDistance.clear()
            return
        case .abandon:
            // Esc abandons the digits, not the Measurement. Right-click is the one way to
            // dismiss one, and a second dismissal mechanism is what ADR 0005 objected to —
            // a DM who mistypes should not lose the Origin they picked.
            let hadDigits = !typedDistance.isEmpty
            typedDistance.clear()
            guard hadDigits else { return }
            measurement.isDistanceTyped = false
            measurement.distance = 0
            appState.setMeasurement(measurement)
            return
        }

        // Show the buffer as it is typed, so a mis-key is visible before Return rather
        // than after the shape jumps.
        if let squares = typedDistance.squares(in: DistanceUnit.current) {
            measurement.distance = squares
            measurement.isDistanceTyped = true
            appState.setMeasurement(measurement)
        }
    }

    private func startGridFit() {
        squaresWideBeforeFit = appState.squaresWide
        hadDeclaredGridBeforeFit = appState.hasDeclaredGrid
        fitSquare = nil
        // Open on the whole map: the zoomed-out view is the orientation step, and zoom
        // is opt-in for the precision moment.
        gridFitTransform = nil
        mode = .gridFit
    }

    private func endGridFit() {
        mode = .normal
        fitSquare = nil
        gridFitTransform = nil
    }

    /// Discard the fit, including anything the autosave debounce already wrote — the Grid
    /// Fit square writes on every drag tick, so a cancelled value is normally already
    /// queued. The explicit flush makes the file correct now rather than half a second
    /// from now, so a quit in between cannot persist a Grid the DM backed out of. Same
    /// tool and same reason as `cancelFogEditing`.
    private func cancelGridFit() {
        appState.restoreGrid(squaresWide: squaresWideBeforeFit,
                             wasDeclared: hadDeclaredGridBeforeFit)
        appState.flushPendingFogWrites()
        endGridFit()
    }

    private func startViewportPan() {
        viewportOriginBeforePan = appState.viewportOrigin
        mode = .viewport
    }

    private func cancelViewportPan() {
        appState.viewportOrigin = viewportOriginBeforePan
        mode = .normal
    }

    /// Suggested, never silent: applying the snap also resizes the overlay to match.
    private func applySnap(_ squares: Int) {
        appState.squaresWide = Double(squares)
        if let image = appState.mapImage, var square = fitSquare,
           let side = GridFit.squareSide(imageWidth: image.pixelSize.width,
                                         squaresWide: CGFloat(squares)) {
            square.side = side
            fitSquare = square
        }
    }

    // MARK: Fog

    /// The height the fog inspector row always claims, selected or not.
    ///
    /// A constant rather than an intrinsic height, because "however tall it happens to be"
    /// is exactly what made the preview jump: the row has to cost the same whether it is
    /// empty, showing a Light's two fields, or showing a Pawn's six controls. 24 pt is the
    /// measured fitting height of the taller of the two (the Pawn inspector, whose
    /// rounded-border text fields set the floor) at `.callout`.
    static let fogInspectorRowHeight: CGFloat = 24

    /// The container the fog preview measures its zoom and pan against.
    ///
    /// Deliberately ignores `hasInspectorSelection`. The inspector row above the preview is
    /// reserved unconditionally, so the GeometryReader's size already excludes it and
    /// selecting something cannot change what the preview is fitted into. Expressed as a
    /// function taking the flag — rather than not taking it — so the rule is testable and
    /// stated, instead of being an invariant that holds only by accident of the layout.
    static func fogPreviewContainer(geometry: CGSize, hasInspectorSelection: Bool) -> CGSize {
        geometry
    }

    /// Label, colour and range for the Pawn selected in the fog mode.
    @ViewBuilder
    private var pawnInspector: some View {
        if mode == .fog, tool == .pawns,
           let pawn = appState.fog.pawns.first(where: { $0.id == selectedPawn }) {
            HStack(spacing: 10) {
                TextField("label", text: Binding(
                    get: { pawn.label },
                    set: { fogEdits.setPawnLabel(id: pawn.id, $0); applyFogEdits() }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)

                ColorPicker("", selection: Binding(
                    get: { Color(hex: pawn.colorHex) ?? .red },
                    set: { fogEdits.setPawnColor(id: pawn.id, hex: $0.hexString); applyFogEdits() }
                ), supportsOpacity: false)
                .labelsHidden()

                // A picker, not two toggles: the three kinds are mutually exclusive, and a
                // pair of checkboxes would let a DM tick both and leave the token in a
                // state the model cannot represent.
                Picker("", selection: Binding(
                    get: { pawn.kind },
                    set: { fogEdits.setPawnKind(id: pawn.id, $0); applyFogEdits() }
                )) {
                    ForEach(PawnKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 104)
                .help("A Creature or a Treasure emits no Light and is hidden from players by darkness.")

                Toggle("Big", isOn: Binding(
                    get: { pawn.isBig },
                    set: { fogEdits.setPawnIsBig(id: pawn.id, $0); applyFogEdits() }
                ))
                .help("Occupies 2×2 squares instead of 1×1. Visual only — its light and sight are unchanged.")

                Text("Sight:")
                TextField("range", value: Binding(
                    get: { Double(pawn.light.brightSquares) },
                    set: {
                        fogEdits.setPawnSight(id: pawn.id, squares: CGFloat($0))
                        applyFogEdits()
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                // A Pawn has one radius. The extra square the region fades over is not a
                // second number the DM sets — it is there so the edge is not a hard cut —
                // so it is not offered as one.
                Text(pawn.isDiscovered
                     ? "squares — unused, a \(pawn.kind.title) emits no Light"
                     : "squares")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    /// Set a Light's state, from the live row. In the fog mode the write has to go
    /// through `FogEdits`, or the next edit would overwrite `appState.fog` wholesale from
    /// the edit buffer and silently revert the toggle.
    private func setLight(id: Light.ID, isOn: Bool) {
        if mode == .fog {
            if fogEdits.document.lights.first(where: { $0.id == id })?.isOn != isOn {
                fogEdits.toggleLight(id: id)
                applyFogEdits()
            }
        } else {
            appState.setLight(id: id, isOn: isOn)
        }
    }

    /// Light radii are in Grid squares, so an undeclared Grid renders every Light at a
    /// plausible-looking wrong size. Shown beside the Lights themselves rather than
    /// buried in the inspector: a DM who relaunches and never selects a Light would
    /// otherwise get no signal at all, which is the silent failure issue 03 forbids.
    @ViewBuilder
    private var undeclaredGridWarning: some View {
        if !(appState.fog.lights.isEmpty && appState.fog.pawns.isEmpty), !appState.hasDeclaredGrid {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("This Map's Grid has not been declared, so Light radii have no real size — run Fit Grid, or set the squares-wide value.")
                    .font(.caption)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// One Pawn in the live panel: its light toggle, and its label editable in place.
    ///
    /// Renaming lives here — beside the toggle, on the surface that is already the live
    /// control surface — rather than on a double-click on the token in `PawnLayer`. That
    /// layer owns the drag gesture, and gesture composition in this render layer has
    /// produced four defects already; a competing double-click there is the risky option
    /// for a marginal gain in directness.
    ///
    /// The write is `appState.setPawnLabel`, not `FogEdits`: a rename at the table is a
    /// live action and is not undoable, exactly as moving a Pawn is not.
    private func pawnLiveRow(_ pawn: Pawn) -> some View {
        HStack(spacing: 6) {
            // The token, not a switch: it is how the DM finds this row, since it carries
            // the same colour and label as the disc on the Map. Toggling its light is a
            // secondary use of it, so it is the one thing in the row that looks like the
            // Map rather than like a control.
            Toggle(isOn: Binding(
                get: { pawn.light.isOn },
                set: { appState.setPawnLight(id: pawn.id, isOn: $0) }
            )) {
                PawnToken(pawn: pawn, squareSide: 14, scalesWithFootprint: false)
            }
            .toggleStyle(.button)
            .help(pawn.isDiscovered
                  ? "\(pawn.label): a \(pawn.kind.title) — emits no Light. Click to douse the light it does not cast."
                  : "\(pawn.label): sight \(Int(pawn.light.brightSquares)) squares. Click to douse.")

            // Fills the column rather than a fixed 72 pt: names like "Goblin B" need the
            // room, and the panel has a known width to give them.
            TextField("label", text: Binding(
                get: { pawn.label },
                set: { appState.setPawnLabel(id: pawn.id, $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 0)

            // Take it off the Player Display without deleting it. The eye is filled when
            // players can see it and slashed when they cannot, so the DM reads the state
            // rather than the control.
            Toggle(isOn: Binding(
                get: { !pawn.isHidden },
                set: { appState.setPawnHidden(id: pawn.id, isHidden: !$0) }
            )) {
                Image(systemName: pawn.isHidden ? "eye.slash" : "eye")
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            .help(pawn.isHidden
                  ? "Hidden from players. Still here, and still yours to move."
                  : "Visible to players where the light reaches. Click to hide.")

            soloSightToggle(pawn)
        }
        // With one Pawn isolated, the rest of the party is switched out of the lighting,
        // and the panel should say so at a glance: a DM who forgets Solo Sight is on will
        // misread the Player Display, in front of players.
        //
        // Deliberately not `PawnLayer`'s 0.4. That one means "the players cannot see this
        // Pawn", and it is already doing its job on the Map beside this panel — a row is
        // dimmed here for the different reason that its *light* is switched out, which is
        // true of a Pawn the table can still plainly see standing in a brazier's glow.
        .opacity(isSwitchedOutBySoloSight(pawn) ? soloSightSwitchedOutOpacity : 1)
    }

    /// How far a row is faded when Solo Sight has switched its Pawn out of the lighting.
    /// Lighter than `PawnLayer`'s 0.4: this says "not lighting the Map", not "invisible".
    private var soloSightSwitchedOutOpacity: Double { 0.5 }

    /// Whether this row is one of the Pawns Solo Sight has switched out.
    private func isSwitchedOutBySoloSight(_ pawn: Pawn) -> Bool {
        guard let isolated = appState.resolvedSoloSightPawnID else { return false }
        // A hidden Pawn was already off the table's screen and already out of the lighting
        // before the mode started, and its slashed eye says so. Dimming its row too would
        // blame Solo Sight for something the DM did themselves, in the one readout that is
        // meant to tell them exactly who the mode is costing them.
        return pawn.id != isolated && !pawn.isDiscovered && !pawn.isHidden
    }

    /// See the Map as one character alone lights it: every other Pawn's Light goes out, and
    /// the table sees it too. Radio-button semantics — clicking another Pawn's control moves
    /// the isolation, clicking the active one ends it.
    @ViewBuilder
    private func soloSightToggle(_ pawn: Pawn) -> some View {
        let availability = SoloSightControl.availability(
            for: pawn,
            isFogOverlayOn: appState.isFogOverlayOn,
            hasDeclaredGrid: appState.hasDeclaredGrid)
        if availability != .absent {
            let isSolo = appState.resolvedSoloSightPawnID == pawn.id
            Toggle(isOn: Binding(
                get: { isSolo },
                set: { appState.setSoloSight(id: $0 ? pawn.id : nil) }
            )) {
                // Both variants exist, unlike `person.viewfinder`, which does not: the
                // inactive state rendered as an empty button until this was caught by eye.
                // Filled when active and outline when not, so the DM reads the state rather
                // than the control — the same way the eye beside it does.
                Image(systemName: isSolo ? "binoculars.fill" : "binoculars")
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            .disabled(availability != .available)
            .help(soloSightHelp(pawn, availability: availability, isSolo: isSolo))
        }
    }

    private func soloSightHelp(_ pawn: Pawn, availability: SoloSightControl.Availability,
                               isSolo: Bool) -> String {
        if case .disabled(let reason) = availability { return reason.explanation }
        return isSolo
            ? "Solo Sight. The table sees only what \(pawn.label)\'s own light reaches. Click to end."
            : "Solo Sight: show the Map as \(pawn.label) alone lights it."
    }

    /// The Fog Overlay's off switch: one control, always reachable, no mode to enter.
    /// It stays inline rather than joining the side panel because it governs the whole
    /// Map rather than any one thing in the list.
    @ViewBuilder
    private var fogSwitch: some View {
        if !appState.fog.walls.isEmpty || !appState.fog.lights.isEmpty
            || !appState.fog.pawns.isEmpty {
            Toggle("Fog", isOn: $appState.isFogOverlayOn)
                .toggleStyle(.switch)
                .help("Hide or reveal the Fog Overlay on the Player Display. Pawns stay visible either way.")
        }
    }

    /// Everything on the Map that can be switched, listed down the side of the preview.
    ///
    /// Vertical and grouped, because the horizontal row this replaces did not survive
    /// contact with a real encounter: a party of four plus a room of goblins ran off the
    /// right-hand edge, and each entry carries a token, a name field and two toggles, so
    /// they are wide. A vertical list gives every row the same shape, lets the names be
    /// read down a column, and turns "which goblin is 3" into a glance.
    ///
    /// The kinds are separated because they are what the DM reasons about separately — the
    /// party is who they are running the world *for*, the Creatures are what they run *at*
    /// them, and the Treasure is what the room is worth. Lights lead because they are the
    /// Map's own furniture rather than anyone's token.
    @ViewBuilder
    private var livePanel: some View {
        if !appState.fog.lights.isEmpty || !appState.fog.pawns.isEmpty {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    if !appState.fog.lights.isEmpty {
                        liveGroup("Lights", count: appState.fog.lights.count) {
                            ForEach(Array(appState.fog.lights.enumerated()), id: \.element.id) { index, light in
                                lightLiveRow(light, number: index + 1)
                            }
                        }
                    }
                    // One group per kind, driven by the enum rather than by a filter per
                    // group. Two hand-written filters only partition the array as long as
                    // nobody adds a third kind — which is exactly what happened — and a
                    // Pawn missing from this panel is one the DM cannot hide or rename
                    // mid-fight.
                    ForEach(PawnKind.allCases, id: \.self) { kind in
                        let group = appState.fog.pawns.filter { $0.kind == kind }
                        if !group.isEmpty {
                            liveGroup(kind.pluralTitle, count: group.count) {
                                ForEach(group) { pawnLiveRow($0) }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: 236)
            // `.controlBackgroundColor` is all but identical to the window's own, so the
            // panel read as text floating beside the Map rather than as a surface. The
            // preview next to it is bordered; this needs to look like its sibling.
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
    }

    /// One titled group in the side panel. The count is in the heading so the DM can see
    /// "Creatures 6" without counting rows.
    private func liveGroup<Content: View>(_ title: String, count: Int,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
    }

    /// One Light in the side panel. A Light has no label of its own, so it is identified
    /// by its position in the list, exactly as it was in the row this replaces.
    private func lightLiveRow(_ light: Light, number: Int) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { light.isOn },
                set: { setLight(id: light.id, isOn: $0) }
            )) {
                Image(systemName: light.isOn ? "flame.fill" : "flame")
                    .frame(width: 16)
            }
            .toggleStyle(.button)

            Text("Light \(number)")
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(Int(light.brightSquares))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Bright \(Int(light.brightSquares)), dim \(Int(light.dimSquares)) squares")
        }
    }

    /// Radii for the Light selected in the fog mode. In **Grid squares**, because a Light
    /// is a physical thing — every 5e stat block reads "bright 20 ft, dim 40 ft".
    @ViewBuilder
    private var lightInspector: some View {
        if mode == .fog, tool == .lights, let light = appState.fog.lights.first(where: { $0.id == selectedLight }) {
            HStack(spacing: 10) {
                Text("Bright:")
                TextField("bright", value: Binding(
                    get: { Double(light.brightSquares) },
                    set: { fogEdits.setLightRadii(id: light.id, brightSquares: CGFloat($0),
                                                  dimSquares: light.dimSquares); applyFogEdits() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)

                Text("Dim:")
                TextField("dim", value: Binding(
                    get: { Double(light.dimSquares) },
                    set: { fogEdits.setLightRadii(id: light.id, brightSquares: light.brightSquares,
                                                  dimSquares: CGFloat($0)); applyFogEdits() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)

                Text("squares").foregroundStyle(.secondary)
                if gridPixels == nil {
                    Text("— no Grid declared, so these have no physical size yet")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
        }
    }

    /// Shown when a Map's fog file exists but could not be read. Silence here is the
    /// dangerous case: the DM would see a Map with no Walls, assume none were ever drawn,
    /// redraw them, and the next save would overwrite the file that still holds the
    /// originals. The path is spelled out so they can recover it by hand.
    @ViewBuilder
    private var fogLoadWarning: some View {
        if let failure = appState.fogLoadFailure {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not read this Map's fog — its Walls and Lights are not shown.")
                    Text("\(failure.url.path) — drawing over this Map will replace it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Player Display

    @ViewBuilder
    private var playerDisplayStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.playerScreen == nil ? "tv.slash" : "tv")
                .foregroundStyle(appState.playerScreen == nil ? Color.secondary : Color.green)
            Picker("Player Display", selection: playerDisplaySelection) {
                Text("None — not presenting").tag(DisplayIdentity?.none)
                ForEach(appState.displayCandidates, id: \.identity) { candidate in
                    Text(label(for: candidate)).tag(DisplayIdentity?.some(candidate.identity))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 420)
        }
        // Presented, but EDID reports no physical size: True Scale is a guess until
        // Calibration. Said plainly rather than hiding the screen from the picker.
        if appState.playerScreen != nil, appState.playerMetrics == nil {
            Label("Physical size unknown — True Scale unverified on this display",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if appState.displayCandidates.count > 1,
           appState.displayCandidates.allSatisfy(\.isBuiltin) == false,
           appState.playerScreen == nil {
            Label("Multiple displays connected — choose the Player Display above",
                  systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var playerDisplaySelection: Binding<DisplayIdentity?> {
        Binding(
            get: { appState.playerScreen?.displayIdentity },
            set: { if let identity = $0 { appState.chooseDisplay(identity) } }
        )
    }

    /// Resolution and physical size, so two identical TVs are told apart by text.
    private func label(for candidate: DisplayCandidate) -> String {
        var parts = [candidate.identity.name]
        if candidate.isBuiltin { parts.append("(built-in)") }
        if let metrics = candidate.metrics {
            parts.append("— \(Int(metrics.pixelSize.width))×\(Int(metrics.pixelSize.height)) px")
            parts.append("\(Int(metrics.physicalSizeMM.width))×\(Int(metrics.physicalSizeMM.height)) mm")
        } else {
            parts.append("— size unknown")
        }
        return parts.joined(separator: " ")
    }
}
