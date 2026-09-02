# 04 — Remove Grid snapping

Status: ready-for-agent

Stop Walls and Lights snapping to Grid intersections. Keep endpoint snapping. Pawns already do not snap and are unchanged.

## The three mechanisms, and which one goes

`WallSnap.snap()` (`WallSnap.swift:27-40`) is the only grid-quantisation primitive in the app, and it does two different jobs behind one name:

- **Endpoint snap** (`:29-31`) — a vertex within tolerance of an existing Wall endpoint welds to it. **Keep.** This is what makes a hand-traced room watertight; `testATracedRoomIsWatertight` (`WallChainTests.swift:106-135`) draws a room with five deliberately sloppy clicks and proves via `Visibility.compute` that no light leaks. It is also not "the Grid" in any sense a DM would perceive.
- **Grid snap** (`:32-38`) — a vertex rounds to a multiple of `gridPixels`. **Remove.** This is what the DM asked to stop. It welds geometry to a lattice that, until issue 03, did not survive a relaunch.

Separately, `WallSnap.constrainAngle()` (`:68-78`) quantises the *direction* of a chain segment to 45°, on by default, ⇧ frees it. It is not snapping to anything, but "the wall will not go where I point" feels identical. **Untouched by this issue** — issue 01 is establishing whether it is implicated, and if it is, that is a follow-up decision about the default, not a removal.

## What to change

- `WallSnap.snap` loses its grid branch and its `gridPixels` parameter, becoming endpoint-snap only. The `Result.target` enum loses `.grid`.
- `FogOverlay.snapped(_:)` (`:355-357`) — the Light path, which passes an empty candidate list so *only* the grid branch could ever fire. With grid snap gone this function does nothing; delete it and its two call sites (`:179` drag, `:346` placement) place raw points.
- `FogOverlay.resolve(viewPoint:)` (`:301-308`) — keeps the angle constraint and endpoint snap, drops `gridPixels`.
- `ControlView.gridPixels` (`:331-336`) exists solely to feed snapping. Remove it unless issue 02's de-emphasis work or a grid overlay wants it.
- `snapIndicator` (`FogOverlay.swift:259-272`) loses its secondary-colour grid case; the green endpoint ring stays.
- The Walls hint text (`FogOverlay.swift:22`) and the Lights hint (`:24`) must stop implying grid snapping.

## The Light select-click guard

`FogOverlay.swift:176` — `guard value.translation != .zero else { return }` — exists because clicking an unsnapped Light used to silently snap it onto the Grid (a fixed defect, recorded in `fog-of-war` issue 03). With grid snap gone the original bug cannot recur, but the guard also stops a select-click writing a no-op undo entry. **Keep it**, and keep its comment accurate to the new reason.

## Tests

- `WallSnapTests.swift` — delete `testSnapsToAGridIntersection` (`:49-54`), `testNoGridDeclaredMeansNoGridSnapping` (`:56-63`), `testAGridIntersectionOutOfRangeDoesNotPull` (`:65-69`). Endpoint and angle tests stay.
- `WallChainTests.swift:106-135` `testATracedRoomIsWatertight` passes `gridPixels: 50`. It must be reworked to prove watertightness through **endpoint snap alone** — which is the honest test of the property anyway, since a real room is traced over artwork that does not align to the lattice. If it cannot pass without grid snap, that is a finding worth surfacing before deleting anything.
- Add the coverage the explorer found missing: a test that Lights are **not** snapped, and that Pawns are not either. Both are currently unasserted.

## Scope

- Walls and Lights only. Pawns already place free-form (`FogOverlay.swift:331-338`) by an explicit decision in `fog-of-war` issue 04.
- No modifier-key toggle to re-enable Grid snap. The DM said "never"; a toggle is more code for a behaviour they do not want.
- Existing Walls and Lights already on disk keep their snapped coordinates. There is no un-snap pass, and none is wanted — geometry stays welded to the artwork it was drawn over.
- The 45° angle constraint keeps its current default.

## Acceptance

On a Map with a declared Grid, a Wall vertex and a Light land exactly where clicked, with no pull toward lattice intersections. Tracing a room by clicking near previous endpoints still produces a watertight room with no light leak. `testATracedRoomIsWatertight` passes without any grid.

## Comments

- 2026-09-02 (grilling session): created via /grilling. The report was "walls, lights and pawns should never snap to the grid". The session separated the three mechanisms sharing that description and established that only grid snap goes: endpoint snap is load-bearing for the visibility model, and Pawns never snapped in the first place.
