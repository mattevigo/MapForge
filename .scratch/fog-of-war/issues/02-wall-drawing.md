# 02 — Wall drawing and snapping

Status: ready-for-agent
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
