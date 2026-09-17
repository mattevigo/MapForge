# Log View: read the evening back

Status: closed 2026-09-16 — all five issues done; 933 unit tests green. Reviewed on both axes; the follow-release scroll maths was wrong on first pass and is fixed with `LogViewPolicy.isFollowing` plus four tests. UI tests compile but could not run: the runner times out enabling automation mode on this machine, which blocks the whole existing suite (see `.scratch/ui-tests-never-ran/`).

MapForge writes two logs and shows neither. The Session Log records the evening's Comments and
movements; the Combat Log records every Turn of every fight. Both are append-only JSONL a human
*could* read in a text editor, and both features shipped with a reading UI explicitly out of
scope — the Session Log spec called the Comment Bar "a write-only control", and the initiative
tracker's spec deferred a timeline with the note that it "is the better long-term answer and
changes no bytes."

This feature is that timeline. A **Log View** replaces the Map in the Control Window and shows
the current Session, fights included.

See `CONTEXT.md` for the terms — Log View, Line, Session, Session Log, Combat Log, Turn, Round,
Change, Correction, Setup Toolbar, Live Toolbar — and:

- `docs/adr/0016-the-log-view-splices-it-does-not-merge.md` — file order, not timestamps; the
  Correction exception; the Map path change
- `docs/adr/0014-the-session-log-falls-silent-during-an-encounter.md` — why there is a hole to
  splice into at all
- `docs/adr/0010-corrections-are-appended-never-edited.md` — why a Correction is drawn next to
  its Turn rather than folded onto it

## The shape of it

A **Log** toggle joins the Setup Toolbar's second row, on the right, past the `Spacer()` that
today ends that row — the one row in the window with a free right edge. It is a
`.toggleStyle(.button)` Toggle bound to its own state, not a fourth `PreviewMode`: nothing about
reading the log is exclusive with having Grid Fit armed, and a mode case would grow a
not-applicable branch in every `switch` in the file. The Viewport toggle set this precedent —
"a toggle, not a mode".

While it is on, the Log View takes the place of **the Map preview and the Live Toolbar** in the
right column. The Live Panel keeps its column and the Comment Bar keeps its row. **Add**,
**Fit Grid…** and **Edit Fog…** disable together — all three act on a Map that is not on screen —
and the mode hint row, already fixed-height and already reserved for explaining the current mode,
says why.

The Session control is gone while reading. That is the point of replacing the Live Toolbar: every
switch on it changes what the players are looking at, and a DM reaching for one has already
decided to look at the Map again.

## What it shows

The current Session and no other. Four states:

- **No Workspace** — there is nowhere a Session could have been written.
- **No Session** — nothing is recording; Start Session is what fills this.
- **Recording, nothing yet** — distinct from the above *on purpose*. "Am I actually recording?"
  is the question this view exists to answer, and collapsing these two states hides the answer.
- **Lines.**

Oldest at the top, newest at the bottom. The scroll view opens at the bottom and **follows** it
as Lines arrive, until the DM scrolls up — then it stops following until they scroll back down.
The chat-app behaviour: a DM who has scrolled up to check Round 2 is not yanked away by a pawn
drag, and a DM sitting at the bottom always sees the newest.

## Rules worth stating once

- **File order. Never timestamps.** ADR-0016. Each Encounter's Turns go into the hole its
  `encounterStarted` Line marks, and no two times are ever compared. ADR-0014's silence rule
  means there is nothing to interleave with.
- **Corrections move, and only Corrections.** Drawn beneath the Turn they target, marked. The one
  departure from file order, and it is what ADR-0010 bought append-only Corrections *for*. An
  orphan Correction — naming a Turn not in the file — is drawn where the file put it, marked as
  an orphan, rather than ignored the way the fold ignores it.
- **Nothing is dropped silently.** An `unrecognised` Line, a malformed Line, an unresolvable
  combat pointer: each draws a marked placeholder in position. `SessionLine.unrecognised` carries
  no timestamp at all — position is the only fact it has left, which is a second reason file
  order is the right spine.
- **Rounds group Turns; Turns group Changes.** A Round heading, the Turns beneath it, each Turn's
  Changes beneath that. The structure is free in the data and it is how a DM thinks about a fight.
- **Before → after, not deltas.** "HP 22 → 15", not "took 7 damage". ADR-0008 refused to store a
  delta and it would be perverse for the view that renders Corrections to invent one.
  `orderChanged` is the exception: a list of UUIDs renders as "Order changed".
- **Empty Turns appear.** A Turn with no Changes is information — a run of them is the answer to
  "when did the ogre stop doing anything" — and hiding them makes the Round's turn count wrong.
- **Distances in metres**, via Distance Unit. `distanceSquares` is stored in squares; the glossary
  already decided that a distance shown to a human gets the unit applied.
- **A Map change draws a separator**, derived at read time from consecutive Lines disagreeing on
  `map`. Nothing records a Map switch, so a switch with no Line on either side of it stays
  invisible. That is a gap in the format, not worth a format change to close.
- **Re-read on every append.** The Session holds no Lines in memory — unlike the Encounter — so
  the file is the truth. Appends are rare and the files are small. Caching finished Encounters is
  a later optimisation that changes no design.

## The format change

`SessionLine.map` becomes a **Workspace-relative path** rather than a bare file name, so that
resolving an Encounter's Combat Log is unambiguous. Relative, not absolute: ADR-0012 keeps the
Workspace portable.

**No backward compatibility.** The Session Log shipped on 2026-09-16 and no `.jsonl` it wrote
exists on disk; the Log View reads only the current Session in any case. A Line written before
this change reads as unresolvable. Taking the break now is free and taking it later is a
migration.

## Out of scope

- **Older Sessions.** A campaign history wants search, export and per-map filtering — a different
  feature with different questions.
- **Editing.** A mistake in a Log is answered by a Correction, and Corrections are made in the
  Combat tab.
- **A stable Map ID.** It is the only thing that would survive a DM reorganising Maps inside the
  Workspace, and it is a larger change than this view earns.
- **Caching parsed Combat Logs.** Available later, changes nothing.
