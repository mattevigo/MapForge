# 05 — Pawn labels at the table

Status: wontfix

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

## Landed (2026-09-02, implementation pass)

The three parts the spec pins independently of issue 01 are built and tested. What remains
is genuinely gated on 01's findings.

- **Live editing, from the light-toggle row.** `ControlView.pawnLiveRow` replaces the bare
  Pawn toggle with a `PawnToken` toggle plus an in-place `TextField`. Writes go to
  `AppState.setPawnLabel`, a sibling of `movePawn`, **not undoable** — the crossing the
  spec sanctions, for the reason it gives. The in-mode `pawnInspector` path is untouched
  and stays undoable through `FogEdits`.
- **Legibility.** `PawnToken.showsLabel(atDiameter:)` lowers the floor from 16 pt to 8 pt,
  below every diameter the three call sites actually produce (10–12 pt), so a Pawn is no
  longer an unlabelled dot at low zoom or with no Grid declared. `minimumScaleFactor(0.5)`
  was already there and now does the work. The floor is a named, tested predicate rather
  than a bare literal in the view.
- **Unique labels.** `Pawn.nextLabel(after:)` counts from the highest existing *numeric*
  label rather than `pawns.count`, so a delete cannot cause a collision and a renamed Pawn
  does not block the numbering.

Covered by `MapForgeTests/PawnLabelTests.swift` (7 tests) and three live-rename tests in
`AppStateFogTests`.

**Not done:** the token-anchored popover the spec floats as a follow-up "if issue 01 finds
the existing gesture layer healthy". Issue 01 found the gesture layer healthy — the defect
was focus, not gesture composition — so this is no longer blocked. It remains out of scope
for this pass, and the caution that chose the live-row `TextField` over a `PawnLayer`
double-click is vindicated rather than weakened: that layer is where focus and gesture
composition have now produced five defects. Nothing was added to `PawnLayer`, per scope.

## Closed 2026-09-02 — wontfix

Everything the issue specified is built: live renaming from the toggle row, the legibility
floor, and unique auto-labels. Dropped is only the token-anchored popover the issue floated
as a conditional follow-up.

Issue 01 unblocked it — the gesture layer is healthy, the defect was focus — but the
condition being met is not a reason to build it. The live-row field already solves the
problem the popover would solve, and `PawnLayer` is where focus and gesture composition
have now produced five defects. A second, competing gesture there buys directness the DM
has not asked for at a risk this codebase has measured five times.

## Comments

- 2026-09-02 (grilling session): created via /grilling. The report was "pawns should have labels that are editable"; the session found labels fully implemented and narrowed the request to the live map. The decision to cross the authoring/play boundary for the label — and only the label — is recorded in the feature spec: a rename is a live act of the same kind as a move, so it follows `movePawn`'s non-undoable precedent.
