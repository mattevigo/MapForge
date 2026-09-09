# 01 — The isolated Pawn

Status: ready-for-agent

Hold the identity of the Pawn currently under Solo Sight, and give it a lifetime that
cannot outlive the document it points into.

## What to build

**State** — `AppState` gains `private(set) var soloSightPawnID: Pawn.ID?`, `@Published`,
**not persisted**. It sits beside `isFogOverlayOn` (`AppState.swift:228`), which is exactly
this shape already: live, read by both windows, reset on launch.

**Writer** — a sibling of `setPawnHidden` (`AppState.swift:399-404`): takes the value
rather than toggling, is **not undoable**, and does not touch `liveEdits`. Solo Sight
changes no Pawn, so there is nothing for `carryLiveState` to carry.

**Lifetime.** The ID is a reference into a `FogDocument` that can change underneath it, so
it clears on:

- **Map switch** — the `be14e58` bug class. Wherever `endFogEditing()` is called from
  `.onChange(of: appState.mapURL)` (`ControlView.swift:127-147`), the ID clears too.
- **The isolated Pawn being deleted** — and lookup by ID must fail safe regardless, so a
  stale ID makes the mode inert rather than crashing or isolating a stranger.
- **Entering fog editing** — fog authoring needs the whole Map lit, and the mode would
  fight the inspector.

It **survives Blackout**: blackout hides the Map, and restoring it should restore the view
the DM had set up.

## Scope

- One optional ID. Not a set — multi-Pawn isolation is out of scope, and `Pawn.ID?` is a
  strict subset of `Set<Pawn.ID>` if that ever changes.
- No persistence, no undo, no sidecar changes. `FogDocument` is untouched by this issue.

## Acceptance

Setting and clearing the ID publishes to both windows. Switching Map clears it. Deleting
the isolated Pawn clears it, and a stale ID reaching the render path leaves the mode inert.
Entering fog editing clears it. Blackout and un-blackout leave it alone. Nothing appears in
the fog undo stack, and no `.fog.json` is written as a result of any of it.
