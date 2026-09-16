# Rendering a Line

Status: done
Blocked by: 02

The text each row shows. Pure formatting over issue 02's rows — testable without a view.

## Changes: before → after

All 14 `Change` kinds render with both values, never a delta. ADR-0008 refused to store a delta
and the view that draws Corrections beside their Turns cannot be the one that invents one.

- `hpChanged` → "HP 22 → 15"; a `nil` side reads as "—"
- `tempHPChanged`, `maxHPChanged`, `acChanged`, `exhaustionChanged`, `initiativeChanged` → same shape
- `conditionAdded` → "Prone applied"; `conditionRemoved` → "Prone removed" (`Condition.title`)
- `concentrationChanged` → "Concentrating" / "Concentration ended"
- `noteAdded` → the text
- `moved` → "moved 7.5 m" — see distances below
- `combatantJoined` → "joined, initiative 14"; `combatantRemoved` → "removed from the Order"
- `orderChanged` → **"order changed"**, the one exception. It carries `[UUID]`; rendering
  fourteen names is a wall and the fact that matters is that it happened.
- `unrecognised` → a marked placeholder

## Distances in metres

`distanceSquares` is stored in Grid squares. Apply **Distance Unit** — CONTEXT.md already settles
that squares are what is stored and the unit is applied when a distance is shown. Both
`Change.moved` and `SessionLine.pawnMoved` go through it, so the Log speaks the same language as
the table and follows automatically when feet ships.

## Names

A Turn carries a `combatantID`, not a name. Resolve from the `encounterStarted` Line's
`combatants` snapshot, plus any later `combatantJoined`. An ID that resolves to nothing renders
as a marked unknown rather than an empty string.

`pawnMoved` already carries `label` — a snapshot taken at drag time, deliberately, so the Line
reads without the fog file. Use it; do not look the Pawn up.

## Done when

- Every `Change` case has a rendering and a test.
- A `nil` hit point on either side renders without crashing or reading as "0".
- A metres conversion test pins 5 squares to 7.5 m.
