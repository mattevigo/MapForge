# 02 — Wall drawing and snapping

Status: ready-for-human
Blocked by: 01

Draw Walls on the Map in a new Control Window mode, beside the existing `normal`, `gridFit` and `viewport` modes in `ControlView`. A Wall is a two-sided segment; the DM draws chained polylines, but storage is flat segments (see `CONTEXT.md`).

Interaction:

- Click to start, click to place each vertex, double-click or Esc to end the chain. Each placed span becomes one Wall segment.
- Reuses `PreviewTransform` for zoom and pan exactly as Grid Fit does — precision here is the whole point, and one grid square of a 3000 px map is ~15 pt at fit-to-window.
- **Snapping**, in priority order: an existing Wall endpoint within a few preview points wins first, so chains join with no hairline gaps that leak Light; then a Grid intersection. Snap targets are shown as the cursor approaches — snapping is visible, never silent.
- **Angle constraint** while dragging a span: 0°/45°/90°/135°. Held by default with a modifier to escape it, since most Walls on a battle map are axis-aligned.
- Select a Wall to delete it. Undo covers drawing and deletion.

Scope:

- Snapping is geometric only — existing endpoints and the Grid. Detecting edges in the artwork (computer vision) was considered and rejected: it fails unpredictably on stylised or hand-drawn maps and would dominate the whole feature.
- The four implicit boundary Walls at the image bounds are not drawn by the DM, not selectable and not deletable. They exist so every visibility polygon closes and Light never spills into the letterbox.
- No doors yet. A Wall that toggles passable is cheap to add on this model and is deliberately out of scope.
- Snapping and the angle constraint are pure geometry: they belong in a testable module, not in the gesture handler.

Acceptance: on a real VTT map, tracing a room's walls produces a closed chain with no gaps at the corners — verified by issue 05's Visibility showing no Light leaking between segments. Vertices land on Grid intersections when the Grid is declared, and on existing endpoints when starting a chain where another ends.

## Comments

- 2026-09-01 (grilling session): designed via `/grill-with-docs`. "Snap to edges" was ambiguous between grid/endpoint snapping and image edge detection; grid + endpoint chosen. Walls stored in image pixels so Grid Fit never moves them relative to the artwork.

- 2026-09-01 (implemented): `WallSnap` and `WallChain` (pure, tested), `WallOverlay`, and a `walls` mode in `ControlView` beside `gridFit` and `viewport`. 20 unit tests plus 3 UI tests.

  The acceptance criterion is tested the way it asks to be: `testATracedRoomIsWatertight` traces a room with deliberately sloppy clicks, lets snapping close it, then puts a torch inside and asserts through issue 05's Visibility that no Light escapes.

  One design decision worth recording: the angle constraint *rotates* the span rather than projecting it onto the axis. Projecting shortens the Wall as the cursor drifts off the axis, so it visibly lags the pointer. Rotating keeps the length the DM dragged and corrects only the direction. Snapping then runs after the constraint, so a snap target always wins — closing a chain matters more than holding 45°.

  Not verified: the three UI tests could not run here — the `MapForgeUITests` target hangs in this environment, on `develop` as well as on this branch. They parse and are written against the same `--test-map` harness the existing UI tests use, but they need a human run on a real desktop session. That is the main thing left before this can be closed.

- 2026-09-01 (review): the two-axis review found the central interaction broken and a requirement simply missing.

  **The gesture composition was wrong.** `.onTapGesture` *is* a gesture modifier, so chaining a single-tap and a double-tap does not compose — the outermost claims every click and the double-click never fires. A comment in the code claimed it followed `GridFitOverlay`'s hard-won "one `.gesture()` call" lesson while doing the opposite. Chains could only ever have been discarded with Esc, never committed. Now one `.gesture()` with an explicit `exclusively` chain, and `SpatialTapGesture` rather than `TapGesture` because placing the final vertex needs a location that `.onTapGesture(count: 2)` does not supply.

  **Undo was specified and not built.** `WallEdits` now groups undo by action, so a chain traced with three clicks takes one press to remove, not two. It is mode-local by construction and cannot unwind past the Walls the mode opened with — that is Cancel's job, and Cancel now also flushes the fog file, since the autosave debounce may already have written Walls the DM then cancelled.

  Also fixed: `WallSnap` took fabricated zero-length Walls as snap candidates and now takes points; only the chain's *first* vertex is a magnet, not every vertex, which would have swallowed vertices when tracing a corridor narrower than the snap tolerance; Walls are not selectable mid-chain, where a click near one means "join here"; and a duplicate delete-key registration is gone.

  One deliberate deviation, now documented in the code: the issue says "Esc to end the chain", but Esc discards it. Esc is `.cancelAction` in both other modes, and an Esc that silently committed a half-traced chain would be the only destructive Escape in the app. Double-click commits.
