# 01 — The Light Marker rule

Status: done

Decide, in one pure place, whether a Light's marker is drawn to players and whether the DM
sees it faded.

## What to build

**In `PlayerVisibility`**, beside the Pawn rules, so there remains exactly one type
answering "what do players see" — the property ADR 0004 says a second function is how the
two screens drift apart:

```
showsLightMarkerToPlayers(light:regions:isFogOverlayOn:hasVisibility:) -> Bool
isLightMarkerDimmedForDM(light:...) -> Bool
```

The rule, in order:

1. **A doused Light shows no marker to players.** `light.isOn == false` is absent, whatever
   the Visibility at its point. This is rule 1 of the Pawn set — the DM's "not yet" — and it
   is what stops a lantern placed for later from telegraphing where light is about to
   appear.
2. **With no fog being drawn, a burning Light shows.** Fog Overlay off, or no Grid declared:
   the same reasoning the Pawn rules already give — there is no darkness to hide behind, and
   a marker that stayed hidden would be a token nobody can explain.
3. **Otherwise drawn only where the light reaches it**, bright or dim, exactly as a Creature
   is. Dim reveals.

**The DM's rule** is the standing one: never absent, only faded, and faded precisely when
players cannot see it — so the negation, as `isDimmedForDM` already is for Pawns.

## Scope

- Map Lights only. This function is never called for a Pawn's light: a Pawn draws its own
  token at that point.
- No new geometry. `Visibility.level(at:in:)` already answers "is this point lit".

## Acceptance

A burning Light on lit floor shows to players; the same Light doused does not; a burning
Light on unlit floor does not. With the Fog Overlay off, every burning Light shows and every
doused one stays hidden. With no Grid declared, the same. The DM's answer is the exact
negation in every case. Tested through `PlayerVisibility` without a window, beside the Pawn
tests.
