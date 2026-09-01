import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var appState: AppState

    private enum PreviewMode { case normal, gridFit, viewport }

    @State private var mode: PreviewMode = .normal
    @State private var fitSquare: GridFitSquare?
    @State private var squaresWideBeforeFit: Double = 0
    @State private var viewportOriginBeforePan: CGPoint?
    /// Grid Fit's preview zoom/pan. Mode-local view state, not part of the Map — it is
    /// reset to fit-to-window on entering the mode.
    @State private var gridFitTransform: PreviewTransform?

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

            playerDisplayStatus

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
                    }
                    .frame(width: visible.width, height: visible.height)
                    .clipped()
                    // .clipped() masks drawing only: the overflowing Image still owns
                    // its full frame for hit-testing and would swallow clicks on the
                    // controls above. The mirror is pure display — take it out of
                    // hit-testing entirely.
                    .allowsHitTesting(false)
                    .position(x: visible.midX, y: visible.midY)
                } else {
                    // Only Grid Fit carries a zoom; every other use of this branch is the
                    // plain aspect fit, which is that transform's floor.
                    let transform = (mode == .gridFit ? gridFitTransform : nil)
                        ?? PreviewTransform.fitted(imagePixelSize: image.pixelSize, container: geo.size)
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
                                           containerSize: geo.size,
                                           square: $fitSquare) { gridFitTransform = $0 }
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
        }
    }

    private func startGridFit() {
        squaresWideBeforeFit = appState.squaresWide
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

    private func cancelGridFit() {
        appState.squaresWide = squaresWideBeforeFit
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
