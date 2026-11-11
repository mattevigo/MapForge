import SwiftUI

/// The Map at True Scale, centered, black letterbox — or, under Map Fit, the whole Map as
/// large as the screen allows, letterboxed the same way — plus the Pawns standing on it.
///
/// Pawns are drawn here whether or not the Fog Overlay is active: a Pawn is a token
/// first and a Light second, so switching fog off leaves the players their tokens.
struct PlayerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                // True Scale at the Viewport, or under Map Fit the whole Map fitted to the
                // screen. Everything below places itself against this frame, so every Pawn,
                // Light and Measurement follows the artwork either way.
                //
                // No frame is True Scale on a screen that reports no physical size, which
                // stays black. Map Fit needs no size, so it draws there all the same.
                if let image = appState.mapImage,
                   let map = appState.mapScale,
                   let frame = ScaleMath.playerFrame(map: map, display: appState.playerMetrics,
                                                     screenSizePoints: geo.size,
                                                     desiredViewportOrigin: appState.viewportOrigin,
                                                     isMapFitOn: appState.isMapFitOn) {
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
                    // Light Markers under the Pawns: a token is the game piece and must
                    // never be obscured by the furniture. Only the Map's own Lights — a
                    // Pawn already draws a token at exactly its own light's point.
                    ForEach(appState.fog.lights.filter {
                        PlayerVisibility.showsLightMarkerToPlayers(
                            light: $0, regions: regions,
                            isFogOverlayOn: appState.isFogOverlayOn,
                            hasVisibility: appState.hasDeclaredGrid)
                    }) { light in
                        let p = PlayerPlacement.viewPoint(light.at, map: map, frame: frame)
                        LightMarker(squareSide: side)
                            .position(x: p.x, y: p.y)
                    }

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
                        PawnToken(pawn: pawn, squareSide: side, isForPlayers: true)
                            .position(x: p.x, y: p.y)
                    }

                    // The table sees the Measurement, its distance included — the first
                    // thing on this screen that is instrumentation rather than world, and
                    // a deliberate breach of the rule that kept it to two. See ADR 0005:
                    // a measurement only the DM can see answers the question for the one
                    // person who could already estimate it.
                    //
                    // Above the tokens, and not gated on the Fog Overlay: the DM drew this
                    // to be seen, and darkness hiding it would defeat the point.
                    //
                    // Gated instead on `playerMeasurements`, the DM's own switch — a
                    // Measurement taken to plan a monster's next move is not one they drew
                    // to be seen. See `AppState.showsMeasurementsToPlayers`.
                    if let pixelsPerSquare = appState.pixelsPerSquare {
                        ForEach(appState.playerMeasurements) {
                            MeasurementLayer(drawable: $0, map: map, frame: frame,
                                             pixelsPerSquare: pixelsPerSquare,
                                             unit: appState.distanceUnit)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        // Where every token on this screen finds its Face — the same library the Control
        // Window reads, so the two screens cannot disagree about what a Pawn looks like.
        .environment(\.faceLibrary, appState.faceLibrary)
    }
}
