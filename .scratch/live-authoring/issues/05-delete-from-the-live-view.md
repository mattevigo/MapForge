# 05 — Delete from the Live View

Status: ready-for-agent
Blocked by: 02

`Delete` in the right-click menu removes a Pawn or a Light. Not a new convenience — `01`
removed `⌫`-after-select in the fog mode, which was the app's only deletion path
(`FogOverlay.deleteSelected`, `:425-445`). This replaces it.

## Wire the function that already exists

`AppState.removePawnFromMap` (`AppState+Combat.swift:258`) is written and tested and has
never had a UI call site. Give it one. Check what it already does before adding to it.

## A deleted Pawn leaves the Order and stays in the Log

If the Pawn is a live Combatant, deleting it removes it from the Order exactly as Benching
does. The Combat Log is untouched and keeps naming it: `CONTEXT.md` (**Combatant**) already
requires that a monster that died in Round 2 stays part of what happened, whatever the
tracker shows now. Do not write a Correction — a deletion is not a Change to a Combatant, and
`CONTEXT.md` (**Correction**) says a movement cannot be corrected for the same reason.

If the deleted Pawn was mid-Turn, advance the Encounter the way Benching the current
Combatant already does. Find that path rather than inventing a second one.

## Everything else that must let go

A deleted Pawn can be referenced from three places, and each already has a self-invalidating
pattern to follow — use them, do not add a fourth:

- **Solo Sight** — `soloSightPawnID` clears when its Pawn goes (`AppState.swift:64-66`,
  `:276-280`, the `resolved…` guard).
- **A Measurement anchored to it** — "a Measurement anchored to a Pawn ends when that Pawn
  does" (`CONTEXT.md`, **Measurement Origin**). Pinned Measurements too.
- **An open Edit sheet on it** — closes, per `03`.

## No confirmation

It is a live action and the DM can add another. A confirmation dialog in the middle of a
fight costs more than the mistake does.

## Tests

- Deleting a Pawn removes it from `fog.pawns` and the change is autosaved.
- Deleting a Combatant removes it from the Order and leaves the Combat Log naming it.
- Deleting the Pawn whose Turn it is advances the Encounter.
- Deleting the Solo Sight subject clears Solo Sight.
- Deleting a Measurement's anchor ends that Measurement, pinned included.
- Deleting a Light removes it and the Visibility recomputes.
- Deleting a Pawn with a Stat Block does not leave the stats file referencing a Pawn that is
  gone.

## Done when

Both objects can be deleted from the Live View, and nothing is left holding a dead ID.
