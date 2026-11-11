# Combat is an append-only turn log

An Encounter has to be recorded. Not for the app's sake — for the DM's, who wants to know
next week what the party did to the ogre, and who wants, eventually, to replay a fight rather
than remember it. That requirement decides the shape of everything else in the feature.

The app's only existing history is `FogEdits`: an array of whole `FogDocument` snapshots,
each the state before an action, thrown away when the fog mode closes. It is the right tool
for its job and the wrong one for this. A combat's record must outlive the session, must be
readable by a human a week later, and must never lose what actually happened when the DM
decides it should have happened differently.

## The log is the state, not a copy of it

The alternative was a live `Encounter` model treated as authoritative, writing a log
alongside it as a record. It is the smaller change and it was rejected, because a state model
and a record of how that state was reached are two things that must agree forever, with
nothing forcing them to. The first bug where the log says 14 hit points and the tracker says
9 is unfindable and uncorrectable: neither is wrong, they simply drifted.

So the Combat Log holds the truth and the tracker is a fold over it. Current hit points are
not stored anywhere; they are what you get by replaying every Change. This is what makes
replay exact rather than approximate, and it is why every Change records the value **before
and after** rather than a delta — a fold of deltas cannot be corrected without recomputing
everything downstream, and a fold of before/after pairs can.

## One line per Turn, not one line per Change

The file is JSONL, one JSON object per line, and each line is a **Turn**: its Round, its
Combatant, and an array of every Change made while it ran. Written when the Turn ends.

Event-grained lines — one per hit point edit — are the purer form and were rejected for
readability. A DM opening this file wants to read it, and a Turn is the unit they think in.
Grouping event lines back into Turns on read is work the writer can simply do once.

The cost is that a Turn's line cannot be written until the Turn ends, so live state is a fold
over the written lines **plus an in-memory buffer** of the current Turn's Changes. This is
event sourcing with a write-behind buffer, not the pure form: durability lags reality by at
most one Turn. A crash mid-fight loses the Turn in progress, which is the smallest unit a DM
can reconstruct from memory anyway, and is what "saved at the end of the turn" already meant.

## JSONL, one file per Encounter

A Map accumulates Encounters, and the obvious home for them is one JSON file holding an array
of all of them. That cannot be appended to — adding an element means rewriting the file — and
rewriting a file you also crash-append to is how logs get corrupted. JSONL appends a line and
`fsync`s, and a truncated final line costs the Turn that was being written and nothing else.

So: one file per Encounter, named by the timestamp it started. Not named by the DM, because a
modal asking "what shall we call this fight?" arrives at the exact moment the table is
waiting for initiative; a timestamp is always available and always correct, and renaming is
a thing that can happen later or never.

## Consequences

Every mutation in combat becomes a Change with a type, and there is no "just set the hit
points" shortcut anywhere. This is the real cost and it should be felt as one: a field the UI
writes directly is a field the Log does not know about, which makes the Log wrong, which
makes replay wrong. The Change vocabulary is the write API.

Non-deterministic ordering becomes impossible. The Order cannot be recomputed from Initiative
on read — two Combatants on 14 would sort arbitrarily — so the Order is itself recorded, both
in the line that opens the Encounter and in an `orderChanged` Change whenever the DM
rearranges it. See ADR-0010.

Replay has no user interface in the first version. The format is the irreversible part and
the timeline UI is not; building the format so replay is possible and shipping no replay is
the trade that gets combat to the table soonest without foreclosing anything.

## Considered Options

- **A live model with a derived log** — rejected above: two things that must agree, with
  nothing making them.
- **One line per Change** — rejected: a DM reads this file, and the Turn is the unit they
  read in. Nothing stops a future reader grouping differently; the data is the same.
- **One JSON file holding every Encounter as an array** — rejected: not appendable, and
  rewriting it forfeits the crash-safety that made a log file worth having.
- **Snapshots per Turn instead of Changes** — rejected. It is what `FogEdits` does and it
  would work, but a snapshot cannot answer "what did the party do", only "what was true
  afterwards", and the question the DM asked for is the first one.
- **SQLite** — rejected: a real answer to appendability and corruption, and wrong for a file
  a DM should be able to open, read, and put in a git repository next to their maps.
