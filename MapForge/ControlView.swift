import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var appState: AppState

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
            }

            playerDisplayStatus

            if let image = appState.mapImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(.separator)
            } else {
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 400)
    }

    @ViewBuilder
    private var playerDisplayStatus: some View {
        if let screen = appState.playerScreen, let metrics = appState.playerMetrics {
            Label {
                Text(verbatim: "\(screen.localizedName) — \(Int(metrics.physicalSizeMM.width))×\(Int(metrics.physicalSizeMM.height)) mm, \(String(format: "%.1f", metrics.pixelsPerInch.width)) ppi")
            } icon: {
                Image(systemName: "tv").foregroundStyle(.green)
            }
        } else {
            Label("No Player Display connected", systemImage: "tv.slash")
                .foregroundStyle(.secondary)
        }
    }
}
