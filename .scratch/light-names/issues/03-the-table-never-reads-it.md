# 03 — The table never reads a Light's name

Status: ready-for-agent

Cheap to build, and the reason it is cheap is worth writing down rather than leaving implicit.
Depends on 01.

## Why this comes first, despite being last

Nothing needs building here — `LightMarker.swift` draws no text today, so a Light's name is
already invisible to the table. That is exactly why it needs a test. An invariant that holds
by accident is one a future feature breaks without noticing, and "draw the Light's name on the
marker so the DM can see it across the room" is a plausible, well-meant change that would leak
prep to the players.

`CONTEXT.md` is explicit about the equivalent rule for a Pawn: its label "is never drawn on the
Player Display, so a Pawn can be named for the DM's notes without the name crossing the room."
A Light named "trapped brazier" or "goes out in round 3" is the same kind of note.

## What exists

The Pawn rule is settled in one named, testable place — and the comment at
`PlayerVisibility.swift:43-46` explains why it lives there rather than in a view:

> A constant rather than a parameter because it is not conditional on anything — but it lives
> *here*, beside the rules about which Pawns draw at all, so that the whole answer to "what do
> the players get to see" is in one file and a view cannot quietly disagree with it.

```swift
static let showsPawnLabelToPlayers = false        // PlayerVisibility.swift:47
```

Enforced in the one shared token view, `PawnToken.showsLabel(atDiameter:toPlayers:)`
(`PawnToken.swift:99-102`), reached via `PawnToken.isForPlayers` (`:29`), which is `true` at
exactly one call site: `PlayerView.swift:70`. Every DM-side caller leaves the default —
`PawnLayer.swift:50`, `ControlView.swift:999`, `FogOverlay.swift:209`.

`LightMarker` is drawn on both surfaces already — `PlayerView.swift:55` for the players,
`PawnLayer.swift:42` for the DM — and takes only `squareSide`.

## Build

**A constant beside the others**, in `PlayerVisibility.swift` next to
`showsPawnLabelToPlayers` (`:47`) and `showsLightMarkerToPlayers` (`:59`):

```swift
static let showsLightNameToPlayers = false
```

**No `isForPlayers` parameter on `LightMarker`.** The cheapest correct answer is that the
marker never draws text at all, so there is nothing to suppress. Adding the parameter now
would be threading a flag through a view to gate a branch that does not exist. The constant
documents the decision; the test enforces it.

**If a future issue does want a name on the marker for the DM**, that is when `LightMarker`
gains `isForPlayers` and a `showsName(atDiameter:toPlayers:)` static mirroring
`PawnToken.showsLabel` — and the constant is already there to be consulted.

## Tests

In `MapForgeTests/LightMarkerTests.swift`, which already holds the Player-Display and DM-fade
rules (`:34-88`), modelled on `PawnLabelTests`:

- `testTheTableNeverReadsALightsName` — the counterpart of
  `PawnLabelTests.testTheTableNeverReadsALabel` (`:62-69`).
- The counterpart of
  `PawnLabelTests.testWhetherTheTableReadsLabelsIsSettledWhereEveryOtherLeakIs` (`:80`) —
  asserting the decision lives in `PlayerVisibility` and not in a view, so that a view cannot
  quietly disagree with it.

## Done when

A Light's name is DM-side by a rule that is written down and tested, rather than by the
accident that nobody has drawn text on a Light Marker yet.

## Comments
