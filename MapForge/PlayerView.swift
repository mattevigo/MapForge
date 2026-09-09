import SwiftUI

/// The Map at True Scale, centered, black letterbox — plus the Pawns standing on it.
///
/// Pawns are drawn here whether or not the Fog Overlay is active: a Pawn is a token
/// first and a Light second, so switching fog off leaves the players their tokens.
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

                    // Darkness over the Map, under the Pawns: a token stays visible in an
                    // unlit room, because turning fog on is not turning tokens off.
                    if appState.isFogOverlayOn {
                        FogCanvas(regions: appState.litRegions, map: map, frame: frame) {
                            FogShading.player($0)
                        }
                    }

                    // Sized in Grid squares, so a token reads as occupying its square at
                    // True Scale — the same physical size as the miniature would be.
                    // Floored, as both Control Window surfaces are: a Map with no declared
                    // physical size yields a zero-width square, and an invisible token is
                    // worse than an approximately-sized one — the Pawn must render
                    // regardless of the fog's state.
                    let side = max(PlayerPlacement.squareSidePoints(map: map, frame: frame), 12)
                    let regions = appState.litRegions
                    // A party Pawn always draws; a Creature only where the light reaches
                    // it, and never when the DM has hidden it. Under Solo Sight the party
                    // draws by that same discovery rule, all but the isolated Pawn itself.
                    // See `PlayerVisibility`.
                    ForEach(appState.fog.pawns.filter {
                        PlayerVisibility.showsToPlayers(pawn: $0, regions: regions,
                                                        isFogOverlayOn: appState.isFogOverlayOn,
                                                        hasVisibility: appState.hasDeclaredGrid,
                                                        soloSightPawnID: appState.resolvedSoloSightPawnID)
                    }) { pawn in
                        let p = PlayerPlacement.viewPoint(pawn.at, map: map, frame: frame)
                        PawnToken(pawn: pawn, squareSide: side)
                            .position(x: p.x, y: p.y)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
