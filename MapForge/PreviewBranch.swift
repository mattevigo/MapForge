import CoreGraphics

/// What the Control Window's preview is currently for.
///
/// `.normal` is the DM watching the table; the other three each take the preview over for a
/// prep task. Lifted out of `ControlView` so `PreviewBranch` can be asked about a mode
/// without standing up the view.
/// `.viewport` was a fourth case until panning became a toggle on the Live View
/// (`ViewportToggle`): a DM moves what the table sees mid-sentence, and a mode with a Cancel
/// and a Done is a thing to get wrong in front of players. The two that remain are prep
/// tasks the DM enters deliberately and leaves again.
enum PreviewMode { case normal, gridFit, fog }

/// Which of the Control Window preview's two branches runs, and what each one owes the DM.
///
/// The preview draws the whole Map, aspect-fitted, in every mode.
///
/// It used to have a second branch: **the mirror**, which cropped the Live View to exactly
/// what the Player Display showed, letterbox and all. That was exact and it was the wrong
/// trade — a DM looking at the mirror could not see what was about to walk into the room,
/// and could not place a Pawn or a Light outside the Viewport without panning there first.
/// The green Viewport rectangle answers "what do the players see" instead, drawn over a Map
/// the DM can see all of.
///
/// The two were separated by what they draw the Map *for*, and the live layers — Pawns,
/// Light Markers, the Fog tint, Measurements — were built on the mirror because the mirror
/// was the DM's view of the table. That made them conditional on a Player Display being
/// connected, which is not a condition anyone chose: a DM prepping a Map on a laptop with no
/// HDMI screen saw bare artwork and no Pawns at all, while the Scene tab listed them and the
/// Initiative Tracker rolled for them.
///
/// Pure policy beside `SoloSightControl` and `MeasurementControl`, for the same reason: the
/// condition deciding whether the DM can see their own party is worth stating once, in a
/// place a test can ask, rather than living inside a `if let` in a 1,700-line view.
enum PreviewBranch {
    /// The Viewport the mirror branch needs, or nil when there is nothing to mirror.
    ///
    /// Takes its inputs rather than reading `AppState` so the nil case — the whole bug — is
    /// reachable from a test without standing up a display.
    static func viewport(map: MapScale, display: DisplayMetrics?, screenSizePoints: CGSize?,
                         desiredOrigin: CGPoint?) -> Viewport? {
        guard let display, let screenSizePoints else { return nil }
        return ScaleMath.resolvedViewport(map: map, display: display,
                                          screenSizePoints: screenSizePoints,
                                          desiredOrigin: desiredOrigin)
    }

    /// Whether the preview draws the live layers: Pawn tokens, Light Markers, the Fog tint
    /// the DM reads through, and any Measurement on the Map.
    ///
    /// **Not conditional on a Player Display**, which is the whole of the bug this exists
    /// to state. A Pawn the DM cannot see is a Pawn the DM cannot drag, and dragging a Pawn
    /// is this app's headline live action — it does not become less true when nothing is
    /// plugged in.
    ///
    /// Conditional on the mode and nothing else: Grid Fit, Viewport and fog editing each own
    /// the preview while they run, and fog editing draws its own Pawns already. Stacking the
    /// live layer over `FogOverlay` would draw every token twice.
    static func drawsLiveLayers(mode: PreviewMode) -> Bool {
        mode == .normal
    }

    /// The rect the Map's artwork occupies, which every live layer places against.
    ///
    /// With a Viewport this is the image frame rebased into the clipped container, carrying
    /// the pan. Without one it is the plain aspect fit — the same rect the Image is drawn
    /// into, so a token lands on the artwork rather than beside it.
    static func liveLayerFrame(imagePixelSize: CGSize, viewportRect: CGRect?,
                               container: CGSize) -> CGRect {
        guard let viewportRect, viewportRect.width > 0, viewportRect.height > 0 else {
            return PreviewTransform.fitted(imagePixelSize: imagePixelSize,
                                           container: container).imageRect
        }
        let frame = ViewportMath.mirrorImageFrame(imagePixelSize: imagePixelSize,
                                                  viewportRect: viewportRect,
                                                  container: container)
        let visible = ViewportMath.mirrorViewportRect(viewportRect: viewportRect,
                                                      container: container)
        return CGRect(x: frame.minX - visible.minX,
                      y: frame.minY - visible.minY,
                      width: frame.width, height: frame.height)
    }
}
