# 02 — Creatures under the fog

Status: done

Draw a Creature only where the players can see it, and always for the DM.

## Why this is the whole feature

`PlayerView.swift:38-48` renders every Pawn after the `FogCanvas` and outside its
`isFogOverlayOn` guard, with a comment stating the intent: the token draws "regardless of
the fog's state", because turning fog on is not turning tokens off. Correct for the party,
exactly wrong for a monster.

## What to build

**Player Display** — a Creature is drawn only when
`Visibility.level(at: creature.at, in: appState.litRegions)` is `.bright` or `.dim`.
Unlit means not drawn at all.

Two edge cases the acceptance test must pin:

- **Fog Overlay off** reveals everything, Creatures included. The DM has switched the
  darkness off; a Creature that stayed hidden would be a token nobody can explain.
- **No Grid declared** makes `litRegions` empty, so every point is `.unlit` and every
  Creature would vanish. That reads as a bug. Treat "no Visibility at all" as "no fog is
  being drawn", and show them — the same reasoning that floors the token diameter rather
  than rendering an invisible token.

**Control Window** — the DM sees every Creature always, lit or not. It renders the Map
fully lit with Visibility as a tint precisely so the DM can see everything, and a DM who
cannot see their own monsters cannot run the fight. Draw an unlit Creature de-emphasised
(reduced opacity) so the DM can tell at a glance what the players can and cannot see. This
is the same de-emphasis idea `table-ready` issue 02 wants for inactive object kinds.

`PawnLayer` and `FogOverlay` both draw Pawns on the Control Window and both need this.

## Scope

- Visibility at the Creature's own point. Not per-player line of sight, not partial
  occlusion of the token's disc.
- No reveal animation. A Creature appears when the light reaches it.

## Acceptance

A Creature in an unlit room is absent from the Player Display and present, dimmed, on the
Control Window. Moving a party Pawn's light onto it makes it appear for players. Switching
the Fog Overlay off reveals it. A Map with no declared Grid shows Creatures rather than
hiding them all.
