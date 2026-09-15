# 04 — Add: the armed placement

Status: ready-for-human
Blocked by: 01, 03

An `Add` control in the Control Window chrome offers **Light**, **Player**, **Creature**,
**Treasure**. Picking one arms a placement with a crosshair; the next left-click on the Map
places it. This is the only way to create a Light, and the only way to create a Creature or a
Treasure.

Land this before shipping the feature: `01` removes the old creation path, and until this
exists a Light cannot be created at all.

## Reuse the Measurement arming, do not reinvent it

`startMeasurement(_:)` (`ControlView.swift:817`) already arms a tool, `MeasurementCursor`
already draws the crosshair, and the next left-click already places a point
(`placeOrigin` :739). The DM has learned this interaction. Model the placement on it and
share the crosshair.

**At most one armed tool ever.** Arming a placement disarms a live Measurement and vice
versa; Esc backs out of either. Two armed tools make a left-click's meaning unguessable, and
the left-click gesture already switches behaviour on `isMeasuring`
(`ControlView.swift:426-429`) — extend that condition rather than adding a second one beside
it. Gesture composition in this layer has produced four defects
(`ControlView.swift:757-760`); one predicate is the safe shape.

The crosshair is the Control Window's alone — the Player Display has no use for watching a
cursor hunt for a point, which is the rule Measurement already follows.

## What gets placed

Kind is settled at arming, not in a sheet, so adding four goblins is four arms and no forms.
**Arming is not sticky**: one click places one thing and disarms. Re-arm for the next. (The
*last-picked* Kind is sticky, so the Add menu opens on it.)

Inherit from the last thing of that Kind placed, exactly as `FogOverlay.place(at:)` does
today (`:339-377`) — read it before `01` deletes it:

| | label/name | colour | sight/bright | big |
|---|---|---|---|---|
| Pawn (any Kind) | `Pawn.nextLabel(after:)` | prev of that Kind ?? `#C81E1E` | prev ?? 6 | prev ?? false |
| Light | `Light.nextName(after:)` | — | prev ?? 4, dim prev ?? 8 | — |

Inherit per Kind, not per Pawn: a DM's Creatures and Players are differently coloured, and
inheriting a goblin's colour onto a Player would be a surprise. `nextLabel` and `nextName`
avoid reusing a number after a delete — keep that.

No sheet opens after placing.

## Rules

- **A click outside the image is refused, not clamped.** `Stamp.swift:64-65` already refuses a
  drop outside, and `CONTEXT.md` says a Pawn beyond the implicit Walls is meaningless to
  Visibility. Stay armed on a refused click so the DM can just click again.
- **No declared Grid is fine.** Do not gate this. `AppState.litRegions` already returns `[]`
  without one, so a Light placed early is inert rather than wrong, and the Edit Light sheet
  warns. Refusing would make this stricter than the fog editor it replaces. See the spec.
- **A new Pawn joins a running Encounter** the way a Stamped one does — `addPawnToMap`
  (`AppState+Combat.swift:246`) appends, flushes and auto-joins with a rolled Initiative.
  Route through it; do not append to `fog.pawns` directly. A Treasure is never a Combatant
  and must not join.
- Placing is a live action: **not undoable**, and autosaved like every other fog mutation.
- Read the click position from `mirrorCursor`, never from an `NSEvent`
  (`RightClick.swift:6-16`).

## Where the button goes

The chrome beside `Edit Fog…` / `Pan Viewport…` (`ControlView.swift:559-561`), as a `Menu`.
Anything added above the preview must reserve constant height or the Map jumps mid-click
(`ControlView.swift:195-206`) — putting it in an existing row avoids that. Disabled with no
Map open.

## Tests

- Arming each of the four and clicking places the right thing at the right Map pixel.
- One click places one thing and disarms.
- Inheritance is per Kind: placing a Creature then a Player gives the Player the last
  *Player*'s colour.
- A click outside the image places nothing and stays armed.
- Arming a placement clears a live Measurement; arming a Measurement clears a placement; Esc
  clears either.
- A Creature placed during a running Encounter joins the Order with a rolled Initiative; a
  Treasure does not.
- Placing with no declared Grid succeeds.
- Labels and names do not collide after a delete.

## Done when

All four can be placed, and a Light can be created again.
