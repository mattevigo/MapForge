# MapForge — Creatures

Status: closed 2026-09-02 — built, awaiting a check at the table

A **Creature** is a Pawn the players discover rather than one they carry. It emits no
light, it is drawn *under* the Fog Overlay so darkness hides it, and the DM can take it off
the table entirely without deleting it.

Vocabulary: see [CONTEXT.md](../../CONTEXT.md) — **Pawn**, **Light**, **Visibility**,
**Fog Overlay**, **Player Display**.

## What this is

Every Pawn today is a light source and is drawn on top of the fog unconditionally.
`PlayerView` says so explicitly: the token renders "regardless of the fog's state", because
turning fog on is not turning tokens off. That is right for the party — a player's own
miniature must never vanish.

It is exactly wrong for a monster. A goblin waiting in an unlit room should not be on the
Player Display at all, and it certainly should not be lighting the room it is hiding in.

So a Creature inverts both halves of what a Pawn is:

| | Pawn (party) | Creature |
|---|---|---|
| Emits Light | yes — sight and illumination are one number | **no** |
| Drawn when unlit | yes, always on top of the fog | **no** — under it, hidden by darkness |
| Hidden by the DM | n/a | **yes**, and then invisible whatever the light |

## A flag, not a new type

`Pawn` gains `isCreature` and `isHidden`. Not a separate `Creature` struct and a fourth
tool: placement, dragging, labels, colour, selection, deletion, undo and the fog file all
work already and would every one of them be duplicated. Only two behaviours branch —
whether the Pawn's Light reaches `Visibility`, and which side of the Fog Overlay it draws
on.

The cost is honest: a Creature carries a `light` it does not use. That is the same
collapse `Pawn` already makes in the other direction — "a Pawn *has* a Light rather than
repeating its fields" — and a Creature that is later promoted to a party member keeps its
radii rather than needing them re-entered.

Version 2 files decode with both flags false, which is exactly today's behaviour.

## Revealed by light, not by proximity

A Creature is drawn where `Visibility.level(at:)` for its position is **bright or dim**,
and hidden where it is unlit. Dim reveals: 5e treats dim light as lightly obscured, not as
blindness, and a Creature standing on floor the players can plainly see would otherwise
be invisible for no reason they could infer.

This is deliberately *not* line-of-sight per player. There are no per-observer masks in
this app and one shared Player Display — the same reasoning that collapsed a Pawn's sight
and illumination into one number. What the fog reveals is what the table sees.

**The DM always sees Creatures.** The Control Window renders the Map fully lit with
Visibility as a translucent tint, and that holds here: a DM who cannot see their own
monsters cannot run the fight. Hidden Creatures show on the Control Window de-emphasised,
never absent.

## Hiding is a live act

`isHidden` is toggled from the live row beside the Fog and Light switches — one click, no
mode to enter, players watching. It follows `setPawnLight`'s precedent exactly: it writes
straight to `AppState.fog` and is **not undoable**, because it is a performance action and
filling the undo stack with it would bury the DM's authoring work.

Hidden beats lit. A hidden Creature is invisible on the Player Display even in bright
light — that is the point of the control.

## Big

A separate, orthogonal flag on the same type: `isBig` draws the token across 2×2 squares
rather than 1×1. All four combinations are meaningful — an ogre ally, a goblin, an ogre
monster, a party member — so it is not folded into `isCreature`.

**Purely visual.** The radii stay measured from the Pawn's point: a creature's size does
not change how far it sees or how far its torch reaches, in 5e or here. A Big Creature is
also revealed by its own point, not by its footprint, consistently with every other Pawn —
the alternative is a token drawn half-lit at the edge of a torch's reach.

**Centred on the click, and not snapped.** A 2×2 token's centre falls on a Grid
intersection rather than a square centre, so the DM positions it by eye like everything
else. Pawns have never snapped, and a Big Pawn that jumped to a lattice would be exactly
the behaviour this app removed on purpose.

`PawnToken` takes **one square's side** and works the span out itself. Pre-multiplying at
the call sites conflated "how big is the footprint" with "how big is this view": an ogre's
label rendered at twice its neighbours' point size, its legibility floor was halved, and
the live row's fixed 14 pt chrome grew and misaligned the row. The disc scales with the
footprint; text and chrome do not.

## Scope

In: the two flags; suppressing a Creature's Light in `Visibility`; drawing Creatures under
the Fog Overlay on the Player Display and de-emphasised on the Control Window; a live hide
toggle; placing a Pawn as a Creature.

Out: size categories beyond Big (no Huge or Gargantuan); per-player line of sight;
initiative, hit points or any stat block; Creature-specific
artwork or tokens beyond the existing coloured disc; automatic reveal on movement; a
fourth tool in the fog mode.

## Closed 2026-09-02

All three issues done, plus **Big** (2×2 tokens), which arrived mid-feature and is specced
above. Two defects were caught by review rather than by testing, both worth recording:

- **Adding flags to `Pawn` nearly broke every existing fog file.** Swift's synthesised
  decode requires every key unless the property is optional, so a property default is not
  enough — every `.fog.json` already beside a Map would have failed to load, and `FogStore`
  would correctly have refused to overwrite what it could not read. A hand-written
  `init(from:)` with `decodeIfPresent` fixes it; the test that decodes a file without the
  keys is the one that must never be deleted.
- **A hidden Pawn kept emitting light.** Its token left the Player Display while its torch
  burned on, lighting a wall-shadowed region radiating from nothing — and that light is
  exactly what reveals Creatures, so hiding a Pawn could have given away the ambush it was
  hiding for.

Not verified at the table. The reveal rule is unit-tested through `PlayerVisibility`, but
whether it *reads* right on a real map during a real fight is a judgement only the DM can
make — and the `table-ready` feature produced four cases where green tests and working
software were different things.

## Issues

1. [01 — The Creature flag](issues/01-creature-flag.md)
2. [02 — Creatures under the fog](issues/02-creatures-under-the-fog.md)
3. [03 — Hiding a Creature](issues/03-hiding-a-creature.md)
