# The Log View splices, it does not merge

ADR-0014 left a tool unwritten and named it: "a tool that wants the whole evening has to open
several files and interleave them by timestamp." The **Log View** is that tool, and it does not
interleave them by timestamp.

It reads in **file order**. Each Encounter's Turns are spliced into the hole its
`encounterStarted` Line marks, and no two timestamps are ever compared.

## Why the predicted merge is unnecessary

ADR-0014's own rule removes the problem it anticipated. While an Encounter runs the Session Log
writes **nothing** — so there is nothing to interleave the fight *with*. The hole in the Session
Log is exactly the Encounter's extent, and the Combat Log's lines are already in order among
themselves. Concatenating at the pointer is not an approximation of a merge; it is the same
answer, reached without a comparison.

Merging by timestamp would also be worse than unnecessary. A `turn` Line carries only `endedAt`
— the moment the Turn *finished* — so a timestamp sort orders fights by when each Turn stopped,
which is not the order a DM watched them in. And `SessionLine.unrecognised`, the case a Line
written by a later version decodes to, carries **no timestamp at all**: the decoder discards the
whole container. A merge would have to invent a position for it. A splice already knows one.

## The one departure from file order

**Corrections move.** A Correction is appended at the end of the Combat Log but targets an
earlier Turn, and the Log View draws it beneath that Turn, marked as a Correction rather than
folded into it.

This is ADR-0010's requirement, not a convenience: that ADR made Corrections append-only so
"what happened at the table stays readable next to what the DM later wished had happened", and
*next to* is only true if they are adjacent. Rendering a Correction at the file's end satisfies
the letter of file order and defeats the reason it exists.

A Correction naming a Turn that is not in the file is drawn where the file put it, marked as an
orphan. `CombatLogFold` silently ignores such a line, which is right for computing state and
wrong for reading history.

## Nothing is dropped silently

The reader already drops what it cannot parse: `SessionLogReader.read` `compactMap`s malformed
lines away, and `.unrecognised` loses every field it had. The Log View renders a marked
placeholder in position instead. A log that quietly omits what it could not read is a log that
lies about the evening, and position is the one fact such a Line still carries.

The same rule covers a combat pointer that cannot be resolved: the Encounter renders as a marked
Line saying its fight could not be read, rather than vanishing and leaving a gap nobody can see.

## Maps are named by Workspace-relative path

Resolving `encounterStarted`'s `logFile` — a bare file name — requires first resolving the Line's
`map`, and `map` was itself only a file name. Two Maps called `dungeon.png` in different
subfolders made the join ambiguous, and a wrong answer looks exactly like a right one.

`SessionLine.map` therefore becomes a path relative to the **Workspace root**, not an absolute
one: ADR-0012 keeps the Workspace portable, and an absolute path breaks the moment it is opened
on another Mac. A relative path survives the move, disambiguates same-named Maps, and stays
greppable, which is what ADR-0015 wanted the field for.

**This breaks the format, deliberately, in the window where it is free.** The Session Log shipped
today and no `.jsonl` written by it exists on disk; the Log View reads only the current Session
in any case. A Line written before this change reads as unresolvable. Taking the break now costs
nothing and taking it later costs a migration.

It stops short of a stable Map ID, which is the only thing that would survive a DM reorganising
their Maps inside the Workspace. Maps have no ID today, inventing one is a larger change than
this view earns, and a path is strictly better than what it replaces.

## What it costs

Opening the Log View reads every Combat Log the Session points at, and re-reads them on every
append while it stays open. A Session is a few hundred Lines and a fight a few dozen, so this is
microseconds, and caching finished Encounters is available later as a pure optimisation that
changes no design. We are choosing the cost knowingly rather than paying for an invalidation
rule this feature does not otherwise need.

A Map switch still writes no Line, so the Log View infers one from consecutive Lines disagreeing
on `map` and draws a separator. A switch that happens while nothing else is recorded stays
invisible. That is a gap in the format, not in the view, and it is not worth a format change to
close.
