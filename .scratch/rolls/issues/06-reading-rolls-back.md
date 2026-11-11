# 06 — Reading Rolls back

Status: ready-for-agent
Blocked by: 02, 03

The Log View end to end, once Rolls exist in both files.

Issues 02 and 03 each added their own rendering. This one checks the seam between them: a
Roll before a fight, a Roll during it, and a Roll after, read as one evening.

## What to check

`LogViewModel.rows` splices an Encounter's lines into the hole its `encounterStarted` pointer
marks (ADR-0016, file order, no timestamps compared). A Roll is the first record type that
can appear on **both** sides of that seam, so it is the first that can look inconsistent
across it.

- The two wordings must agree. A DEX save reads the same whether it came from a `Change` or a
  `SessionLine` — same phrasing, same arithmetic, same verdict. Only the name differs in
  provenance (a Combatant's snapshot name vs the Pawn's `label` snapshot).
- Indent, timestamp, font and colour (`LogViewModel.indent`, `LogView.swift:246-274`) —
  decide where a Roll sits. It is a record like `.moved`, not a heading, so it should follow
  whatever `.moved` does on each side.
- A live fight reads from `Encounter.lines` in memory (`LogViewModel.swift:127-130`), so a
  Roll must appear the instant it is recorded, not when the Turn ends. Confirm this — it is
  the one place a Roll differs from a Turn, which only appears on `endTurn`.

## Tests

`LogViewTests` / `LogViewModelTests` — an evening containing a Roll outside a fight, an
Encounter with a Roll inside it, and a Roll after it ends, rendering in file order with the
fight spliced at its pointer.

A Roll inside a Turn that is later the target of a Correction still reads — the Correction
moves under its Turn (ADR-0016's one departure from file order) and must not orphan the Roll.

## Done when

An evening with Rolls on both sides of a fight reads as one narrative.
