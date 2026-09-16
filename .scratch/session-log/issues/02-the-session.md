# 02 — The Session

Status: done

The pure-logic half: a `Session` value and a `SessionControl` that decides what lines a gesture
produces. No file handles, no `AppState`, no views — mirroring how `EncounterControl` is
testable without a disk.

Depends on 01.

## What to build

**`Session`** in `MapForge/Session.swift`:

```swift
struct Session: Equatable {
    let startedAt: Date
    /// True between `encounterStarted` and `encounterEnded`: the Session Log is silent.
    private(set) var isRecordingSuspended: Bool
}
```

`isRecordingSuspended` is the whole of ADR-0014 expressed as one Bool. It is the single place
the silence rule lives, so no caller needs to remember it.

**`SessionControl`** — static functions taking `inout Session` and returning `[SessionLine]`,
exactly as `EncounterControl` does:

```swift
static func start(at: Date) -> (Session, [SessionLine])
static func comment(_ text: String, map: String?, pawnID: UUID?,
                    at: Date, in: inout Session) -> [SessionLine]
static func pawnMoved(...) -> [SessionLine]
static func encounterStarted(map: String?, logFile: String, at: Date,
                             in: inout Session) -> [SessionLine]
static func encounterEnded(map: String?, at: Date, in: inout Session) -> [SessionLine]
static func stop(_ session: inout Session, at: Date) -> [SessionLine]
```

The rules, all of which belong here rather than in `AppState`:

- `comment` and `pawnMoved` return `[]` when `isRecordingSuspended`. **The silence is enforced
  in the model, not by the view disabling a field.** A disabled control is a courtesy; this is
  the guarantee.
- `comment` trims and returns `[]` for empty text, as `AppState.addNote` does
  (`AppState+Combat.swift:69-75`).
- `encounterStarted` sets `isRecordingSuspended = true` and emits its line. `encounterEnded`
  clears it and emits its line. **Both lines are written even though the flag is set** — the
  pointer line is what makes the hole in the file legible, and the resume line is what makes
  the fold able to tell "silent" from "ended".
- `encounterStarted` while already suspended emits `[]` and changes nothing. Belt and braces:
  two fights cannot nest, but a double call must not write two pointers.
- `stop` while suspended still ends the Session and emits `sessionEnded`. A DM who quits
  mid-fight has ended the evening; the Combat Log's own end line is not this file's business.

**`SessionFold`** — the minimum needed to resume: given `[SessionLine]`, return whether the
Session ended and what its `startedAt` and suspension state were.

```swift
enum SessionFold {
    static func fold(_ lines: [SessionLine]) -> Session?   // nil if ended or unreadable
}
```

A file whose last relevant line is `encounterStarted` folds to a suspended Session — a DM who
quit mid-fight and reopened gets the silence back, and `resumeEncounter` will reopen the fight
alongside it.

## Tests

`MapForgeTests/SessionTests.swift`, TDD:

- `start` produces exactly one `sessionStarted` and an un-suspended Session.
- A comment during a normal Session produces one line carrying its text, map and pawn.
- **A comment while suspended produces no lines** and mutates nothing.
- **A movement while suspended produces no lines.**
- `encounterStarted` suspends; `encounterEnded` resumes; a comment between them is dropped and
  one after them is recorded.
- A second `encounterStarted` while suspended is a no-op.
- `stop` while suspended still emits `sessionEnded`.
- Empty and whitespace-only comment text produces no lines.
- `SessionFold` on a file ending in `sessionEnded` returns nil; on one ending in a comment
  returns a live un-suspended Session; on one ending in `encounterStarted` returns a live
  *suspended* one.

## Acceptance

Every rule in ADR-0014 is enforced by `SessionControl` with no disk and no UI present. The
silence is a property of the model: a caller that forgets to check `isRecordingSuspended`
cannot write a line anyway.
