# 02 — Markers on both screens

Status: done

Blocked by: 01

Draw the marker, on the Player Display and on the Control Window's normal preview.

## What to build

**A shared `LightMarker` view**, used by every surface that draws one — the reason
`PawnToken` is shared: a marker "can never look like two different things on the two
screens". It takes the Grid square side, like `PawnToken` does, so it scales with the Map
rather than with the window.

**Player Display** (`PlayerView`) — filter `appState.fog.lights` through
`showsLightMarkerToPlayers`. Drawn under the Pawns: a token is the game piece and must never
be obscured by furniture.

**Control Window** (`ControlView`'s normal preview, not the fog editing mode) — every Map
Light, faded via `isLightMarkerDimmedForDM` at the same `0.4` `PawnLayer` uses for a Pawn
the players cannot see. The same opacity because it is the same statement: *the table cannot
see this*.

**Leave the fog editing mode alone.** `FogOverlay.lightMarkers` already draws draggable
yellow authoring handles with selection rings, and they are a different thing: an editing
affordance, hit-testable, sized for dragging. Do not unify them — that is how an authoring
control ends up on the table's screen.

## Scope

- `document.lights` only, never `pawn.light`.
- No radius ring, no colour, no intensity, no icon per Light kind.
- Not clickable on either surface. Selecting a Light stays a fog-editing-mode action.

## Acceptance

A burning brazier on lit floor appears on both screens; doused, it stays on the DM's screen
faded and vanishes from the table's. A Pawn standing on a Light draws its token over the
marker, not under it. Entering and leaving the fog editing mode leaves that mode's existing
yellow handles exactly as they are. The marker scales with the Grid when the Map is zoomed.

## Comments

**A third of a square was too small.** Built at `squareSide / 3` first, and checked by
launching the app against a Map with a burning, a doused and a wall-shadowed Light. The
marker rendered correctly and the rules held — but beside a token it was a speck, easy to
miss when scanning for the source of a lit region, which is the whole job. Half a square
reads as a light source and still cannot be mistaken for a game piece.
