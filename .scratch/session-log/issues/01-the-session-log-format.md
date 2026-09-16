# 01 — The Session Log format

Status: done

`SessionLine`, its `Codable`, and the writer/reader pair. Pure model — no `AppState`, no views.

## What to build

**`SessionLine`** in a new `MapForge/SessionLog.swift`:

```swift
enum SessionLine: Equatable {
    case sessionStarted(startedAt: Date)
    case comment(text: String, map: String?, pawnID: UUID?, at: Date)
    case pawnMoved(pawnID: UUID, label: String, map: String?,
                   from: MapPoint, to: MapPoint, distanceSquares: CGFloat, at: Date)
    case encounterStarted(map: String?, logFile: String, at: Date)
    case encounterEnded(map: String?, at: Date)
    case sessionEnded(endedAt: Date)
    case unrecognised
}
```

Externally tagged on `"line"`, exactly as `LogLine` is (`CombatLog.swift:262-321`) and for the
same stated reason: a DM opens this file and reads it.

`map` is the Map's **file name** (`mapURL.lastPathComponent`), not an absolute path — the
Workspace moves and ADR-0012 says the machine does not travel with it. Optional throughout,
because a Session needs no Map (ADR-0015).

`label` on `pawnMoved` is a snapshot, for the same reason `Combatant` snapshots a name: a line
read next year must name the Pawn without the fog file it came from.

`.unrecognised` mirrors `Change.unrecognised` (`CombatLog.swift:54`) — decode-only, and
throwing on encode with the same message shape. A later version's line must not lose the file.

**`SessionLogFile`** — the naming and codec pair, mirroring `CombatLogFile`
(`CombatLogStore.swift:3-35`). Same `yyyy-MM-dd'T'HHmmss'Z'` format, same `.sortedKeys` +
`.withoutEscapingSlashes`, same `.iso8601` dates, same not-pretty-printed reasoning. Plus:

```swift
static func directory(in workspace: Workspace) -> URL   // .mapforge/sessions/
```

**`SessionLogWriter`** and **`SessionLogReader`** — mirroring `CombatLogWriter`/`CombatLogReader`
(`CombatLogStore.swift:44-129`) case for case: `init(in:startedAt:fileManager:)`,
`init(reopening:)`, `append(_:)` that writes one line and `synchronize()`s, `close()`,
`read(at:)` that drops a malformed final line, `logURLs(in:)`, `newestLogURL(in:)`.

Do **not** refactor `CombatLogWriter` into a shared generic. The duplication is ~60 lines and
ADR-0014 is explicit that the two formats share discipline and not vocabulary; a shared base
class is the coupling that makes one format's change break the other's file.

## Tests

`MapForgeTests/SessionLogTests.swift`, TDD — write these first:

- Every `SessionLine` case round-trips through encode/decode unchanged.
- A line encodes with `"line"` as its discriminator and reads as legible JSON.
- `.unrecognised` throws on encode; an unknown `"line"` value decodes *to* `.unrecognised`
  rather than throwing.
- `SessionLogFile.name(startedAt:)` has no colons and sorts as text in start order.
- Writer appends without rewriting: two `append` calls leave two lines, and reopening and
  appending a third leaves three.
- Reader drops a truncated final line and returns the rest; an absent file reads as `[]`.
- `newestLogURL` returns the latest by name.

## Acceptance

A `.jsonl` written by the writer and read by the reader yields the same lines. A file with a
half-written last line loses only that line. Nothing in `CombatLog.swift` or
`CombatLogStore.swift` is modified.
