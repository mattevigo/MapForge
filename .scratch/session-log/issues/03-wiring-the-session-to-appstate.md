# 03 — Wiring the Session to AppState

Status: ready-for-agent

`AppState` holds a live Session, opens and closes its file, and feeds it the three events that
produce lines: a Comment, a completed drag, and an Encounter starting or stopping.

Depends on 01 and 02.

## What to build

In a new `MapForge/AppState+Session.swift`, mirroring `AppState+Combat.swift`'s shape:

```swift
@Published private(set) var session: Session?     // in AppState.swift, beside `encounter`
private var sessionWriter: SessionLogWriter?      // beside `logWriter`
```

**Starting.** `startSession()` requires `workspace != nil` and returns otherwise — the same
refusal `startEncounter` makes for a missing `mapURL`. Opens the writer, writes
`sessionStarted`.

**Stopping.** `stopSession()` writes `sessionEnded`, closes the writer, sets `session = nil`.

**Resuming.** `resumeSession()` on opening a Workspace: newest log, `SessionFold.fold`, and if
it returns a Session, reopen the writer at that file. Mirrors `resumeEncounter`
(`AppState+Combat.swift:333-343`) exactly, including that an unterminated file is honest.
Call it from `open(_ workspace:)` (`AppState.swift:742`).

**Commenting.** `addComment(_ text: String)` — trims, passes the current map name and
`selectedPawnID` to `SessionControl.comment`, writes what comes back.

**Movement.** `commitPawnMove(id:from:)` (`AppState+Combat.swift:221`) currently bails on
`guard encounter != nil`. It must now serve both logs. Restructure:

```swift
func commitPawnMove(id: Pawn.ID, from origin: MapPoint) {
    flushPendingFogWrites()
    guard let pawn = fog.pawns.first(where: { $0.id == id }), pawn.at != origin else { return }
    let distance = distanceInSquares(from: origin, to: pawn.at)
    if encounter != nil {
        recordChange(.moved(combatantID: id, from: origin, to: pawn.at,
                            distanceSquares: distance))
    }
    writeSession(SessionControl.pawnMoved(...))   // no-op while suspended
}
```

Note the two guards are now independent — a drag with no Encounter and a live Session records
to the Session Log only, which is the entire point of the feature. `SessionControl` drops it if
suspended, so **no `if` about Encounters is needed on the Session side**; the silence is the
model's job, not this call site's (issue 02).

**The hand-off.** `startEncounter` must call
`SessionControl.encounterStarted(map:logFile:at:in:)` with `logWriter?.url.lastPathComponent`
*after* the writer is opened, so the pointer names a file that exists. `stopEncounter` calls
`encounterEnded` — and must do so **before** `closeLog()`, or the map name is read from a
closed writer. Both are no-ops when no Session is running.

**Switching Workspace** ends the Session: `open(_ workspace:)` calls `stopSession()` first if
one runs. A Session's file lives in the Workspace it started in, and a Session that outlived
its folder would write into the wrong one. Note `hasRunningEncounter` already gates the
picker's confirmation (`AppState.swift:732`) — extend that predicate rather than adding a
second prompt.

## Tests

`MapForgeTests/AppStateSessionTests.swift`, TDD, against a temp-directory Workspace:

- `startSession` with no Workspace writes nothing and leaves `session == nil`.
- `startSession` creates `.mapforge/sessions/<name>.jsonl` with one `sessionStarted` line.
- A comment while a Session runs appends a line carrying the map name and text.
- **A drag with a Session and no Encounter appends `pawnMoved` to the Session Log** and nothing
  to any combat file.
- **A drag during an Encounter appends `.moved` to the Combat Log and nothing to the Session
  Log** — the ADR-0014 test, and the one that most matters.
- `startEncounter` appends exactly one `encounterStarted` line to the Session Log naming the
  Combat Log's file name, and that file exists on disk.
- `stopEncounter` appends `encounterEnded`, and a comment after it is recorded again.
- `stopSession` appends `sessionEnded` and a later comment writes nothing.
- Reopening a Workspace whose newest log has no `sessionEnded` restores a live Session and
  appends to the same file.
- Opening a different Workspace mid-Session ends it.

## Acceptance

With a Session running and no fight, dragging a Pawn leaves a line in the Workspace's session
file. Starting a fight makes the next drag land in `<map>.combat/` instead, with the Session
file untouched between the pointer line and the resume line. Nothing about the Combat Log's
existing behaviour changes: `MapForgeTests` combat suites pass unmodified.
