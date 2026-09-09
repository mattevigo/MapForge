# 01 — The isolated Pawn

Status: done

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

## Comments

**Blackout has no state to test against.** Acceptance asked that Blackout leave the mode
alone. There is no blackout property on `AppState` — the CONTEXT.md term is implemented
only as far as a comment on `chosenDisplay`. Nothing in this feature can break it, and a
test asserting an interaction with a feature that does not exist would be a fake one. Left
untested deliberately; it becomes a real acceptance criterion when Blackout is built.

**Two lifetime rules were wrong in review and are now fixed.**

- *Hiding the isolated Pawn stranded the mode.* The eye takes a Pawn out of the lighting, so
  hiding the subject left Solo Sight pointing at something that emits nothing: the fog fell
  back to lighting the Map with every torch while the token rule kept the rest of the party
  under the discovery test — a lit Map with most of the party missing from it — and the
  control is disabled on a hidden Pawn, so the DM could not click their way out.
  `setPawnHidden` now ends the mode when it hides its subject.
- *The Map-switch clear was incidental.* It fell out of `fog`'s didSet only because Pawn IDs
  are UUIDs and the incoming Map's would not match. `loadMap` now clears it outright, before
  the document changes.
