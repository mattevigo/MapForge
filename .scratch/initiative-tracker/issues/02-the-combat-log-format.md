# 02 — The Combat Log format

Status: ready-for-agent

The file format and the fold that reads it back. Still no Encounter, no UI — this issue is
the vocabulary every later one writes in.

Read `docs/adr/0008-combat-is-an-append-only-turn-log.md` and
`docs/adr/0010-corrections-are-appended-never-edited.md` first. Both are load-bearing here.

## Build

**`Change`.** An enum with an associated payload per case. Every value change carries **both
the before and the after value**, never a delta — ADR-0008 explains why, and getting this
wrong is not recoverable once files exist.

| Case | Payload |
|---|---|
| `moved` | `combatantID`, `from: MapPoint`, `to: MapPoint`, `distanceSquares: CGFloat` |
| `hpChanged` | `combatantID`, `from: Int?`, `to: Int?` |
| `tempHPChanged` | `combatantID`, `from: Int`, `to: Int` |
| `maxHPChanged` | `combatantID`, `from: Int?`, `to: Int?` |
| `acChanged` | `combatantID`, `from: Int`, `to: Int` |
| `conditionAdded` | `combatantID`, `condition: Condition` |
| `conditionRemoved` | `combatantID`, `condition: Condition` |
| `exhaustionChanged` | `combatantID`, `from: Int`, `to: Int` |
| `concentrationChanged` | `combatantID`, `isConcentrating: Bool` |
| `noteAdded` | `combatantID`, `text: String` |
| `initiativeChanged` | `combatantID`, `from: Int`, `to: Int` |
| `orderChanged` | `order: [UUID]` — the whole new Order |
| `combatantJoined` | `combatantID`, `name`, `kind`, `initiative`, `block: StatBlock` |
| `combatantRemoved` | `combatantID` |

`combatantID` is a `Pawn.ID`. `orderChanged` carries no combatant because it is about the
Order itself. `combatantJoined` carries a **snapshot** — name, kind, and the Stat Block as it
stood — so a Log read years later can name a Combatant whose Pawn is long gone.

Encode as an externally tagged enum: `{"type": "hpChanged", "combatantID": "...", "from": 14,
"to": 9}`. Hand-written `Codable`, as `Pawn` and `MapPoint` already are. An unknown `type` on
read must not throw the whole file away — skip the Change and carry on, the way an unknown
key already decodes as absent.

**`LogLine`.** One per line of the file, four kinds:

- `encounterStarted` — `startedAt: Date`, `order: [UUID]`, and a `combatantJoined`-shaped
  snapshot for every Combatant. This line alone must be enough to reconstruct the opening
  state, because ADR-0008 forbids recomputing the Order from Initiative.
- `turn` — `round: Int`, `combatantID: UUID`, `changes: [Change]`, `endedAt: Date`
- `correction` — `targetRound: Int`, `targetCombatantID: UUID`, `changes: [Change]`,
  `recordedAt: Date`
- `encounterEnded` — `endedAt: Date`

**`CombatLogWriter`.** Opens `<map>.combat/<ISO8601>.jsonl`, appends one line per call,
flushes to disk each time. Appending — `FileHandle.seekToEnd` — never read-modify-write. A
line is one JSON object with **no newlines inside it**: encode without `.prettyPrinted` here,
unlike every other store in the app, because the format depends on it.

**`CombatLogReader`.** Reads a file to `[LogLine]`. A **truncated or malformed final line is
dropped, not an error** — that is the crash case ADR-0008 accepts, and refusing to open the
file would lose the whole fight to save the last Turn of it.

**`CombatLogFold`.** The pure function this whole design rests on:
`fold([LogLine]) -> EncounterState`, where `EncounterState` is the Order, the current Round,
and the current `StatBlock` per Combatant. It must:

- apply `encounterStarted`'s snapshots as the initial state
- apply each `turn`'s changes in file order
- apply each `correction`'s changes **onto the state as of its target Turn**, meaning
  Corrections are gathered by target before folding, not applied where they appear in the file
- tolerate a Correction targeting a Turn that was itself already corrected

Keep it a free function over `[LogLine]` with no file access, no `AppState`, and no clock, in
the shape of `Visibility` and `ScaleMath`. It is the most-tested thing in the feature.

## Tests

- A Log round-trips: write lines, read them, equal.
- Each `Change` case round-trips through its JSON, before/after values intact.
- A file whose last line is truncated mid-object reads every complete line before it.
- An unknown `Change` type is skipped and the rest of the line survives.
- A fold over `started → turn(hp 20→14) → turn(hp 14→9)` gives 9.
- A Correction targeting Round 1 changes the folded result even though it appears last.
- Two Corrections against the same Turn both apply, in file order.
- A Correction targeting a Turn that does not exist is ignored, not fatal.
- `combatantJoined` mid-Log adds a Combatant with its snapshot; `combatantRemoved` leaves it
  in the folded state, flagged removed.
- An `orderChanged` Change is what determines the Order, not a re-sort on Initiative.

## Done when

A Combat Log can be written, read back, and folded to state, with Corrections landing where
they belong. Covered by tests. Nothing writes one yet.
