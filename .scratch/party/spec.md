# Party: define the cast once, drag it onto the Map

A DM re-creates the same player tokens on every Map. Today that means "Edit Fog…" → Pawns
tool → click → type the label → pick the colour → set the sight range, once per character,
once per Map. The party is the one cast that never changes, and it is the one thing the app
made you re-enter every time.

This feature lets a DM define one or more **Parties** of **Characters** once, and place them
by dragging a Character onto the Map preview. See `docs/adr/0007-characters-are-stamped-not-linked.md`
for the decision this rests on, and `CONTEXT.md` for **Character**, **Party** and **Stamp**.

## The shape of it

A **Character** is a name, a colour, a sight range in Grid squares, and whether it is Big.
Always Player-kind. No portrait. It belongs to a **Party**, which has a name. Parties live in
`~/Library/Application Support/MapForge/parties.json`; the active Party is remembered in
`UserDefaults`.

The active Party appears as a group at the top of the Control Window's `livePanel`, above
Lights, with a picker to switch Party and manage the roster. Dragging a Character onto the
ordinary preview **Stamps** a Pawn from it: a copy, placed free-form under the cursor, live
and not undoable, flushed to disk on drop.

## Rules worth stating once

- **Copy, never link.** The Pawn takes the Character's fields at drag time. Editing or
  deleting the Character afterwards changes nothing already on a Map, silently and with no
  prompt.
- **`characterID` is advisory.** It exists so the roster can show a placed-count. Nothing
  draws from it, and a Pawn whose Character is gone is fully functional.
- **Duplicates are allowed.** Stamp the same Character five times and get five Pawns sharing
  a label. No auto-renaming.
- **Free-form placement.** No Grid snapping — consistent with click-to-place, with dragging a
  Pawn, and with Line measurements.
- **Out of bounds is refused.** A drop landing outside the Map image creates nothing.

## Out of scope

Deliberately, so it is not read as an omission:

- **Portraits** on a Character. Reaches into token rendering, True Scale sizing and the
  sidecar format; its own feature.
- **Creature and Treasure libraries.** The pain is the fixed cast. Placing six goblins is
  already served by a new Pawn copying the last one placed.
- **Promoting an existing Pawn** into a Party ("Add to Party…"). A second, redundant entry
  path; a good follow-up.
- **Stamping a whole Party at once.** Needs a multi-token placement rule (row? arc? what
  happens at the image edge?) that is a decision tree of its own hanging off a convenience.
  Five short drags already beats five click-and-fill cycles.
- **Grid snapping**, which is an app-wide question, not this feature's.

## Issues

1. `01-the-party-model.md` — Character, Party, `PartyStore`, active-Party preference.
2. `02-pawn-remembers-its-character.md` — the advisory `characterID` and its migration.
3. `03-the-party-panel.md` — the group in `livePanel`: picker, rows, inline authoring, counts.
4. `04-stamping-by-drag.md` — `Transferable`, the drop target, the coordinate maths.

Sequential: each depends on the one before.
