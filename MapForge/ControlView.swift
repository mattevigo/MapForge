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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Open Map…") { appState.openMap() }
                if let url = appState.mapURL {
                    Text(url.lastPathComponent).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Grid squares wide:")
                TextField("squares", value: $appState.squaresWide, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                Stepper("squares", value: $appState.squaresWide, in: 1...500)
                    .labelsHidden()
                Spacer()
                modeControls
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
                lightInspector
                pawnInspector
            }

            playerDisplayStatus

            fogLoadWarning

            undeclaredGridWarning

            lightToggles

            preview
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
        .onChange(of: fitSquare) { _, square in
            guard let square, let image = appState.mapImage,
                  let squaresWide = GridFit.squaresWide(imageWidth: image.pixelSize.width,
                                                        squareSide: square.side) else { return }
            appState.squaresWide = Double(squaresWide)
        }
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
                                  frame: CGRect(x: frame.minX - visible.minX,
                                                y: frame.minY - visible.minY,
                                                width: frame.width, height: frame.height)) {
                            FogShading.control($0, isOverlayOn: appState.isFogOverlayOn)
                        }
                    }
                    .overlay {
                        // Dragging a Pawn is a LIVE action — the party moves during play,
                        // not during prep — so it works on the normal mirror, outside the
                        // fog editing mode entirely.
                        PawnLayer(map: map,
                                  frame: CGRect(x: frame.minX - visible.minX,
                                                y: frame.minY - visible.minY,
                                                width: frame.width, height: frame.height),
                                  pawns: appState.fog.pawns,
                                  // Hoisted, not read per Pawn: `litRegions` is computed,
                                  // and rebuilding the cache key for every token every
                                  // frame of a drag is exactly the drag-rate work this
                                  // file's comments record a regression over.
                                  isDimmed: { [regions = appState.litRegions] pawn in
                                      isInvisibleToPlayers(pawn, regions: regions)
                                  },
                                  onMove: { appState.movePawn(id: $0, to: $1) },
                                  onCommit: { appState.flushPendingFogWrites() })
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
            Spacer()
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
            Button("Done") { mode = .normal }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func startFogEditing() {
        appState.beginFogEditing()
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

    /// Whether players currently cannot see this Pawn — a hidden one, or a Creature
    /// standing in the dark. The DM's surfaces draw it faded rather than dropping it.
    private func isInvisibleToPlayers(_ pawn: Pawn, regions: [LitRegion]) -> Bool {
        PlayerVisibility.isDimmedForDM(pawn: pawn, regions: regions,
                                       isFogOverlayOn: appState.isFogOverlayOn,
                                       hasVisibility: appState.hasDeclaredGrid)
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

                Toggle("Creature", isOn: Binding(
                    get: { pawn.isCreature },
                    set: { fogEdits.setPawnIsCreature(id: pawn.id, $0); applyFogEdits() }
                ))
                .help("A Creature emits no Light and is hidden from players by darkness.")

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
                // Naming the dim radius rather than leaving a second, larger circle on the
                // Map with nothing in the UI to explain it — it looked fixed and unrelated
                // to the number being typed.
                Text(pawn.isCreature
                     ? "squares — unused, a Creature emits no Light"
                     : "squares, dim to \(Int(pawn.light.dimSquares))")
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
        HStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { pawn.light.isOn },
                set: { appState.setPawnLight(id: pawn.id, isOn: $0) }
            )) {
                PawnToken(pawn: pawn, diameter: 14)
            }
            .toggleStyle(.button)
            .help(pawn.isCreature
                  ? "\(pawn.label): a Creature — emits no light, seen by players only where the light reaches it"
                  : "\(pawn.label): sight \(Int(pawn.light.brightSquares)) squares — the field renames it")

            TextField("label", text: Binding(
                get: { pawn.label },
                set: { appState.setPawnLabel(id: pawn.id, $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)

            // Take it off the Player Display without deleting it. The eye is filled when
            // players can see it and slashed when they cannot, so the DM reads the state
            // rather than the control.
            Toggle(isOn: Binding(
                get: { !pawn.isHidden },
                set: { appState.setPawnHidden(id: pawn.id, isHidden: !$0) }
            )) {
                Image(systemName: pawn.isHidden ? "eye.slash" : "eye")
            }
            .toggleStyle(.button)
            .help(pawn.isHidden
                  ? "Hidden from players. Still here, and still yours to move."
                  : "Visible to players where the light reaches. Click to hide.")
        }
    }

    /// The live panel: on/off for every Light, always visible, never behind a mode.
    /// Toggling is the one fog action a DM performs mid-session with players watching, so
    /// it must be one click with nothing to open first.
    @ViewBuilder
    private var lightToggles: some View {
        if !appState.fog.walls.isEmpty || !appState.fog.lights.isEmpty
            || !appState.fog.pawns.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // The off switch: one control, always reachable, no mode to enter.
                    Toggle("Fog", isOn: $appState.isFogOverlayOn)
                        .toggleStyle(.switch)
                        .help("Hide or reveal the Fog Overlay on the Player Display. Pawns stay visible either way.")
                    Divider().frame(height: 16)
                    Text("Lights:").foregroundStyle(.secondary)
                    ForEach(Array(appState.fog.lights.enumerated()), id: \.element.id) { index, light in
                        Toggle(isOn: Binding(
                            get: { light.isOn },
                            set: { setLight(id: light.id, isOn: $0) }
                        )) {
                            Text("\(index + 1)")
                        }
                        .toggleStyle(.button)
                        .help("Light \(index + 1): bright \(Int(light.brightSquares)), dim \(Int(light.dimSquares)) squares")
                    }
                    // A Pawn's own light toggles here too: a character putting out their
                    // torch is the same live action as dousing a brazier — and its label
                    // is renamed here, for the same reason.
                    ForEach(appState.fog.pawns) { pawn in
                        pawnLiveRow(pawn)
                    }
                }
            }
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
