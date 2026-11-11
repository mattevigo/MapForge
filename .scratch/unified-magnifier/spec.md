# Unified Magnifier: one zoom, the same gestures everywhere

Status: closed 2026-09-29 — all three issues done; green suite, verified by hand on a trackpad and a wheel mouse

The Control Window's zoom behaves differently depending on which surface is up, and it
cannot be driven from a trackpad the way a Mac user expects. Today:

| | Live View | Live View, Viewport armed | Wall Editor | Grid Fit |
|---|---|---|---|---|
| Wheel zooms | yes | yes | yes | yes |
| Trackpad pinch zooms | **no** — no `MagnifyGesture` attached | **no** | yes | yes |
| Middle-drag / ⌥-drag pans | yes | yes | yes | yes |
| Zoom kept across visits | kept | **thrown away on arming** | **reset on entry** | **reset on entry** |
| Hint mentions zoom / pan | zoom | neither | neither | both |

The zoom is three separate transforms — `liveZoom`, `fogTransform`, `gridFitTransform`
(`ControlView.swift:31-56`) — and the Wall Editor and Grid Fit each carry their own scroll and
pinch handlers (`FogOverlay.swift:97-98`, `GridFitOverlay.swift:86-87`) beside the Live View's
(`ControlView.swift:700`). And a two-finger trackpad swipe arrives as the same `scrollWheel`
event as a mouse wheel, so today it **zooms** everywhere (`ScrollWheel.swift:62`) — the
opposite of what a trackpad user's fingers expect.

See `CONTEXT.md`, **Magnifier**, for the settled vocabulary. It was rewritten for this feature:
the Magnifier is now the Control Window's zoom, not the Live View's.

## The shape of it

**One Magnifier for the whole Control Window.** The Live View (Viewport armed or not), the Wall
Editor and Grid Fit read and write the same zoom and pan. The DM who zooms into the tavern and
opens the Wall Editor is still looking at the tavern, and still is after closing it.

**The same gestures on every surface:**

| | Zoom | Pan |
|---|---|---|
| Wheel mouse | vertical wheel | tilted wheel / ⇧ + wheel, middle-button drag, ⌥-drag |
| Trackpad | pinch | two-finger swipe, with momentum |
| Magic Mouse | ⌘-scroll | swipe on its surface |
| Any device | ⌘-scroll | ⌥-drag |

## Rules worth stating once

- **Only two things end the Magnifier:** opening a different Map, and zooming back out to its
  floor (the whole Map). Arming the Viewport, entering or leaving the Wall Editor or Grid Fit,
  Cancel in either, committing a new Grid, and opening or closing the Log View all leave it
  where it is. Cancel undoes *edits*; where the DM was looking is not an edit. A new Grid does
  not change the image's pixels, so the transform stays valid. A window resize only re-clamps
  it against the artwork's edges, as `settled(in:)` already does.
- **This reverses "open on the whole Map".** `startFogEditing` (`ControlView.swift:856`) and
  `startGridFit` (`ControlView.swift:1296`) both reset to fit on purpose: *"the zoomed-out view
  orients, and zoom is opt-in for the precision moment."* That reasoning assumed each mode had
  its own zoom to opt into. With one, the DM chose their magnification before entering, and
  zooming out is one gesture away. The comments go with the reset.
- **Arming the Viewport no longer zooms out.** `ViewportToggle.endsMagnifier` exists for a
  "Zoomed" affordance and a cropped mirror that are both gone; the rectangle is drawn against
  the magnified artwork (`fitted`) and stays true at any zoom.
- **Panning never moves the Viewport.** A swipe, middle-drag or ⌥-drag over an armed rectangle
  slides the DM's view, not the table's. Moving the Viewport stays a deliberate primary-button
  drag — a swipe is too easy to make by accident in front of the players.
- **The classifier, stated once.** A scroll event is:
  - **zoom** if ⌘ is held (any device), using its vertical delta;
  - **pan** if it has precise deltas (trackpad, Magic Mouse), both axes, including its momentum
    phase;
  - otherwise, from a line-based wheel: **zoom** on its vertical delta, **pan** on its
    horizontal delta.

  Precise deltas already carry the user's scroll-direction setting, so the artwork follows the
  fingers the way any Mac scroll view does.
- **Zoom stays cursor-anchored** for the wheel and ⌘-scroll, and anchored where the pinch
  began for a pinch, as both already are. Sensitivity is unchanged (`exp(delta * 0.01)`,
  line deltas ×10).
- **At the floor there is nothing to pan**, as today — `panned` stops at the artwork's edges.

## What this deliberately excludes

- **Persisting the zoom.** Still never persisted, per `CONTEXT.md`.
- **Smart zoom** (two-finger double-tap). Not asked for; file it separately if wanted.
- **A preference for scroll behaviour.** ⌘-scroll covers the one device the classifier leaves
  without a zoom.
- **Anything on the Player Display.** The Magnifier is the DM's alone; nothing here changes
  what the table sees.

## Known edge

Third-party wheel mice whose drivers smooth scrolling (Logitech Options and the like) may report
precise deltas and would therefore **pan** rather than zoom. ⌘-scroll still zooms for them. Not
worth a heuristic until a DM reports it.

## Issues

1. `issues/01-one-magnifier.md` — one shared transform; no reset on mode entry or arming.
2. `issues/02-trackpad-and-wheel-gestures.md` — the classifier, pinch on every surface,
   ⌘-scroll, sideways wheel. Depends on 01.
3. `issues/03-hints.md` — the hint row says it once. Depends on 02.
