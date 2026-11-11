# 01 — One Magnifier

Status: done

Collapse the three zooms into one, and stop throwing it away. No gesture changes here — the
wheel, middle-drag and ⌥-drag already exist on every surface; this makes them all act on the
same thing.

## The problem

`ControlView` holds three transforms (`ControlView.swift:31-56`): `liveZoom`, `fogTransform`,
`gridFitTransform`. `preview` picks one by mode (`:579-581`), and each is reset at different
moments:

- `fogTransform = nil` on entering the Wall Editor (`startFogEditing`, `:858`).
- `gridFitTransform = nil` on entering and leaving Grid Fit (`startGridFit` / `endGridFit`,
  `:1298`, `:1305`).
- `liveZoom = nil` on arming the Viewport (`viewportToggle`, `:1687-1689`, via
  `ViewportToggle.endsMagnifier`).
- All three on changing Map (`:509-515`) — the one reset that stays.

So a DM zoomed into a room loses it the moment they open the Wall Editor to trace that room.

## What to do

- One `@State` transform for the whole preview (the Magnifier). `GridFitOverlay` and
  `FogOverlay` keep taking `transform` / `onTransform`, but both write the same state.
- Remove the resets on mode entry/exit and on arming the Viewport, with the "open on the whole
  Map" comments that justify them. Keep the reset on changing Map.
- Delete `ViewportToggle.endsMagnifier` and its doc comment; the reason it gives is gone.
- The middle-drag `switch mode` (`:730-734`) collapses to one assignment.
- Rewrite the `liveZoom` doc comment to say what it is now: the Control Window's zoom, shared by
  every mode.

## Tests

- `ViewportToggleTests.testShowingTheViewportEndsTheMagnifier` asserts the old rule — delete it
  with `endsMagnifier`, and replace it with a test that arming leaves the transform alone if
  that rule gets a home in a testable policy.
- `PreviewContainerStabilityTests` already holds that entering a mode does not move a zoomed
  preview; it should still pass unchanged.
- Unit tests only if the app is running in Xcode — UI tests fail with "Failed to terminate"
  against an open debug session.

## Done when

Zoom into a corner in the Live View, open the Wall Editor, Cancel, open Grid Fit, Cancel, arm
the Viewport: the same corner at the same magnification throughout. Open a different Map: whole
Map.
