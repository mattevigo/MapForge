# Corrections are appended, never edited

Halfway through Round 4 the DM realises they forgot to apply the goblin's damage two Rounds
ago. They need to go back and fix it. Every tracker offers this and the obvious implementation
— find the number, change it — is unavailable here, because ADR-0008 made the Combat Log
append-only and a Turn's line is already on disk.

## The button goes back; the pointer does not

The instinct is a Previous button that is the mirror of Next: it moves the turn pointer back,
and you carry on from there. That breaks immediately on a question with no good answer — what
happens to the Turns already logged after the one you returned to? Discarding them contradicts
append-only. Keeping them means the Log contains two Round 3 goblin Turns, and a replay cannot
tell which one happened.

So the pointer does not move. What moves is a **correction cursor**: Previous walks backwards
through Turns that have already ended, and while it is away from the live Turn the tracker
says so plainly — *correcting Round 2, Grog's turn* — and every edit made writes a
`correction` line naming that Turn. Next walks the cursor forward until it arrives back at the
live Turn, and then Next is Next again.

One button pair, two meanings, and the mode is on screen the whole time. Ending a Turn while
the cursor is in the past is refused rather than reinterpreted: the DM returns to live first.
Two buttons that each do one thing was considered and is worse — four combat buttons in a
236-point-wide panel, two of which are dark most of the time.

## The amended Turn's line is never touched

A Correction is a new line: the Turn it targets, and the Changes being made to it. Reading the
Log folds Corrections onto their Turns. The original line stays exactly as it was written.

This is the point of the feature rather than a constraint on it. "You can go back and add a
note, never delete one" was the requirement, and a Log that can be silently amended does not
satisfy it — what happened at the table and what the DM later decided should have happened are
different facts, and a campaign record that cannot tell them apart has lost the more
interesting one.

## Movement cannot be corrected

Hit points, Conditions and notes can be corrected. A `moved` Change cannot.

Where a Pawn stands is the Map's own state, visible on two screens and already saved. A
retroactive move would make the fold disagree with the Map, and there is no way to reconcile
them: the token is where it is. A DM who moved the wrong Pawn moves it back, which is a real
movement in the present and is logged as one.

## Consequences

The Change vocabulary is shared between Turn lines and Correction lines, with movement
excluded from the latter. One type, two contexts, one rule about which subset applies.

A correction cursor is state the tracker must display unmistakably, because an edit made in
the wrong mode is silent and wrong. This is the most dangerous interaction in the feature and
deserves the loudest treatment in the panel.

Folding on read is now non-trivial: a reader must accumulate Corrections by target before
applying a Turn's own Changes, and Corrections can target any earlier Turn including ones
already corrected. The fold is a pure function over the file and should be tested as one,
separately from anything that opens a file.

Nothing is ever deleted from the Log, so a long fight with a fumbling DM produces a long file.
At one line per Turn plus occasional Corrections, a four-hour session is some hundreds of
lines. This is not a problem worth engineering against.

## Considered Options

- **A true pointer rewind** — rejected above: it makes the Log ambiguous about what happened.
- **Rewriting the target Turn's line in place** — rejected: it forfeits append-only, it
  requires rewriting the file, and it destroys the distinction the feature exists to keep.
- **Previous limited to the immediately preceding Turn** — rejected as too weak. It handles
  "I forgot the goblin's damage" and not "I have been forgetting it since Round 1", and the
  cursor costs nothing extra once the correction mechanism exists.
- **Correcting by clicking a Turn in a timeline list** — rejected for now, and it is the
  better long-term answer. It needs a timeline view, which is most of the replay UI ADR-0008
  deferred. The cursor reaches every Turn with two buttons and no new view, and a timeline can
  replace it later without changing a byte of the format.
- **A free-text "the DM says this actually happened" amendment** — rejected: it records the
  correction without applying it, so the fold stays wrong and the tracker still shows the
  goblin at full health.
