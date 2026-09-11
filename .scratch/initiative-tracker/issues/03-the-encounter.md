# 03 — The Encounter

Status: ready-for-human

The rules of running a fight, as pure logic: rolling, ordering, advancing, correcting. Still
no views. This is the `MeasurementControl`/`SoloSightControl` layer of the feature.

## Build

**`InitiativeRoll`.** `1d20 + initiativeBonus`, as a seam: a function taking a random source,
so tests are deterministic. `PlayerPlacement` and `GridFit` are the precedent for a pure enum
of static functions. A `d20` that takes `inout RandomNumberGenerator` is enough.

**`Encounter`.** A value type holding the live fight:

- `order: [UUID]` — Pawn IDs, the DM's sequence, never re-sorted after the start
- `round: Int` — starts at 1
- `activeIndex: Int` — whose Turn it is
- `correctionCursor: Int?` — nil when live; otherwise how many Turns back, per ADR-0010
- `pendingChanges: [Change]` — the current Turn's write-behind buffer (ADR-0008)
- `removed: Set<UUID>` — Combatants still listed but taking no Turns

**`EncounterControl`.** The operations, each returning the new `Encounter` plus any
`LogLine`s to append. Nothing here touches a file.

- **`start(pawns:stats:using:)`** — takes every Pawn whose kind is `.player` or `.creature`
  (never `.treasure`), rolls each, sorts descending on Initiative, and emits
  `encounterStarted` with the settled Order and a snapshot per Combatant. Ties keep whatever
  order the sort produced — no tiebreak rule, per the spec — and the DM rearranges by hand.
- **`next()`** — flushes `pendingChanges` into a `turn` line, advances `activeIndex` past any
  Combatant in `removed`, and wraps to index 0 incrementing `round`. Silently: no
  confirmation, the table is waiting. **Refused while `correctionCursor` is non-nil** — the
  DM returns to live first.
- **`previous()`** — moves `correctionCursor` back one ended Turn. Walking forward past the
  live Turn clears it to nil, which is how Next doubles as "return to live".
- **`record(_ change:)`** — appends to `pendingChanges` when live, or emits a `correction`
  line targeting the cursor's Turn when correcting. **`moved` is refused while correcting**
  (ADR-0010): return it unrecorded rather than silently dropping it, so issue 07 can decide
  what the UI says.
- **`reorder(from:to:)`** — moves a Combatant in `order` and records `orderChanged` carrying
  the whole new Order.
- **`join(pawn:block:using:)`** — rolls, inserts into `order` at its Initiative position,
  records `combatantJoined`. Inserting **after** the active index when the roll ties with
  someone already passed, so a summon does not act twice in one Round.
- **`remove(combatantID:)`** — adds to `removed`, records `combatantRemoved`. The Combatant
  stays in `order`. If it is the active one, `next()` must still work.
- **`stop()`** — flushes the current Turn and emits `encounterEnded`.
- **`rerollInitiative(using:)`** — re-rolls everyone and re-sorts, emitting an
  `initiativeChanged` per Combatant plus one `orderChanged`. **The Round does not reset** —
  it is a fact about history. The confirmation prompt is the UI's business (issue 05); this
  function assumes it already happened.

**The zero-hit-point rule.** Applying a `hpChanged` that lands on 0 or below also records
`conditionAdded(.unconscious)` and, if the Combatant was concentrating,
`concentrationChanged(false)`. One step, three Changes, for Players and Creatures alike.
Nobody is removed. Put this in `EncounterControl` rather than in the editor, so it holds no
matter which code path changes the number. Raising a Combatant above 0 does **not**
automatically clear Unconscious — coming back up is a decision, going down is not.

## Tests

Deterministic via an injected generator throughout:

- `start` rolls every Player and Creature and **no Treasure**.
- `start` sorts descending; a fixed generator gives a known Order.
- `next` wraps and increments the Round; it skips removed Combatants.
- `next` is refused while the correction cursor is set.
- `previous` then `next` returns to live, and the Round is unchanged by the trip.
- A Change recorded while correcting emits a `correction` line targeting the right Turn;
  the same Change recorded live lands in `pendingChanges`.
- A `moved` Change is refused while correcting.
- Dropping to 0 records Unconscious and clears concentration, in one call.
- Dropping to 0 while already Unconscious does not record a duplicate.
- Healing from 0 to 5 does not clear Unconscious.
- A joined Combatant lands in the right Order position and does not act twice in its Round.
- Removing the active Combatant leaves `next` working.
- Re-rolling changes the Order and leaves the Round alone.

## Done when

A whole fight can be run in tests — start, several Rounds, a correction, a join, a removal,
a stop — producing a Log that folds (issue 02) back to the same state. Nothing shows it.

## Comments

**Built.** One behavioural question the issue left ambiguous, resolved in the code.

The issue says a joined Combatant should insert "**after** the active index when the roll ties
with someone already passed, so a summon does not act twice in one Round". The implementation
inserts after the active index *always*, then walks forward to the position its Initiative
earns. So a wolf rolling 20 during Grog's turn (18) acts after Grog but still ahead of the
goblin's 12, in the same Round. The first test asserted the wolf should fall behind the goblin
too, which would have been punishing a summon for arriving — the test was wrong and was
changed.

`ScriptedGenerator`, the test's deterministic die, needed its own tests. `Int.random(in:using:)`
does not take `next()` modulo the range — it draws from the full `UInt64` space with rejection
sampling — so the obvious implementation returned faces nobody asked for and would have made a
dozen downstream assertions quietly meaningless. It now maps each face to the middle of its
band, and `testTheScriptedGeneratorRollsWhatItWasToldTo` holds that down.

`applyToState` in `EncounterControl` deliberately mirrors `CombatLogFold.apply`. The two are
kept separate because they serve different masters — one keeps the live tracker in step, the
other reconstructs from a file — and `testAWholeFightFoldsBackToWhatTheTrackerShows` is what
holds them to the same answer. If they ever disagree, that test fails rather than a DM finding
out mid-session. Worth revisiting if a third caller appears.

Three mutations were confirmed to fail the suite: the join insertion point, `next` ending a
Turn while correcting, and the 0-hit-point boundary at exactly 0.
