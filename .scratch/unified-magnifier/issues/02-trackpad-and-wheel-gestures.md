# 02 — Trackpad and wheel gestures

Status: ready-for-agent
Blocked by: 01

A two-finger swipe pans; a pinch zooms on every surface; ⌘-scroll zooms on any device; a wheel
tilted sideways pans. See the spec's **The classifier, stated once**.

## The problem

- `ScrollWheelModifier` (`ScrollWheel.swift:62`) reports only `scrollingDeltaY`, and every
  caller treats it as zoom. A trackpad swipe therefore zooms, and its horizontal component is
  dropped.
- The Live View has no `MagnifyGesture`; only `FogOverlay` (`:311`) and `GridFitOverlay`
  (`:163`) do. Pinch does nothing on the surface the DM uses most.
- Scroll and pinch are handled in three places (the preview, `:700`, and each overlay). With
  one Magnifier after 01, they belong on the preview once, beside the middle-drag that already
  lives there "for all three modes".

## What to do

- Make the classifier a pure function a test can ask, beside `PreviewTransform` — inputs:
  precise deltas or not, ⌘ held or not, dx, dy; output: zoom by a delta, or pan by a size.
  `ScrollWheelModifier` reads `hasPreciseScrollingDeltas`, `modifierFlags`,
  `scrollingDeltaX`/`Y` and hands them over; the momentum phase needs nothing special — it
  arrives as more precise deltas.
- Pan by the precise deltas directly so the artwork follows the fingers (they already carry the
  user's scroll-direction setting). Check the sign by hand on a trackpad; it is the one thing a
  unit test cannot tell you.
- One scroll handler and one `MagnifyGesture` on the preview, acting on the Magnifier in every
  mode. Remove the overlays' own `onScrollWheel` and `magnifyGesture`, and their
  `pinchStart` / `zoomSensitivity` state.
- Keep middle-drag and ⌥-drag exactly as they are.
- A pan over an armed Viewport rectangle moves the Magnifier, never `appState.viewportOrigin`.

## Tests

- The classifier: ⌘ + precise → zoom; ⌘ + line → zoom; precise → pan on both axes; line
  vertical → zoom; line horizontal → pan; line with both → zoom and pan.
- `ScrollWheelHandlerTests` and `PreviewZoomStabilityTests` guard the stale-closure bug and the
  zoom limits; they must still pass.

## Done when

On a trackpad, in the Live View, the Wall Editor, Grid Fit and with the Viewport armed: pinch
zooms at the fingers, two fingers pan and glide to a stop at the artwork's edges, ⌘ + two
fingers zooms, and the Player Display never moves. With a wheel mouse: wheel zooms at the
cursor, ⇧ + wheel pans sideways, middle-drag pans.
