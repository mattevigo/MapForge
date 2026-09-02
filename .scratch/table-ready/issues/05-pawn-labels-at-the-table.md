# 05 — Pawn labels at the table

Status: ready-for-agent
Blocked by: 01

Make a Pawn's label editable during live play, and legible at the sizes it is actually rendered. The label already exists end to end — model, both render surfaces, an inspector field, undo — but it is unreachable when the DM needs it and invisible at typical zoom.

## What exists

- `Pawn.label: String` — `FogDocument.swift:116-136`, non-optional, required at init.
- Auto-assigned at placement as `"\(pawns.count + 1)"` — `FogOverlay.swift:334`.
- Rendered inside the token disc by `PawnToken` — `PawnToken.swift:9-39` — on the Player Display (`PlayerView.swift:43-48`), the live Control mirror (`PawnLayer.swift:25-30`) and the fog overlay (`FogOverlay.swift:192-208`).
- Editable via a `TextField` in `ControlView.pawnInspector` — `:384-410` — undoable through `FogEdits.setPawnLabel` (`FogEdits.swift:111`).

## The three gaps

**1. Unreachable at the table.** The inspector appears only when `mode == .fog` **and** `tool == .pawns` **and** a Pawn is selected. During play the DM is in normal mode, where `PawnLayer` offers drag-to-move and nothing else — no selection, no label edit. Renaming means leaving the table view for authoring mode.

**2. Invisible when small.** `PawnToken.swift:25` suppresses the label entirely below a 16pt diameter, but all three call sites floor the diameter at 10–12pt. At low zoom, or with no Grid declared, Pawns render as unlabelled coloured dots — on the Player Display too. This is arguably the real defect behind "pawns should have labels": they have them, and they cannot be seen.

**3. Colliding numbers.** `pawns.count + 1` reuses an existing label after a delete — place three, delete the second, and the next Pawn is also "3".

## What to build

**Live editing, from the light-toggle row.** `ControlView.lightToggles` (`:453-490`) already lists every Pawn by label as a button title and is already the live-play control surface. Make those labels editable in place.

Deliberately **not** a double-click on the token in `PawnLayer`. That layer owns the drag gesture, and gesture composition in this render layer has produced four defects already; adding a competing double-click there is the risky option for a marginal gain in directness. If issue 01 finds the existing gesture layer healthy, a token-anchored popover becomes a reasonable follow-up — but not before.

**A live edit is not undoable.** It writes straight to `AppState.fog`, exactly as `AppState.movePawn` (`:217-220`) does, and for the same stated reason: `CONTEXT.md` holds that acting on a Pawn during play is a live action while editing one during authoring is an edit. The fog undo stack is mode-local and cannot unwind past what the mode opened with, so a live edit has no stack to land in. Add a sibling to `movePawn` rather than routing through `FogEdits`.

The existing in-mode `pawnInspector` path is untouched and stays undoable. Two paths with different undo semantics is the established pattern here, not an inconsistency.

**Legibility.** Lower the suppression threshold in `PawnToken` and let the text shrink rather than vanish — a one- or two-character label reads well below 16pt. `minimumScaleFactor(0.5)` is already there. Pick the floor from what is actually legible on the Player Display at a typical Pawn size, not from a round number.

**Unique labels.** Derive the auto-label from the highest existing numeric label rather than the count, so a delete cannot cause a collision.

## Scope

- The label only. Colour, radii and deletion stay inside Fog editing mode.
- No new gesture on `PawnLayer`.
- No rename prompt at placement time — auto-numbering plus easy renaming is faster than a modal on every drop.

## Acceptance

Mid-session, without leaving the live map, the DM renames a Pawn from "3" to "Goblin B" and it updates on the Player Display immediately. The label is readable on both screens at the Pawn size a real map produces. Placing, deleting and placing again never yields two Pawns with the same label.

## Comments

- 2026-09-02 (grilling session): created via /grilling. The report was "pawns should have labels that are editable"; the session found labels fully implemented and narrowed the request to the live map. The decision to cross the authoring/play boundary for the label — and only the label — is recorded in the feature spec: a rename is a live act of the same kind as a move, so it follows `movePawn`'s non-undoable precedent.
