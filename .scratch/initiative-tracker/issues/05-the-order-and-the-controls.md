# 05 — The Order and the combat controls

Status: ready-for-agent

The tracker itself: the list of Combatants and the buttons that drive a fight. Depends on
01, 02, 03 and 04.

## Build

**The header.** Round number, prominent — a DM glances at it mid-sentence. Beside it:

| Control | Icon | Behaviour |
|---|---|---|
| Play | `play.fill` | Rolls, settles the Order, opens a Combat Log. Only before an Encounter. |
| Next | `forward.fill` | Ends the Turn. Refused while correcting (issue 03) — disable it and say why. |
| Previous | `backward.fill` | Walks the correction cursor back one ended Turn. |
| Stop | `stop.fill` | Ends the Encounter. Confirms first — it closes the Log. |
| Re-roll | `dice.fill` | Re-rolls every Initiative. **Confirms first**: it destroys the settled Order. |

Icons were asked for explicitly. SF Symbols throughout, with accessibility labels, because
the UI tests will need to find these by name.

**The Order list.** One row per Combatant, in `order`. Compact enough that eight fit without
scrolling in 320 points:

- **Initiative** — leading, fixed-width, the number the row sorts by
- **Kind mark** — Players and Creatures must be distinguishable at a glance. Use the Pawn's
  own colour swatch plus a shape difference, matching how `PawnToken` already draws a Player
  as a disc and Treasure as a rounded square. Do not rely on colour alone.
- **Name** — the Pawn's label
- **Hit points** — `14/32`, with temporary hit points shown additively (`14+5/32`) when
  non-zero. An incomplete Stat Block shows a dash and a subtle warning mark, per the spec's
  rule that a missing stat block never drops a monster from the fight.
- **AC** — small, trailing
- **Conditions** — icons, not text. Fourteen of them will not fit as words. Overflow to a
  count badge past three or four.

**The active Turn is unmistakable**: a filled background, not a thin border. A DM reads this
from across a table at a glance.

**A removed Combatant** stays in the list, struck through and dimmed. It takes no Turns.

**Selecting a row** drives the editor in issue 06. Selection is independent of whose Turn it
is — a DM edits the monster the party just hit, not the one acting.

**Drag to reorder.** Ties are the DM's to break (ADR-0008 and the spec), so the rows reorder
by drag and each reorder records `orderChanged`. Reordering does not change anyone's
Initiative number — the Order and the numbers are allowed to disagree, because the Order is
what is real.

**The correcting state must be loud.** When the correction cursor is set, the header changes
to something like *◀ correcting Round 2 — Grog* on a distinctly coloured bar, and the Order
list dims. ADR-0010 names this the most dangerous interaction in the feature: an edit made in
the wrong mode is silent and wrong. Over-signal it.

## Tests

UI tests for the flows, unit tests for anything computable:

- Play with three Pawns produces three rows in descending Initiative order.
- A Treasure Pawn on the Map produces no row.
- Next moves the active highlight and wraps, incrementing the displayed Round.
- Previous shows the correcting bar; Next from there eventually returns to live.
- Next is disabled while correcting.
- Re-roll asks first, and cancelling changes nothing.
- Stop asks first.
- A Pawn with no hit points shows the incomplete mark and still appears.
- A removed Combatant is struck through and is skipped by Next.
- Dragging a row records a reorder and the new order survives a Next.
- Players and Creatures are distinguishable without reference to colour.

## Done when

A whole fight can be run from the panel: play, several Rounds of Next, a trip backwards and
forwards, a re-roll, a stop — with the Log on disk matching what happened.
