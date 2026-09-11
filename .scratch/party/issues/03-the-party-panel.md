# 03 — The Party group in the Control Window

Status: ready-for-agent

Depends on: 01, 02

Where the roster is seen and edited: a group at the top of the existing `livePanel`, above
Lights.

## Build

**The group.** `ControlView.livePanel` (`ControlView.swift:1060`) is a 236 pt column built
from `liveGroup(_:count:content:)` (line 1100). Add the Party group as its first child, reusing
`liveGroup` rather than inventing a second heading style. It follows the panel's existing
rule: no Parties defined, no group — and, as today, the whole panel stays hidden when there is
nothing at all to show.

**The Party picker.** At the group's head, naming the active Party. Its menu ends with the
roster actions: **New Party…** (created empty, becomes active), **Rename Party…**,
**Delete Party**. Deleting a Party touches no Pawn on any Map — see ADR 0007. Deleting the
last one leaves the group hidden.

**Character rows.** One per Character in the active Party, in the Party's own order. Each row
carries, in the idiom of `pawnLiveRow` (`ControlView.swift:931`):

- a `PawnToken` swatch, as that row already uses for its torch toggle's label — the Character
  should look like the Pawn it stamps
- the name
- the **placed count**: how many Pawns on the *current* Map carry this `characterID`. Show it
  only when non-zero; a plain "×2"-style badge, or the count badge `liveGroup` already uses.
  This is the only reader of `characterID` in the app. It is decoration — it forbids nothing,
  and duplicates are expected (ADR 0007).

**Inline authoring.** A "+" on the group header appends an editable row: name `TextField`,
`ColorPicker` (no opacity), sight `TextField`, "Big" `Toggle` — the same four controls
`pawnInspector` uses (`ControlView.swift:830-888`), stacked to fit 236 pt. No sheet and no
modal: this app has none, and four fields do not justify the first one. Editing an existing
Character uses the same row. Deleting a Character is in the row's context menu.

Every edit writes through `PartyStore`. These are roster edits, not Map edits: they do **not**
join `FogEdits`' undo history, which is mode-local to fog authoring by construction
(`FogEdits.swift:10-13`).

## Tests

- The group is absent with no Parties, and appears when one is defined.
- Characters render in the Party's order, and the order survives a store round-trip.
- The placed count reflects Pawns on the current Map only, counts duplicates, and drops to
  absent when the matching Pawns are deleted or the Map is switched.
- A Character edit reaches disk.
- Deleting a Character leaves Pawns stamped from it on the Map, fully drawn, and only removes
  the count.

## Done when

A DM can define a Party and its Characters and see them listed. Dragging is issue 04.
