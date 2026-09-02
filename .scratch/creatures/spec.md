# MapForge — Creatures

Status: built — awaiting a check at the table

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

## Scope

In: the two flags; suppressing a Creature's Light in `Visibility`; drawing Creatures under
the Fog Overlay on the Player Display and de-emphasised on the Control Window; a live hide
toggle; placing a Pawn as a Creature.

Out: per-player line of sight; initiative, hit points or any stat block; Creature-specific
artwork or tokens beyond the existing coloured disc; automatic reveal on movement; a
fourth tool in the fog mode.

## Issues

1. [01 — The Creature flag](issues/01-creature-flag.md)
2. [02 — Creatures under the fog](issues/02-creatures-under-the-fog.md)
3. [03 — Hiding a Creature](issues/03-hiding-a-creature.md)
