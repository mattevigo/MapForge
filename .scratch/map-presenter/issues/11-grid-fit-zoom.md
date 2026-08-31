# 11 — Grid Fit zoom

Status: closed
Blocked by: 08

Zoom and pan the Control Window preview while in Grid Fit mode, so the DM draws the fit square over a magnified grid square instead of over the whole map at once. Today Grid Fit hard-fits the entire image into the preview (`GridFit.fittedImageRect`, taken in the non-mirror branch of `ControlView.preview`): on a 3000x2000 px map in a ~450 pt preview the view scale is ~0.15, so one printed grid square is ~15 preview points and a 1-point mis-drag is ~6.7% error in the derived squares-wide. Zoom removes the precision ceiling without changing what Grid Fit produces.

This supersedes part of issue 08's reasoning, not its interaction: 08 chose the live readout, the arrow-key nudge and the suggested snap *as substitutes for zoom*. All three stay, and the nudge gets better (see below).

This does not touch True Scale. "Never resizable — resizing would zoom and break True Scale" (`ViewportOverlay`, issue 09) is about the Player Display window and remains true: the zoom here is the DM's preview only, and the Player Display keeps rendering at 1 map inch = 1 physical inch throughout.

Interaction:

- Grid Fit still opens fit-to-window, as today — the whole-map view is the orientation step. Zoom is opt-in for the precision moment.
- Scroll wheel and trackpad pinch zoom the preview; ⌥-drag pans it. Plain drag keeps its current meanings (draw a new square, move the body, drag a corner handle) — the modifier is what keeps pan from colliding with them.
- Zoom is cursor-anchored: the image point under the pointer stays under the pointer. Scroll-to-zoom therefore doubles as navigation, and ⌥-drag pan is the fallback for what it doesn't cover.
- Zoom range is expressed as image pixels per preview point. The floor is fit-to-window — the map can never be zoomed out smaller than the preview. The ceiling is 1:1, one image pixel to one preview point; past that there is no more precision to extract, since `GridFitSquare` is stored in image pixels. A map smaller than the preview would aspect-fit *above* 1:1, inverting the range; it is pinned at 1:1 and centered instead, which also stops Grid Fit rendering such a map upscaled and blurry (a change from the old unconditional aspect fit).
- The arrow-key nudge keeps its `1 / viewScale` step but is floored at 1 image pixel. It auto-refines as the DM zooms in (at 1:1 it is exactly 1 image pixel) and never degenerates into a keypress that moves nothing.
- The fit square is stored in image pixels and so is zoom-invariant: it stays on the artwork it was drawn over and re-renders at the new scale. Zoom or pan can leave it off-screen; that is accepted, with no recentre affordance this increment.
- Entering Grid Fit resets the zoom to fit-to-window. The zoom is mode-local view state, not part of the Map.

Scope:

- Still derives squares-wide only. `GridFitSquare.center` remains discarded. Anchoring the lattice to a grid origin — which zoomed single-square selection makes newly tempting — needs grid overlay rendering and persistence (issues 03/07, both wontfix) and is a separate feature.
- Grid Fit mode only. Viewport mode (issue 09) shares the same preview branch and would inherit the transform for free, but it is deliberately not wired up: placing the players' window on the map is an orientation task where seeing the whole map is the point.
- The suggested-snap threshold is unaffected — 0.25 squares absolute is computed on the derived value, not on screen distance.
- Panning is clamped so the image keeps covering the preview on any axis large enough to fill it, and stays centered on any axis that is not. This is not a precision requirement — it just stops the map being dragged off into dead space — and it does not conflict with the accepted drift of the fit square, which is about zoom/pan moving the *square* out of view.

Implementation note: the preview transform is currently implicit — `fittedRect` *is* the transform, permanently at `min(...)` scale — and the screen-to-map ratio is re-derived independently in four places (`GridFitOverlay`, `ViewportOverlay`, `ViewportMath`, `ScaleMath`). Make it explicit as a pure `PreviewTransform` value type (scale + offset, owning the `imagePoint(from:)` / `viewRect(of:)` inverse pair that is private to `GridFitOverlay` today), unit-tested in the established style of `GridFit` / `ViewportMath` / `ScaleMath`, with `GridFit.fittedImageRect` becoming its initial state rather than its permanent one. `ViewportOverlay` keeps taking a plain fitted rect.

Acceptance: on a real VTT map, zooming into one printed grid square and drawing the fit square there yields a visibly tighter squares-wide value than the same square drawn fit-to-window, and the Player Display still measures 1 inch to 2.54 cm on a calibrated display; the preview cannot be zoomed out past the whole map nor in past 1:1; a drawn square stays on its artwork across zoom and pan; plain drag never pans and ⌥-drag never draws.

## Comments

- 2026-08-31 (grilling session): designed via /grilling. Decisions: zoom the Control Window preview, not the Player Display (the player viewport's zoom *is* True Scale, derived from squares-wide — zooming it to set squares-wide is circular); augment the existing flow rather than replace it; scope held to squares-wide only; scroll/pinch + ⌥-drag over click-to-zoom; 1:1 ceiling because image pixels bound the achievable precision; nudge floored at 1 image px; Viewport mode deliberately left out. No ADR — the True Scale invariant is untouched.

- 2026-08-31 (implementation): shipped on `feature/grid-fit-zoom` (PreviewTransform + ScrollWheel, GridFitOverlay/ControlView wiring, 16 unit tests, one UI test). Two-axis review applied. Fixed from review: two chained `.gesture()` calls do not compose in SwiftUI, so the draw gesture shadowed the pan and every ⌥-drag was silently swallowed; and `MagnifyGesture` reports cumulative magnification, which the code compounded against the live scale each frame so a pinch accelerated — it now multiplies the scale the pinch began at and anchors on the pinch's own start location rather than the preview centre. Recorded as scope after the fact: the 1:1 pin for maps smaller than the preview, and the pan clamp.

  Two failures that only surfaced by driving the real app, both invisible to unit tests because every button kept working and only the pixels stood still: an `NSViewRepresentable` scroll catcher placed in Grid Fit's `.position()`-based ZStack never gets a non-zero frame, so it never reaches a window and never receives events (replaced with a local `NSEvent` monitor scoped to the view's global frame); and a `hitTest` override returning nil — added to stop that catcher stealing clicks — also muted `scrollWheel`, which routes through hit-testing. The zoom is now covered by a UI test that compares rendered pixels.

  Known gap: ⌥-drag panning has no automated test. XCUITest's `perform(withKeyModifiers:)` does not hold the modifier across `press(forDuration:thenDragTo:)`, so the test failed against code verified working by driving the real app with synthetic ⌥ key events. The pan math is unit tested; the gesture wiring is not. Also unverified on real hardware: trackpad pinch, which has no synthetic-event equivalent — worth a human check.
