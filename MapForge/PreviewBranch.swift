import CoreGraphics

/// What the Control Window's preview is currently for.
///
/// `.normal` is the DM watching the table; the other three each take the preview over for a
/// prep task. Lifted out of `ControlView` so `PreviewBranch` can be asked about a mode
/// without standing up the view.
enum PreviewMode { case normal, gridFit, viewport, fog }

/// Which of the Control Window preview's two branches runs, and what each one owes the DM.
///
/// The preview draws the Map one of two ways. **The mirror** shows exactly the portion the
/// Player Display shows, letterbox and all, and needs a resolved Viewport to know what that
/// portion is. **The fitted** branch shows the whole Map aspect-fitted into the preview, and
/// is what every editing mode is authored against.
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
    /// **Not conditional on a Player Display.** A Pawn the DM cannot see is a Pawn the DM
    /// cannot drag, and dragging a Pawn is this app's headline live action — it does not
    /// become less true when nothing is plugged in.
    ///
    /// It *is* conditional on the mode: Grid Fit, Viewport and fog editing each own the
    /// preview while they run, and fog editing draws its own Pawns already. Stacking the
    /// live layer over `FogOverlay` would draw every token twice.
    static func drawsLiveLayers(mode: PreviewMode, hasViewport: Bool) -> Bool {
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
