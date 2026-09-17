# The spliced reading model

Status: done
Blocked by: 01

A pure value that turns a Session Log — and the Combat Logs it points at — into a flat list of
renderable rows. No SwiftUI. This is the piece the view is thin over, and it is where every rule
in ADR-0016 lives.

## Input and output

In: a Session Log URL, a Workspace root, and the live `Encounter` if one is running.
Out: an ordered list of rows. Something like:

- `sessionStarted(at:)`
- `comment(text:at:)`
- `pawnMoved(label:distanceSquares:at:)`
- `mapSeparator(path:)` — synthetic, see below
- `encounterStarted(map:)` / `encounterEnded`
- `encounterUnreadable(reason:)` — the pointer would not resolve
- `roundHeading(round:)`
- `turn(combatantName:)`
- `change(...)` — one per Change, beneath its Turn
- `correction(targetRound:targetCombatantName:)` + its Changes, beneath the target Turn
- `orphanCorrection(...)` — target Turn not in the file
- `unreadableLine`

## The rules

**File order. Never compare timestamps.** ADR-0016. Splice each Encounter's lines into the
position of its `encounterStarted` Line. Do not merge, do not sort.

**Corrections move; nothing else does.** Gather Corrections, draw each beneath the Turn it
targets, marked. A Correction whose target is absent is drawn at its file position, marked as an
orphan — `CombatLogFold` silently ignores these, which is right for state and wrong for history.

**Nothing vanishes.** `SessionLine.unrecognised`, a line `SessionLogReader.read` `compactMap`s
away, and an unresolvable combat pointer each produce a marked row. Note that `read` currently
erases the distinction between a dropped line and an `.unrecognised` one; if surfacing both
matters, the reader needs to stop `compactMap`ping.

**Map separators are synthetic.** When consecutive Lines disagree on `map`, emit a separator.
Derived at read time, written nowhere. A switch with no Line either side of it is invisible and
that is accepted.

**Rounds group Turns.** Emit a `roundHeading` when the round number changes.

**Empty Turns are emitted.** A `turn` with `changes: []` still produces its row.

## Reading combat

Always from the Combat Log file, for live and finished Encounters alike — one code path, and the
join fails loudly and early rather than only for last hour's fight. Resolve by taking the
`encounterStarted` Line's `map` (now a relative path, issue 01), applying
`StatsStore.combatDirectory(forMapAt:)`, and appending `logFile`. There is no existing helper for
this join; write one.

## Done when

- A Session with two Encounters produces Session Lines, then the first fight's Turns, then more
  Session Lines, then the second fight's, in file order.
- A Correction appended at a file's end renders beneath its target Turn.
- An `encounterStarted` naming a missing file renders as `encounterUnreadable`, not a gap.
- An `unrecognised` Line renders in position despite having no timestamp.
- Unit tests cover each, against fixture JSONL.
