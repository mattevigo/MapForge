# 06 — Cleanup carried over from shipping Measurement

Status: needs-triage

Debt knowingly left when the feature merged. None of it blocks use; all of it was surfaced
by the code review or by bugs found in play, and is recorded here rather than in a commit
message nobody will read again.

## Missing tests

Issues 03 and 04 listed tests that were never written. The behaviour works and was checked
by hand, but it is unproven:

- Both screens project the same Measurement to the same map-space polygon.
- An anchored Measurement's apex sits on its Pawn's centre in the mirror (the rebased-frame
  case).
- The shape is sticky across Measurements; changing it re-projects in place.
- The menu is unavailable without a declared Grid.
- **A UI test that a Measurement appears and is dismissed**, following
  `MapForgeUITests/FogEditingUITests.swift`.

The UI test is the one that matters most. Three separate coordinate-space bugs shipped
during this feature and **no unit test could have caught any of them** — the arithmetic was
correct every time and the view handed it the wrong frame. A UI test is the only level that
sees that class of defect. See the note on `PlayerPlacement.mapPoint(_:map:frame:)`.

## Three copies of the local event monitor

`RightClick.swift`, `ScrollWheel.swift` and `DeleteKey.swift` are near-identical: the same
`Handler` reference class refreshed every render, the same window or frame scoping, the same
install/teardown. `MeasurementKeys.swift` is a fourth partial copy. A shared
`LocalEventMonitorModifier(matching:)` would collapse them.

Deliberately not done while shipping: each one carries a long comment explaining a bug it
exists to prevent, and merging them without preserving that reasoning would lose more than
the duplication costs.

## No `Squares` type

Issue 01 asked for a distance value type wrapping a count of Grid squares. `DistanceUnit`
centralises the 1.5 and nothing else imports it, so the Done-when was met in substance — but
`Measurement.distance`, `chainSquares` and `Buffer.squares(in:)` all pass bare `CGFloat`s
that are indistinguishable from metres at the call site. `MapPoint` exists for exactly this
reason on the position side.

## Right-click carries four meanings

Open the shape menu, finish a chain, disarm an armed tool, pin or unpin the shape under the
cursor. Each is unambiguous on its own — resolved by what is under the pointer or which
state the tool is in — but it is a lot on one button, and it grew one meaning at a time
rather than being designed that way. Worth revisiting if it reads as unpredictable in play.

## `fdda4f7` has a misleading message

That commit reordered the input modifiers above `.clipped()`/`.position()` on a diagnosis
that turned out to be wrong. The reorder is harmless and arguably tidier, but its message
confidently explains a bug that was not the bug. `8f9794e` has the real finding.
