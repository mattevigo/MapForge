# 05 — Visibility engine

Status: ready-for-agent
Blocked by: 02, 03

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
