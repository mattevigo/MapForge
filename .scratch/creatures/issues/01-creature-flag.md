# 01 — The Creature flag

Status: done

Add `isCreature` to `Pawn` and stop a Creature's Light reaching `Visibility`. No render
change yet — that is issue 02.

## What to build

**Model** — `Pawn` gains `var isCreature = false` (`FogDocument.swift:116`). Defaulted, so
version 2 files decode with it false and every existing Pawn stays a party member.

**Lighting** — `VisibilityCache.regions(for:)` passes `document.pawns.map(\.light)`
(`VisibilityCache.swift:42`). It must pass only the Pawns that are not Creatures. Do it
there rather than inside `Visibility.compute`, which takes a bare `[Light]` and should stay
a pure geometry seam that knows nothing about Pawns.

Note the cache's `Inputs` compares `pawnLights`, so filtering at that point also means
toggling `isCreature` correctly invalidates the cache — a Creature that stops emitting must
recompute the fog, not serve a stale polygon.

**Placement** — a Pawn placed while a "Creature" control is on gets `isCreature = true`.
Where that control lives is issue 03's call; this issue only needs the model to carry it.

## Acceptance

A Creature placed in a dark room lights nothing: `AppState.litRegions` is unchanged by its
presence. Flipping `isCreature` on an existing Pawn removes its light from the next
computation rather than serving the cached one. A version 2 fog file with no `isCreature`
key loads with every Pawn a party member.
