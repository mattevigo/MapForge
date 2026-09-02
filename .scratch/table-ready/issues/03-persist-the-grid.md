# 03 — Persist the Grid in the fog file

Status: ready-for-agent

Store the Map's Grid alongside its fog, so a relaunch returns a DM's Grid Fit result instead of making them redo it. `<map>.fog.json` becomes version 2 and gains the Grid. See [ADR 0003](../../../docs/adr/0003-grid-in-the-fog-file.md).

This is the only substantial build in the feature.

## Why the fog file

`Light.brightSquares` and `dimSquares` are stored in **Grid squares**; a Pawn's range likewise. The Grid was stored nowhere. So the fog file already persisted a measurement without its unit — a relaunch gave back Lights whose radii meant nothing, which is why `AppState.litRegions` returns `[]` without a declared Grid (`AppState.swift:201`) and why `ControlView.undeclaredGridWarning` exists (`:438`).

The comment at `FogDocument.swift:62-68` explaining why the Grid is *not* here must be replaced with a pointer to the ADR.

## What to build

**Model** — add to `FogDocument` (`FogDocument.swift:69`):

- `version` goes to `2`.
- The Grid: `squaresWide: Double?` and the declared flag. A single optional carries both — `nil` means undeclared — which is preferable to two fields that can contradict each other. `hasDeclaredGrid` in `AppState` stays as it is; only the serialised form collapses.
- Version 1 files decode with the Grid absent. Synthesised `Codable` handles this for free if the property is optional; assert it in a test rather than assuming.

**`isEmpty`** — `FogDocument.isEmpty` (`:80`) drives file deletion in `FogStore.save` (`:57-62`). A document with a Grid and no fog is **not** empty: a DM who fits the Grid and stops must get that back. Update the predicate and test it, or the Grid is silently discarded in exactly the case that matters most on a fresh map.

**Load** — `AppState.loadMap` (`:162`) currently sets `hasDeclaredGrid = false` and carries `squaresWide` over from the previous Map. It must instead restore both from the loaded document via `restoreGrid(squaresWide:wasDeclared:)` (`:30`), which already exists for Grid Fit's Cancel and is exactly the right entry point — it sets the value without counting as a declaration.

**Save** — `squaresWide.didSet` (`:10-19`) must reach the autosave. `AppState.fog`'s `didSet` already schedules a debounced write (`:40-45`), so the Grid needs to live in `AppState.fog` or be pushed into it on change. Note `didSet` is deliberately not guarded by `!= oldValue` — typing the default 30 must still declare the Grid, a defect already fixed once. Do not reintroduce that guard.

Watch the write rate: `ControlView.swift:99-104` writes `squaresWide` on **every drag tick** of the Grid Fit square. The 0.5s last-wins debounce in `FogAutosave` absorbs this, but confirm a drag produces one write and not fifty.

**Cancel** — `cancelGridFit()` (`ControlView.swift:354`) restores the previous value and declaration. With persistence, it must not leave a cancelled value on disk; `flushPendingFogWrites()` is the existing tool, used the same way `cancelFogEditing()` uses it.

## Scope

- `squaresWide` and its declared flag only. No rotation, no gridless direct physical width — `map-presenter` issue 03 stays `wontfix`.
- No Calibration. "Depends on the screen" is a per-display correction factor, not a per-Map Grid; it is out of scope for this feature entirely. See the feature spec.
- No migration tooling. Version 1 files simply load without a Grid.
- The file keeps the name `.fog.json` despite now holding more than fog. Renaming would strand every file already written beside a Map.

## Acceptance

Fit the Grid on a Map, quit, relaunch, reopen the Map: the Grid is back, the undeclared-Grid warning is absent, Lights render at their authored radii, and a ruler check on the Player Display still measures 1 inch to 2.54 cm. A Map with a Grid and no fog keeps its `.fog.json`. An existing version 1 file loads without error and gains a Grid once one is fitted.

## Comments

- 2026-09-02 (grilling session): created via /grilling. The reported request was "grid fit should persist depending on the screen"; the session established that the per-screen half is Calibration and a separate feature, while the per-Map half is this. Reverses the written decision in `FogDocument.swift` that kept the Grid out of the fog file — recorded as ADR 0003, on the grounds that Light radii in squares had already broken the separation.
