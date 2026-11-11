# 04 — The Comment Bar

Status: done

The full-width row beneath the Map: one text field, one send button, three states.

Depends on 03.

## What to build

**A policy seam first.** `MapForge/CommentBar.swift` holds the state decision as a pure
function, testable without a view — following `ViewportToggle.swift`'s precedent, which exists
for exactly this reason:

```swift
enum CommentBarState: Equatable {
    case noSession        // "Start the session to record"
    case recording        // "what happened"
    case duringEncounter  // "Note on <name>'s turn — use the Combat tab"

    var isEnabled: Bool { self == .recording }
    var placeholder: String { ... }
}

enum CommentBarPolicy {
    static func state(session: Session?, encounter: Encounter?,
                      activeCombatantName: String?) -> CommentBarState
}
```

`duringEncounter` wins over `noSession` only when a Session exists — with no Session and a
fight somehow running, the bar still reads `noSession`, because that is the honest instruction.

**The view.** A `CommentBar` view: `TextField` + a send button
(`arrow.up.circle.fill`, mirroring `StatEditor.notesBox`'s button at `StatEditor.swift:155-193`).
Return submits via `.onSubmit`. Both disabled together per Q18 — the button greys, it does not
vanish. Accessibility identifiers `comment-field` and `send-comment`, matching the
`note-field`/`add-note` convention.

**Placement.** In `ControlView.body`'s outer `VStack`, **after** the
`HStack { preview; livePanel }` at `ControlView.swift:267-270` — the first thing ever to sit
below the Map.

⚠️ **Height.** `preview` is `.frame(maxHeight: .infinity)` and claims what is left. The
Comment Bar must be **fixed height in all three states**, or the Map resizes when a fight
starts — the exact failure `ChromeHeightTests` and `PreviewContainerStabilityTests` guard for
the rows above. The placeholder changes; the frame must not. A one-line `TextField` with no
`axis: .vertical` (unlike `notesBox`, which grows to three lines) is what keeps this true.

**Visibility.** Always shown, in every mode including the Wall Editor — the Setup Toolbar is
not disabled by a Session (Q7/soft boundary) and the converse holds too: a Comment is typeable
while tracing a wall, if a Session is running.

⚠️ **Not gated on a Map.** An earlier draft of this issue said "whenever a Map is open", which
contradicts ADR-0015 and the spec: a Session needs a Workspace and not a Map, and *"a Comment
typed before the crypt is opened is still part of the evening"*. Gating on the Map would also
make the bar appear and disappear with it — a height change, which is the one thing this row
must never do.

## Tests

`MapForgeTests/CommentBarTests.swift` — the policy, exhaustively:

- `state(session: nil, encounter: nil, …) == .noSession`
- `state(session: live, encounter: nil, …) == .recording`
- `state(session: live, encounter: live, …) == .duringEncounter`
- `state(session: nil, encounter: live, …) == .noSession` — the honest instruction
- `isEnabled` is true only for `.recording`.
- The `duringEncounter` placeholder names the active Combatant, and degrades gracefully when
  `activeCombatantName` is nil.

`MapForgeTests/ChromeHeightTests.swift` — extend if it can assert below-Map chrome; otherwise a
new `CommentBarHeightTests` asserting the bar's height is equal across all three states.

A UI test in `MapForgeUITests`: with a Session running, type into `comment-field`, press
Return, and assert the field clears. Starting a fight disables it.

## Acceptance

The field is dead before a Session, live during one, dead again during a fight, and says which
in its placeholder each time. The Map does not move by a single point as those states change.
