# 05 — Visibility engine

Status: ready-for-human

The core geometry: given the Walls, Lights and Pawns on a Map, compute Visibility — for every point, whether it is bright, dim or unlit. Pure, testable, no rendering, no GPU. See [ADR 0002](../../../docs/adr/0002-cpu-visibility-polygons.md).

Approach:

- One exact visibility polygon per Light: cast rays at Wall endpoints, sort by angle, build the lit region. Two polygons per Light in practice — one clipped to the bright radius, one to the dim radius.
- Clipped to the Light's radii; combined across all Lights so bright anywhere wins over dim anywhere, and dim wins over unlit.
- Computed in **Map space**, cached, invalidated only when Walls, Lights or Pawns change. **A Viewport pan must never trigger a recompute** — panning is drag-rate, and `map-presenter/09` already cost a round of work on drag smoothness.
- Lives in a pure module beside `ScaleMath` and `ViewportMath`, unit-tested with no rendering context. "Can the players see round that corner" must be right, and is miserable to verify by eye.

Cases that must be tested, not eyeballed:

- A Light exactly on a Wall, and a Light exactly on a Wall endpoint.
- Collinear and overlapping Walls.
- A ray passing exactly through a vertex — the classic source of one-pixel light leaks.
- A closed room with the Light outside it: interior stays fully unlit.
- A chain with a deliberate gap: Light leaks through, and the leak is the shape geometry says it should be.
- The implicit boundary Walls (issue 02) closing every polygon: no Light escapes the image bounds.
- Overlapping Lights: bright beats dim beats unlit, with no seams where two polygons meet.

Scope:

- Hard shadow edges at Walls — a visibility polygon has no penumbra. The only softness is the gradient at each Light's range limit, and that belongs to rendering (issue 06), not here.
- No Metal. Rejected in the ADR: a hand-authored Map has tens of Walls, not thousands, and a GPU in the test path costs more than it buys.
- No third-party dependency. If degenerate cases prove harder than expected, that is the point to reconsider — the ADR says so explicitly.

Acceptance: the case list above passes as unit tests. On a real dungeon map with a traced room and a torch inside it, the corridor outside stays black and the doorway throws a correctly-shaped wedge of light.

## Comments

- 2026-09-01 (grilling session): designed via `/grill-with-docs`. CPU polygons over a shader, and no third-party geometry library — both recorded in ADR 0002 with the conditions for revisiting.

- 2026-09-01 (implemented): `Visibility`, `Polygon` and `VisibilityCache`, 18 unit tests. Built ahead of 02 and 03 — the block on them was only ever for Walls and Lights as *data*, and issue 01 delivered that, so the engine could be proven with hand-built `FogDocument`s and no UI in the way.

  The engine returns polygons per Light (bright and dim) rather than a sampled grid, so a shadow edge lands exactly on the Wall casting it and issue 06 can fill them straight into a Canvas path.

  Two degenerate cases cost real work and are now tested, not assumed. A Light sitting exactly on a Wall endpoint made `atan2(0,0)` undefined and lost the whole far side of the sweep; a Wall touching the Light is now treated as non-blocking, which is also what the geometry says — it casts a shadow of zero width. And rays are cast a hair either side of every vertex, which is what stops the classic one-pixel leak where two Walls meet.

  `boundaryWalls` lives here rather than in the fog file: the four implicit Walls belong to the image, so they are derived at load exactly as issue 01 specified and never stored.

  Performance is measured, not asserted: 80 Walls and 8 Lights compute in ~14 ms, against ADR 0002's bet that a hand-authored Map never needs a GPU. The test names the ADR so a future failure points at the decision to revisit.

  Acceptance met in geometry: a traced room with a doorway throws a wedge into the corridor whose width matches similar triangles to within 2 px at 100 px beyond the door. The "on a real dungeon map" half needs issues 02 and 06 before a human can look at it.

- 2026-09-01 (review): two-axis review found a real bug the case list had asked for and my test had been too weak to catch. A Light sitting exactly *on* a Wall lit nothing at all — `rayHit` returned t≈0 in every direction, collapsing the polygon onto the Wall's own line — while the test only asserted the polygon was non-degenerate, which a zero-area shape with six vertices satisfies. The test now names the requirement (the side the Light is on is lit) and a second test covers the other half (a Wall through a Light still blocks the far side).

  Also added: bright ⊆ dim, which nothing structurally guaranteed since the two radii are swept independently with their own Wall sets, and the "no seams" half of the overlapping-Lights case, which the precedence test could not reach because it used no Walls.

  Two doc defects corrected. The vertex nudge's stated rationale was wrong — its job is escaping the ambiguous corner, not out-running `atan2` error, which is eleven orders smaller — and the dedupe comment described pairs collapsing, which never happens (0.06 px apart at r=3000, against a 1e-9 epsilon). Dedupe does earn its place for genuinely coincident endpoints, which snapping in issue 02 will produce constantly, and it now also closes the wrap-around.
