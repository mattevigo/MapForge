import SwiftUI

/// The pure Map, True Scale, centered, black letterbox — nothing else.
struct PlayerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = appState.mapImage,
                   let map = appState.mapScale,
                   let metrics = appState.playerMetrics {
                    let viewport = ScaleMath.resolvedViewport(map: map, display: metrics,
                                                              screenSizePoints: geo.size,
                                                              desiredOrigin: appState.viewportOrigin)
                    let frame = ScaleMath.trueScaleFrame(map: map, display: metrics,
                                                         screenSizePoints: geo.size,
                                                         viewportOriginInches: viewport.originInches)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .ignoresSafeArea()
    }
}
