import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isFittingGrid = false
    @State private var fitSquare: GridFitSquare?
    @State private var squaresWideBeforeFit: Double = 0

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
                gridFitControls
            }

            if isFittingGrid, fitSquare == nil {
                Text("Drag a square over one grid square of the map, then nudge it with the handles or arrow keys (⇧ resizes).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            playerDisplayStatus

            if let image = appState.mapImage {
                GeometryReader { geo in
                    let fitted = GridFit.fittedImageRect(imagePixelSize: image.pixelSize,
                                                        container: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)
                        if isFittingGrid {
                            GridFitOverlay(fittedRect: fitted,
                                           imagePixelSize: image.pixelSize,
                                           square: $fitSquare)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(.separator)
            } else {
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
        .onChange(of: fitSquare) { _, square in
            guard let square, let image = appState.mapImage,
                  let squaresWide = GridFit.squaresWide(imageWidth: image.pixelSize.width,
                                                        squareSide: square.side) else { return }
            appState.squaresWide = Double(squaresWide)
        }
    }

    @ViewBuilder
    private var gridFitControls: some View {
        if isFittingGrid {
            if fitSquare != nil, let snap = GridFit.snapSuggestion(for: appState.squaresWide) {
                Button("Snap to \(snap)") { applySnap(snap) }
            }
            Button("Cancel") { cancelGridFit() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { endGridFit() }
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Fit Grid…") { startGridFit() }
                .disabled(appState.mapImage == nil)
        }
    }

    private func startGridFit() {
        squaresWideBeforeFit = appState.squaresWide
        fitSquare = nil
        isFittingGrid = true
    }

    private func endGridFit() {
        isFittingGrid = false
        fitSquare = nil
    }

    private func cancelGridFit() {
        appState.squaresWide = squaresWideBeforeFit
        endGridFit()
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

    @ViewBuilder
    private var playerDisplayStatus: some View {
        if let screen = appState.playerScreen, let metrics = appState.playerMetrics {
            Label {
                Text(verbatim: "\(screen.localizedName) — \(Int(metrics.physicalSizeMM.width))×\(Int(metrics.physicalSizeMM.height)) mm, \(String(format: "%.1f", metrics.pixelsPerInch.width)) ppi")
            } icon: {
                Image(systemName: "tv").foregroundStyle(.green)
            }
        } else if appState.externalScreens.count > 1 {
            Label("Multiple external displays — picker not built yet (issue 05)", systemImage: "tv.slash")
                .foregroundStyle(.orange)
        } else {
            Label("No Player Display connected", systemImage: "tv.slash")
                .foregroundStyle(.secondary)
        }
    }
}
