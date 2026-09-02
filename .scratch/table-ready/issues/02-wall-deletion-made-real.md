# 02 — Wall deletion, made real

Status: needs-info
Blocked by: 01

Make deleting a placed Wall work, and make it evident. The model layer and the key handler already exist and are tested; what is unproven is whether the gesture reaches them, and what is certainly missing is any signal to the DM about why a click did nothing.

`needs-info` until issue 01 reports: the fix is a bug fix or an affordance change depending on what it finds, and possibly both.

## What exists

- `FogEdits.deleteWall(id:)` — `FogEdits.swift:44-48`, records undo, tested by `testUndoRestoresADeletedWall`.
- `deleteSelected()` — `FogOverlay.swift:373-384`, a Wall → Light → Pawn cascade behind `.onKeyPress(.delete)` (`:111`). U+007F is macOS backspace, so one registration covers ⌫.
- Wall selection — `FogOverlay.swift:136`, a `TapGesture` per Wall, hit area widened to a 12pt stroked path (`:127-130`) because a 2.5pt line is unclickable.
- The hint text already says "click a Wall then ⌫ to delete" (`FogOverlay.swift:22`), rendered at `ControlView.swift:68`.

## If issue 01 finds the gesture dead

Fix the wiring. Likely suspects in order: the child `TapGesture` losing to the parent's `exclusively` chain; `@FocusState` not being set when the overlay has not yet been clicked, so `.onKeyPress` never fires; `.allowsHitTesting` false because `chain.isDrawing` is stuck true after a cancelled chain.

Whatever the cause, it gets a UI test under issue 06 — this layer's defects are unreachable from the unit suite by construction.

## If issue 01 finds it working but unfindable

Two changes, both small:

- **De-emphasise inactive object kinds.** All Walls, Lights and Pawns are always drawn, but only the active tool's kind is clickable. That is invisible, and it makes a click on a Wall while the Pawns tool is active look like a broken feature. Render the inactive kinds at reduced opacity so "not clickable right now" is something the DM can see.
- **Hover feedback on Walls.** With the Walls tool active, a Wall under the pointer highlights, so the DM knows what they are about to select and that Walls are clickable at all.

## Scope

- No new deletion affordance — no context menu, no eraser sub-mode, no delete button. Select-then-⌫ is the established pattern across all three object kinds and it stays.
- No "clear all Walls". Undo and Cancel remain the coarse escape hatches.
- The four implicit boundary Walls (`Visibility.boundaryWalls`) stay non-selectable and non-deletable, per the fog spec.
- Deletion stays inside Fog editing mode. The live map gets no delete.

## Acceptance

On a real map: clicking a Wall with the Walls tool active highlights it, ⌫ removes it, Undo brings it back, and the change survives to `.fog.json`. With a different tool active, Walls are visibly de-emphasised rather than silently inert.

## Comments

- 2026-09-02 (grilling session): created via /grilling. The DM reported wall deletion as missing; the code has it. Whether that is a runtime defect or a discoverability failure is issue 01's job — the two feel identical from the DM's chair and have opposite fixes.
