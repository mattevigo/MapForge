# 06 — The Stat Block editor and the notes box

Status: ready-for-agent

The two panes below the Order list. Depends on 05.

## Build

**The editor**, for the row selected in the Order list. Fields: initiative bonus, AC, current
HP, max HP, temporary HP, exhaustion (0–6), concentration (a toggle), and the fourteen
Conditions.

- **Edits reflect into the Order list live**, as typed. The list above is the same state, not
  a snapshot.
- **Every edit records a Change** through `EncounterControl.record` — never by writing a
  `StatBlock` directly. ADR-0008's consequence section is explicit: a field the UI writes
  directly is a field the Log does not know about. This is the rule most likely to be broken
  by accident, and the one that quietly invalidates the whole format.
- **A Change per committed edit, not per keystroke.** Typing `9` over `14` must not record
  `14→1, 1→9`. Commit on focus loss and on Return, the way the Pawn label field in
  `pawnLiveRow` already behaves.
- **Hit points want quick arithmetic**: a `-7` typed into a delta field beats mental
  subtraction at the table. Offer a small damage/heal stepper beside the current HP field. The
  recorded Change is still before-and-after, whatever the DM typed to get there.
- **Temporary hit points are shown for every Combatant**, Player and Creature alike — one
  shape, per issue 01.
- **Conditions as a toggle grid** of icons, not a menu: applying Prone must be one click. Each
  records `conditionAdded`/`conditionRemoved`.
- **Editing works with no Encounter running.** A DM fills in monster hit points during prep,
  and there is no Log open then — the edit writes straight to `stats.json` and records
  nothing, which is correct and is exactly why ADR-0009 keeps Stat Blocks out of the Log.

**The notes box**, below the editor. Free text, about **the Combatant whose Turn it is** —
not the selected one. Label it with that Combatant's name so there is no ambiguity. Return,
or a small send button, records `noteAdded` and clears the field.

While correcting, the notes box targets the Turn under the cursor, and its label says so. A
note can be added to a past Turn; no note can ever be edited or deleted (ADR-0010).

**With no Encounter running**, the notes box is disabled — a note belongs to a Turn.

## Tests

- Typing a new current HP updates the row above without a save or a reselect.
- One committed edit records exactly one Change, with the right before and after.
- A `-7` in the damage stepper records `hpChanged(from: 14, to: 7)`.
- Dropping to 0 through the editor applies Unconscious and clears concentration (issue 03's
  rule, exercised through the UI).
- Toggling Prone twice records an add and a remove.
- A note records `noteAdded` against the **active** Combatant, even when another row is
  selected.
- While correcting, a note lands on the targeted Turn.
- With no Encounter, editing hit points persists to `stats.json` and writes no Log.
- With no Encounter, the notes box is disabled.

## Done when

Every number and Condition is editable from the panel, edits show instantly in the Order list,
and every one of them is in the Log with its before and after.
