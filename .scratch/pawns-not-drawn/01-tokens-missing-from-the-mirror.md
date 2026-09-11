# 01 — Pawn tokens are not drawn on the Control Window's preview

Status: needs-triage

Found while verifying the Initiative Tracker by hand. **Not caused by that feature**: the
same behaviour is present on the stashed pre-feature tree, checked by building both and
comparing screenshots of the same Map.

## What happens

Place three Pawns with the Pawns tool, leave the editing mode. The Pawns are real by every
other measure:

- `<map>.fog.json` holds all three with sensible image-pixel coordinates, well inside a
  1200×900 image
- the Scene tab lists them as "Players 3" with their coloured token swatches
- the Initiative Tracker rolls for them and runs a fight over them

But **no token is drawn anywhere on the preview**, with the Fog Overlay on *or* off. The
whole mirror is bare map.

## Why it matters

Dragging a Pawn is the app's headline live action, and a token that cannot be seen cannot be
dragged. It also means the movement logging added in
`.scratch/initiative-tracker/issues/07-wiring-the-map-to-the-log.md` cannot be exercised by
hand — its unit tests pass, and the gesture they stand in for has no visible subject.

## Where to look

`PawnLayer` draws tokens at `PlayerPlacement.viewPoint(pawn.at, map:frame:)` inside a
`ZStack(alignment: .topLeading)`, positioned with `.position()`. It is handed `mirrorFrame`
from `ControlView`. Candidates, in the order worth checking:

1. `mirrorFrame` is zero or the wrong rectangle when the layer is built — `.position()` on a
   zero frame puts everything at the origin, under the preview's own clip.
2. The `.overlay { PawnLayer(...) }` is being laid out behind or outside the preview image.
3. `PlayerPlacement.squareSidePoints` returning 0, making every token zero-sized. `max(side, 12)`
   guards the token's own size but not a NaN.

`PlayerPlacementTests` covers the arithmetic and passes, which points at the frame rather
than the maths.

## How it was found

Driving the built app: `open -n MapForge.app --args --test-map <png> --test-squares 30
--test-fresh-preferences`, placing Pawns, then screenshotting the preview. Worth a UI test
that asserts a token is hittable on the mirror — no existing test looks at the preview's
contents, which is why this survived.
