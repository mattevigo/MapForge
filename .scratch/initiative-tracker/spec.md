# Initiative Tracker: run the fight from the Control Window

Status: closed 2026-09-14 — all seven issues done, verified at the table

MapForge presents maps and lights them. It knows nothing about the fight happening on them —
no hit points, no armour class, no dice, no turn order. A DM runs combat on paper or in a
second app while MapForge shows the map.

This feature adds an **Encounter**: a second tab in the Control Window holding the Order of
**Combatants**, their **Stat Blocks**, and an append-only **Combat Log** of everything that
happened, Turn by Turn.

See `CONTEXT.md` for the eleven terms this is written in, and:

- `docs/adr/0008-combat-is-an-append-only-turn-log.md` — the Log is the state; one line per Turn
- `docs/adr/0009-combat-state-lives-outside-the-fog-document.md` — where Stat Blocks live
- `docs/adr/0010-corrections-are-appended-never-edited.md` — the Previous button

## The shape of it

The Control Window's right-hand panel becomes two tabs: **Scene** (the Party, Lights and Pawn
groups exactly as today) and **Combat**. The panel widens from 236 to 320 points for both.

The Combat tab, top to bottom:

1. **Header** — Round number, a play/stop button, a next button, a previous button. Icons.
2. **The Order** — one compact row per Combatant: Initiative, name, a Player/Creature mark,
   hit points, armour class, Condition icons. The Combatant whose Turn it is is unmistakable.
3. **The Stat Block editor** — the selected Combatant's numbers, live-editing into the row
   above.
4. **The notes box** — free text about the Combatant whose Turn it is, appended to the Log.

Pressing **play** rolls 1d20 + initiative bonus for every Player and Creature Pawn on the Map,
sorts them, and writes the opening line of a new Combat Log. **Next** ends a Turn and writes
its line. **Stop** ends the Encounter.

## Rules worth stating once

- **Treasure never takes part.** The Order is Players and Creatures only.
- **Everyone is rolled for**, Players included. Overtyping a number the players call out beats
  typing into an empty field.
- **Ties are not broken by a rule.** The Order sorts on Initiative once and is then the DM's
  to rearrange by hand. Because it is decided rather than derived, it is recorded.
- **A Pawn with no Stat Block still joins**, with defaults (AC 10, no hit points, +0), flagged
  as incomplete. A forgotten stat block must never silently drop a monster from the fight.
- **A Pawn stamped mid-Encounter joins automatically**, rolling as it arrives and entering the
  Order in place.
- **A Pawn deleted mid-Encounter stays listed as removed.** It stops taking Turns. The Log
  already names it.
- **Zero hit points applies Unconscious and clears concentration**, as one recorded step, for
  Players and Creatures alike. It does not remove anybody.
- **Conditions have no duration.** Fourteen booleans, plus exhaustion as a level of 0–6, plus
  concentration as its own flag — not a Condition, and not rendered as one.
- **Stopping an Encounter changes no numbers.** No healing, no clearing.
- **Every value Change records before and after**, never a delta.
- **Movement is logged per drag**, one Change per completed drag, `from` and `to` and the
  distance between them. Not the path within a drag: the DM's hand-wobble is not domain data,
  and the decision is where they let go.

## Files

Everything lives in `<map>.combat/` beside the Map image:

```
dungeon.png
dungeon.fog.json                       ← untouched by this feature
dungeon.combat/
├── stats.json                         ← Stat Blocks, keyed by Pawn.ID
├── 2026-09-11T143200Z.jsonl           ← one Encounter
└── 2026-09-11T210400Z.jsonl           ← another
```

## Out of scope

Deliberately, so none of it reads as an omission:

- **Replay UI.** The format makes replay possible; no timeline, scrubber or animation ships
  here. This is the explicit trade in ADR-0008.
- **A timeline view for choosing which Turn to correct.** The Previous button reaches every
  Turn with no new view. A timeline is the better long-term answer and changes no bytes.
- **Damage and healing as distinct concepts** with a source. The UI edits a hit point field;
  it has no attack button, so it cannot honestly know who dealt what. `hpChanged` is what can
  be observed.
- **Condition durations**, concentration saves, death saves, and anything else that needs to
  know about actions. Half a rules engine is worse than none.
- **A monster library.** Creature Stat Blocks are typed per Encounter, as Creature Pawns are
  placed per Encounter. ADR-0007 already deferred this for Characters.
- **Dice for anything but initiative.** No attack rolls, no damage rolls.
- **Markdown or PDF export** of a Combat Log. The file is already human-readable JSONL.
- **Grid snapping**, still an app-wide question and still not this feature's.

## Issues

1. `01-the-stat-block.md` — `StatBlock`, `Condition`, `StatsStore`, and Stat Blocks on `PartyCharacter`.
2. `02-the-combat-log-format.md` — `Turn`, `Change`, `Correction`, the JSONL reader/writer, the fold.
3. `03-the-encounter.md` — rolling, the Order, Turns, Rounds, the correction cursor. Pure logic.
4. `04-the-combat-tab.md` — splitting `livePanel` into tabs and widening the panel.
5. `05-the-order-and-the-controls.md` — the rows, the play/next/previous/stop buttons, the Round header.
6. `06-the-stat-editor-and-notes.md` — the editor below the list, live reflection, the notes box.
7. `07-wiring-the-map-to-the-log.md` — movement Changes, stamp-joins, delete-removes, autosave.

Sequential, with one exception: 04 depends only on 01 and can start alongside 02–03.
