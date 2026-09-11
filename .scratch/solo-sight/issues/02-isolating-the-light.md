# 02 — Isolating the light

Status: done

Blocked by: 01

While Solo Sight is on, only the isolated Pawn's Light joins the Map's own Lights in the
Visibility computation. Every other Pawn's goes out.

## What to build

**The filter** — `VisibilityCache.regions(for:imagePixelSize:pixelsPerSquare:)`
(`VisibilityCache.swift:38-69`) already filters `pawnLights` to
`!$0.isDiscovered && !$0.isHidden` (lines 53-55). Solo Sight adds one clause: when an ID is
isolated, keep only that Pawn's light.

`document.lights` — the Map's own Lights — are **not** filtered. A brazier is the room, not
another character's influence. This is the line most likely to be "helpfully" over-applied;
the ADR records why it must not be.

**The cache key** — `Inputs` (`VisibilityCache.swift:16-22`) gains the isolated ID. It is a
lighting input like any other, so the memoisation that already answers "did the lighting
inputs change" answers this too. Toggling the mode invalidates once and then re-memoises.

`AppState.litRegions` (`AppState.swift:236-241`) keeps its signature: one array, one cache,
both windows reading the same thing. No second `[LitRegion]` set — the two views are never
shown at once, so computing both wastes work to serve a state that cannot exist.

**The isolated Pawn's own flame is respected.** If `light.isOn` is false, `Visibility`
already drops it (`Visibility.swift:39`) and Solo Sight must not force it back on. The
result — one token standing in whatever the room's own fire shows — is a scene, not a bug.

## Scope

- Lighting inputs only. Which Pawns are *drawn* is issue 03.
- No change to `Visibility.compute`, `litPolygon`, `level(at:in:)` or `FogCanvas`. The
  geometry and the compositor do not know this feature exists.

## Acceptance

With Solo Sight on Pawn *P*, the lit region set equals what it would be if every other Pawn
had its flame off — and Map Lights are unaffected, verifiable by isolating a Pawn far from a
brazier and confirming the brazier's room stays lit. Panning still does not recompute.
Toggling the mode on and off returns the exact region set that was there before. With *P*'s
own flame off, only the Map Lights contribute.

## Comments

**Built without adding a field to `Inputs`.** The issue asked for the isolated ID to join
the cache key. It did not need to: `pawnLights` is *derived* from the ID, so isolating a
Pawn already changes the key — adding the ID as well would have been a second copy of the
same fact, and a chance for the two to disagree. `testEnteringAndLeavingSoloSightRecomputes`
and `testSoloSightIsStillMemoised` are what hold the invalidation rule down.
