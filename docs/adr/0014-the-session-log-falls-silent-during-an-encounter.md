# The Session Log falls silent during an Encounter

A **Session** is the evening; an **Encounter** is one fight inside it. Both record what
happened, and the obvious question is what happens to the Session Log when a fight starts.

It stops. The Session Log writes one line naming the Encounter's Combat Log file and records
nothing further until the fight ends. Exactly one recorder is live at any instant.

## Two recorders would both be right

ADR-0008 made the Combat Log the state of a fight: append-only, one line per Turn, every
Change carrying before and after. It already records Pawn movement — `.moved`, one Change per
completed drag, with `from`, `to` and the distance between them (`AppState+Combat.swift:221`).

The Session Log records movements too, because a party walking a corridor between fights is
exactly the thing this feature exists to capture. So during a fight both logs have a claim on
the same drag, and there are three ways to settle it:

**Both record it.** Now a movement exists twice, in two files, in two vocabularies, and every
future reader has to know which one to believe. They cannot disagree today, and they will
disagree the first time one of the two write paths is changed and the other is not.

**The Session Log records the non-combat subset** — movement goes to the Combat Log, comments
and light switches to the Session Log. This is the version that sounds tidy and is not: it
splits one evening's record across two files by a rule nobody can state from memory, and
"which file is this in" becomes a question with a per-event answer.

**The Session Log stops.** The rule is one sentence, the same sentence in every case, and it
is checkable from the file itself: between the `encounterStarted` line and the next line, this
file says nothing, and the file it names says everything.

## What it costs

Reading an evening end to end means following a pointer. The Session Log is not a single
readable narrative of the night; it is a narrative with holes, each hole labelled with the
file that fills it. A tool that wants the whole evening has to open several files and
interleave them by timestamp.

We are choosing that cost deliberately, because the alternative cost — two files that are each
*almost* the truth — is worse and is paid by a human at a table rather than by a program.

There is a smaller cost at the Comment Bar. Because the Session Log is closed during a fight,
the Comment Bar is disabled during a fight, and the DM types into the Combat tab's note box
instead. That is a control going dead mid-evening, and it was argued against: the field could
stay live and route its text to whichever log is open. It was rejected because the two are not
the same thing — a Comment is about the moment and has no target, a note is a Change on a
Combatant's Turn — and one field quietly producing two different records is the ambiguity this
decision exists to remove. The Comment Bar's placeholder says where to type instead.

## Consequences

`<map>.combat/*.jsonl` is untouched. ADR-0008, ADR-0009 and ADR-0010 keep every promise they
made, including that a Combat Log is readable on its own, and no shipped, table-verified code
is migrated.

The Session Log gets its own line vocabulary rather than reusing `Change` or `LogLine`.
`Change` is keyed on `combatantID` throughout and a Pawn moving outside a fight has no
Combatant; `LogLine` is shaped around Rounds and Turns, which a Session has neither of. The
JSONL discipline is shared — append one line, `synchronize()`, drop a malformed final line —
and the vocabulary is not.

Anything recorded in neither log is recorded nowhere, and for now that is most things. The
first version records movements and Comments only: Lights doused, Blackout, Solo Sight, Pawns
added or deleted, Walls and Grid changes are not Session Log lines. That is a deliberate first
cut rather than an oversight — a DM who needs the darkness remembered types a Comment about
it, and JSONL takes new line types additively.

## Considered Options

- **Both logs record everything** — rejected: two records of one event that can only ever
  drift apart, and no rule for which is authoritative.
- **Split by event type, both logs open** — rejected: the rule is per-event and cannot be
  stated in a sentence, so "which file is this in" has no memorable answer.
- **The Session Log absorbs everything; Encounters stop writing their own files** — rejected,
  though it is the cleanest model in the abstract. It rewrites shipped code that has been
  verified at a table, it breaks the ADR-0008 promise that a `.combat/` file stands alone, and
  it buys a single-file evening at the price of a migration.
- **The Comment Bar stays live during a fight and routes to the Combat Log** — rejected: a
  Comment and a Turn note differ in what they are about, and one control producing either
  depending on hidden state is the ambiguity this decision removes. Revisit if the dead field
  proves worse at the table than the argument predicts.
