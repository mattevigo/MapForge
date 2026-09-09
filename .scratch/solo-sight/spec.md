# MapForge — Solo Sight

Status: ready-for-agent

**Solo Sight** isolates one Pawn so the table sees the Map as that character alone lights
it. Every other Pawn's Light goes out, and each Pawn is then drawn only where the light
that remains reaches it. The Map's own Lights keep burning.

Vocabulary: see [CONTEXT.md](../../CONTEXT.md) — **Solo Sight**, **Pawn**, **Light**,
**Visibility**, **Fog Overlay**, **Player Display**, **Control Window**.
Decision: [ADR 0004](../../docs/adr/0004-solo-sight-is-a-per-observer-view.md).

## What this is

A DM cannot currently answer "what does this character see?". Every party Pawn is a Light,
every Light feeds one shared `Visibility`, and the Player Display shows the union. The
scout who went ahead is standing in the glow of the fighter's torch three rooms back.

Solo Sight removes the rest of the party from the lighting for as long as the DM holds the
button, and shows the result **to the table**. A scout goes ahead; the players see what the
scout's own light finds, and not what the party's collective torchlight does.

## The rule

While Solo Sight is on for Pawn *P*:

| | |
|---|---|
| Lights feeding `Visibility` | Map Lights + *P*'s light only. Every other Pawn's is out. |
| *P* itself | **Always drawn**, on both screens. It is the subject of the mode. |
| Every other Pawn | Drawn only where the remaining light reaches it — bright or dim — exactly as a Creature is. |
| A hidden Pawn (`isHidden`) | Still hidden. Rule 1 is untouched. |
| *P*'s own flame (`light.isOn`) | Respected. Torch out means *P* lights nothing — that is what "your torch just died" means. |
| Control Window | Unchanged in kind: readable tint, **every** Pawn still drawn, the ones the table has lost dimmed at 0.4. |

At most one Pawn is isolated at a time. Pressing another Pawn's button moves the isolation;
pressing the active one ends it.

## What it is not

It is not line of sight. The Map's own Lights stay lit, so a party member in a
brazier-lit room is visible to the table even if *P* is nowhere near. Solo Sight shows what
is visible when the only *carried* light is *P*'s. The fog engine has no eyes, and the ADR
says why that is deliberate.

## Design

**Derived, never mutated.** The mode is one optional `Pawn.ID` on `AppState`, filtered in
at render time. Nothing is written to the sidecar, nothing is undoable, nothing is
restored on relaunch — the same shape as `isFogOverlayOn`, and the same reasoning as
`setPawnHidden`: a live performance action does not belong in the authoring undo stack.

**One cache, one array.** The isolated ID joins `VisibilityCache.Inputs`, so the
memoisation that already answers "did the lighting inputs change" answers this too.

**One visibility function.** `PlayerVisibility.showsToPlayers` gains the solo state and the
lit regions rather than acquiring a sibling. Two functions answering "what do players see"
is how the two screens drift apart.

**Clears itself** on a Map switch, on the isolated Pawn being deleted, and on entering fog
editing — the `be14e58` lesson, applied to a reference that outlives the document it points
into. It survives Blackout, which is orthogonal.

**Unavailable** on a hidden Pawn (the eye's guarantee wins) and while the Fog Overlay is
off (the whole effect is the fog shrinking). Disabled with a reason, not silently inert.

## Scope

In: the isolated-Pawn state on `AppState`; filtering the lighting inputs; the token
discovery rule under the mode; the live-row control beside the eye; the lifetime rules.

Out: multi-Pawn isolation; Solo Sight on Creatures or Treasures (a Creature emits no light,
so isolating one shows a black map — "what does the dragon see" is a different feature);
real per-observer line of sight; per-observer masks of any kind; a cone of vision;
persistence; undo.

## Issues

1. [01 — The isolated Pawn](issues/01-the-isolated-pawn.md)
2. [02 — Isolating the light](issues/02-isolating-the-light.md)
3. [03 — Tokens follow the light](issues/03-tokens-follow-the-light.md)
4. [04 — The Solo Sight control](issues/04-the-solo-sight-control.md)
