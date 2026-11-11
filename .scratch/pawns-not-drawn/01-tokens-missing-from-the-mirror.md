# 01 — Pawn tokens are not drawn on the Control Window's preview

Status: done

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

## Comments

**Fixed.** The cause was none of the three candidates above, and the report's own framing —
"not drawn on the Control Window's *mirror*" — is what hid it.

`ControlView.preview` has two branches. The **mirror** branch draws the Pawns, and is guarded
on `resolvedViewport != nil`. `resolvedViewport` (`ControlView.swift:237-244`) returns nil
unless `playerMetrics` **and** `playerScreen` are both present — that is, unless a Player
Display is connected. With nothing plugged in the view falls through to the **fitted** branch,
which drew the Image plus whichever editing overlay the mode wanted, and no `PawnLayer`,
no `FogCanvas` and no `MeasurementLayer` at all.

So the Pawns were never missing from the mirror. The mirror was never running. Every symptom
follows: the fog file is correct, the Scene tab lists the Pawns, the Initiative Tracker rolls
for them, and the preview is bare artwork — because the branch that draws tokens is the branch
that needs an HDMI screen, and the DM was prepping on a laptop.

`mirrorFrame` was a red herring, and so was `squareSidePoints`. A first pass wrote four
geometry tests against the frame-overflows-container theory; all four passed, which is what
sent the search to the branch condition. Those tests were replaced rather than kept — they
asserted true things that had nothing to do with the defect.

**The fix.** A new `PreviewBranch` (`MapForge/PreviewBranch.swift`) states, once and testably,
when the preview owes the DM the live layers and which frame they are placed against — pure
policy beside `SoloSightControl` and `MeasurementControl`, for the same reason those exist.
`drawsLiveLayers` is conditional on the *mode*, never on a Player Display: the editing modes
draw their own overlays and `FogOverlay` already draws its own Pawns, so stacking would double
every token.

`ControlView` gained a `liveLayers(map:frame:)` shared by both branches, so they cannot drift
apart again. `PreviewMode` was lifted out of `ControlView` to file scope so the policy can be
asked about a mode without standing up the view.

**Two things worth knowing for next time.**

`--test-player-screen auto` is why no UI test caught this. Every existing test passes it, so
every existing test exercised the branch that worked. `PreviewWithoutDisplayUITests`
deliberately omits it, and fails when the fix is reverted — checked, not assumed.

`PawnLayer` now sets `pawn-token-<label>`. A `PawnToken` is a `ZStack` that publishes as one
accessibility element, so its label `Text` is not separately queryable — without an identifier
on the token, "the preview draws nothing" and "the preview draws everything" look identical to
XCTest. That is the gap this bug lived in.

Verified by hand in the running app with no Player Display attached: two Players, a Big
Creature, a Light Marker and the Fog tint all drawn, and the Scene panel agreeing.

- 2026-09-14: verified at the table. Running a real fight exercised this directly — the
  tokens are drawn, and dragging one writes to the Combat Log, which is what issue 07 of the
  Initiative Tracker could not be checked without. Closed.
