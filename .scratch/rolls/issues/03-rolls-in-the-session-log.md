# 03 — Rolls in the Session Log

Status: ready-for-agent
Blocked by: 01

The same two records outside a fight, in the Session Log's own vocabulary.

## What to add

**`SessionLog.swift`**, `enum SessionLine`:

```swift
case savingThrow(pawnID: UUID, label: String, map: String?, ability: Ability, roll: Roll, at: Date)
case abilityCheck(pawnID: UUID, label: String, map: String?, skill: Skill, roll: Roll, at: Date)
```

`label` is a snapshot for the reason `pawnMoved`'s is: "a line read next year must name the
Pawn without the fog file it came from". Unlike `comment`'s `pawnID`, this one **is** the
subject — a Roll is unambiguously about the Pawn that made it, and this is the first
`SessionLine` for which that is true.

Then: `Kind` raw values, decode arms, encode arms, same flat `Roll` encoding as issue 02, and
the same omission of `difficultyClass` when nil.

**`AppState+Session.swift`** — a recorder beside `recordSessionMove`, funnelling through
`writeSession(_:)` so `sessionLineCount` bumps and the Log View reloads.

**`Session.swift`**, `SessionFold.fold` and **`LogViewModel.swift`**, `SessionLine.map` —
both exhaustive, both need the new cases.

**`LogViewModel.rows`** — map both to `LogRow`, and **`LogRowText.describe(_ row:)`** — the
same wordings as issue 02 but naming the Pawn's `label`.

## The silence is the point

The recorder must respect `session.isRecordingSuspended`, exactly as `comment`
(`Session.swift:43`) and `pawnMoved` (`:54`) do — `guard !session.isRecordingSuspended else
{ return [] }`. During a fight this write is dropped and issue 02's `Change` is the one that
lands. ADR-0014: exactly one recorder is live.

## Tests

`SessionLogTests` — round-trip both, with and without a DC; an unknown `line` still decodes
to `.unrecognised`.

`AppStateSessionTests` — a Roll recorded during an Encounter writes **nothing** to the
Session Log; the same Roll outside one writes exactly one line.

`LogViewModelTests` / `LogRowTextTests` — both render, at the right indent.

## Done when

A Roll outside a fight appears in the Log View, and the same call during a fight does not.
