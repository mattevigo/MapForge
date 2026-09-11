# 07 — Wiring the Map to the Log

Status: ready-for-agent

The last seam: things that happen on the Map become Changes in the Log. Depends on all of
01–06.

## Build

**Movement.** `PawnLayer`'s drag already has the right boundary: `onCommit` on drag end, which
flushes to disk immediately rather than waiting out the autosave debounce. One completed drag
is one `moved` Change — `from`, `to`, and the distance between them. Not the path within the
drag: the spec is explicit that hand-wobble is not domain data and the decision is where the
DM lets go.

Distance in **Grid squares**, converted for display by `DistanceUnit` the way `Measurement`
already does. Squares are what gets stored, metres are what gets shown — the existing rule,
and the reason `DistanceUnit`'s glossary entry says so.

A drag records only while an Encounter is running. Moving a Pawn with no Encounter open is
what the app already does and stays unlogged.

**Whose Turn does a move land in?** The active one, always, even when the Pawn moved is
somebody else's. A Turn records what happened during it (`CONTEXT.md`, **Turn**), and the
Change carries `combatantID` so the reader can still tell who moved.

**Movement while correcting is refused** (ADR-0010, and issue 03 returns it unrecorded). The
Pawn still moves — the Map is the truth — it simply records nothing. Say so once, quietly, in
the correcting bar rather than in an alert.

**Stamping mid-Encounter.** A Character stamped onto the Map while a fight runs joins
automatically: roll, insert in the Order, record `combatantJoined` with its snapshot. No
prompt. `Stamp` already produces a Pawn with a Stat Block copied from the Character (issue
01), so the snapshot is to hand.

A Creature Pawn created by click-to-place inside the fog editing mode does **not** join, and
this asymmetry is deliberate: authoring fog is not playing. It joins at the next `play`.

**Deleting a Pawn mid-Encounter.** Records `combatantRemoved`. The Combatant stays listed and
struck through (issue 05), and its Stat Block stays in `stats.json` until the Encounter ends —
ADR-0009 says the record outlives the token. Sweep orphaned Stat Blocks on `stop`, never
while a fight runs.

**Persistence timing.**

- The Combat Log appends on every `next` and on every `correction`. Never debounced; a Turn
  ending is the durability boundary the whole format is built on.
- `stats.json` is written debounced, like fog. Use `FogAutosave`'s shape — 0.5s, last-one-wins
  — and flush on `stop`, on Map close, and on app quit, alongside the existing
  `flushPendingFogWrites` wired into `NSWindow.willCloseNotification`.
- An Encounter left running when the Map closes or the app quits is **flushed, not stopped**.
  A DM closing a laptop mid-fight is taking a break, and inventing an `encounterEnded` line
  would put a lie in the Log. Reopening the Map folds the Log back and the fight resumes.

**Resuming.** Opening a Map whose newest Log has no `encounterEnded` line restores the
Encounter from the fold (issue 02). The Round, the Order, the active Combatant and every Stat
Block come back. This falls out of the format for free and is the payoff for the whole design;
test it.

**`AppState` grows an `encounter`**, alongside `fog` and `parties`. Keep the live/authoring
split the app already has: everything in this feature is **live**. None of it enters
`FogEdits`, none of it is undoable by the fog Undo button, and the fog Undo must not disturb
it. `carryLiveState(onto:)` is the precedent for what a live change has to survive.

## Tests

- A pawn drag during a Turn records one `moved` with the right distance in squares.
- Three drags in one Turn record three Changes; their distances sum to the turn's total.
- A drag with no Encounter records nothing.
- A drag while correcting moves the Pawn and records nothing.
- Stamping mid-Encounter joins the Combatant in Order position.
- Placing a Creature inside fog editing does not join it.
- Deleting a Pawn records a removal, keeps the row, and keeps the Stat Block until `stop`.
- Opening a Map with an unterminated Log resumes the Round, Order, active Combatant and
  every Stat Block.
- Quitting mid-fight and relaunching resumes; the Log has no `encounterEnded`.
- The fog Undo button does not alter any hit points or the Order.
- A fight run end to end produces a Log that folds back to the tracker's final state — the
  invariant that everything else depends on.

## Done when

A fight can be run at a real table: play, drag pawns, take damage, apply Conditions, take
notes, go back and fix Round 2, stop — and the file beside the Map is a complete, foldable,
human-readable record of it.
