# 03 — Drawing the shape and the readout on both screens

Status: ready-for-agent
Blocked by: 01, 02

Green translucent fill, solid green border, a distance readout — on the Control mirror and
the Player Display. **Read ADR-0005 first**: the table seeing the number is a deliberate
breach of a rule that held for four features, and the reasoning constrains what else may go
on that screen.

## Where it goes

Both screens already have the seam, and both already use `PlayerPlacement.viewPoint` with a
frame that carries the pan.

- **Player Display** — a sibling of `FogCanvas`/`LightMarker` in `PlayerView.swift`'s
  `ZStack`, between the `FogCanvas` (`:35`) and the Light Marker `ForEach` (`:48`): above the
  fog, below the tokens. A Measurement is not hidden by darkness — the DM drew it to be seen.
- **Control mirror** — a third `.overlay` in `ControlView.swift` beside the `FogCanvas`
  (`:215`) and `PawnLayer` (`:228`) ones, passed the identical rebased frame used verbatim at
  `:222-224` and `:233-235`. Get this wrong and the shape sits at an offset from the Pawn it
  is anchored to.

One view, both screens, differing only in the frame handed to it. Two drawing paths is how
the screens drift, which is the divergence `PawnToken` and `PlayerVisibility.showsToPlayers`
both exist to prevent.

## Style

"Translucent fill + solid border" has two precedents — `GridFitOverlay.swift:48-50` and
`ViewportOverlay.swift:32-34`. Follow their shape, in green.

`Polygon` → `Path` already exists privately at `FogCanvas.swift:90-100`. Lift it rather than
writing a second one.

`.line` strokes rather than fills.

## The readout

Fixed-size chrome, following `GridFitOverlay.swift:71-77` — a `.thinMaterial` capsule pinned
near the shape — **not** `PawnToken`'s map-scaled text. A distance is a fact about the world,
not an object in it, and map-scaled text on a True Scale display is illegible on a large Map
and enormous on a small one. ADR-0005 records this.

Text per issue 01: "6 m radius", "6 m across", "9 m".

Place it so it stays on screen when the shape runs off the edge of the Player Display.

## Gotchas

- `.allowsHitTesting(false)` on both overlays. Every non-interactive overlay in this codebase
  does it (`FogCanvas.swift:36`, `LightMarker.swift:43`), and an overflowing view owns its
  full frame for hit-testing — it would eat the right-click from issue 02.
- Hoist `appState.litRegions` if you read it — it is a *computed* property and per-token
  reads at drag rate were a real regression (`ControlView.swift:242-250`,
  `PlayerView.swift:44`). This overlay should not need it at all, since Walls do not block a
  Measurement.
- Do not add anything to the Control Window's outer `VStack` that appears and disappears —
  it resizes the `GeometryReader` the preview transform is measured against and the map
  visibly jumps (`ControlView.swift:81-97, 504-506`).
- The Measurement redraws on every hover tick. Keep the projection out of the view body.

## Tests

Geometry is covered by issue 01; here, verify placement and parity:

- The same Measurement projects to the same map-space polygon for both screens' frames.
- The readout string matches the shape (the "radius" vs "across" distinction).
- Rebased-frame correctness: an anchored Measurement's apex sits on its Pawn's centre in the
  mirror.
- A UI test that a Measurement appears and is dismissed, following
  `MapForgeUITests/FogEditingUITests.swift`.

## Done when

Specs 1–5 and 7 are usable end to end: right-click, see the shape and the distance on both
screens, right-click to dismiss.
