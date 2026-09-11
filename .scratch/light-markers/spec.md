# MapForge — Light Markers

Status: closed — built, awaiting a check at the table

A **Light Marker** is the dot drawn where a Light stands, so the source of a lit region can
be seen rather than inferred.

Vocabulary: see [CONTEXT.md](../../CONTEXT.md) — **Light Marker**, **Light**, **Pawn**,
**Visibility**, **Fog Overlay**, **Player Display**, **Control Window**.

## What this is

A Light is invisible today. The lit region is its only representation, and outside the fog
editing mode nothing marks the point it radiates from — so mid-session the DM cannot answer
"which torch is lighting this room?" without opening an authoring mode they do not want open
during play. The table cannot answer it at all.

Both screens get markers. This is a deliberate change to the rule that the Player Display
draws only the Map and its Pawns: a Light Marker becomes the second thing, and the only
non-Pawn thing, that the table's screen draws over the artwork.

## The rule

| | Player Display | Control Window |
|---|---|---|
| A burning Light, on lit floor | **Marker** | Marker |
| A burning Light, on unlit floor | absent | Marker, de-emphasised |
| A doused Light (`isOn == false`) | **absent** | Marker, de-emphasised |

The players' half is exactly the Creature rule — drawn where the light reaches it, absent
otherwise — and it exists for the same reason. A doused lantern the DM placed for later, or
a brazier in a room the party has not reached, must not appear on the table's screen: that
is the giveaway the `creatures` feature already fixed once, when a hidden Pawn's torch could
light the ambush it was hiding.

The DM's half follows the Control Window's standing rule: everything drawn, the invisible
ones faded, because a DM as blind as the players cannot run the fight.

## Only the Map's own Lights

A Pawn is also a Light, but a Pawn already draws a token at exactly that point. A second
marker on top would be redundant, and on the Player Display it would double every party
member. Markers are for `document.lights` only — the braziers, sconces and campfires placed
with the Light tool.

## Not a new visibility rule

A burning Light almost always lights its own position, so in practice the fog test passes
for nearly every lit Light. It is still applied rather than assumed: a Light with a zero
radius, or one standing behind a Wall from itself, must not become the one thing on the
Player Display that ignores the fog.

## Scope

In: a marker drawn at each Map Light's point on both screens; the burning-and-lit rule for
players; the draw-everything-faded rule for the DM; reuse of `PlayerVisibility` so there
remains one answer to "what do players see".

Out: markers for Pawn lights; a marker that indicates radius, colour or intensity; per-Light
artwork or icons; clicking a marker to select or edit a Light outside the fog editing mode
(the editing mode keeps its own draggable handles); animating or flickering.

## Issues

1. [01 — The Light Marker rule](issues/01-the-light-marker-rule.md)
2. [02 — Markers on both screens](issues/02-markers-on-both-screens.md)
