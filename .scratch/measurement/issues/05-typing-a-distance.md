# 05 — Typing a distance

Status: ready-for-agent
Blocked by: 03, 04

With a Measurement armed, type `9` and press Return: a 9 m projection in the direction of the
cursor, from the Origin. The exact-range affordance — no hunting for a pixel that happens to
be 9 m away.

**Do this last.** It is the one mechanism here with a bad track record in this codebase, and
issues 01–04 deliver specs 1–5 and 7 without it. If it goes wrong it is cut without stranding
anything.

## Why it is risky

SwiftUI focus does not reach these overlays — position-based `ZStack`s carry no focusable
region — so keyboard work goes through process-global `NSEvent` monitors.
`DeleteKey.swift:71-73` exists *solely* because such a monitor ate keystrokes belonging to a
text field: typing in a pawn label deleted geometry mid-word.

Digits collide with far more than ⌫. "Grid squares wide" and every pawn label are
digit-friendly fields in the same window.

## Three gates, all required

1. **Armed only.** The monitor is installed only while a Measurement exists, and torn down
   with it. Much narrower than `DeleteKey`'s always-on monitor.
2. **Frame-scoped**, following `ScrollWheel.swift:61` (scoped by frame) rather than
   `DeleteKey.swift:62` (scoped by window) — the map, not the whole Control Window.
3. **Text-field-declining.** Copy `DeleteKey.swift:71-73` verbatim: return the event
   untouched if the first responder is an `NSTextInputClient` or the window's field editor.

Use the `Handler` reference-class indirection from both files (`DeleteKey.swift:28-36`,
`ScrollWheel.swift:29-32`), refreshed every render. Both carry comments about the
stale-closure capture bug that motivated it.

## Behaviour

- Digits accumulate; Return commits. Escape and right-click both abandon.
- Backspace edits the buffer — and this is precisely the collision `DeleteKey` warns about,
  so make sure the two monitors cannot both act on one keystroke.
- The typed number is in **metres**, converted to `Squares` by the issue-01 unit. It is
  **not** snapped — you typed it, you meant it.
- Direction comes from the live cursor (issue 02's hover), so a committed typed Measurement
  still swings with the mouse until dismissed. This is the point: exact range, chosen
  direction.
- Show the buffer as it is typed, so a mis-key is visible before Return. The readout capsule
  from issue 03 is the natural home.
- Radius shapes ignore direction; Cone and Line use it.

## Tests

- The three gates, each independently: not armed, outside the frame, text field focused —
  each leaves the event untouched. These are the regression tests that matter more than the
  feature.
- Buffer accumulation, Return commits, Escape abandons.
- Typed distances bypass snapping; dragged ones do not.
- Backspace does not simultaneously delete a selected fog object.

## Done when

Spec 6 works and the three gates are proven by test. If the gates cannot be made to hold,
cut this issue rather than shipping a monitor that eats keystrokes — the feature is complete
without it.
