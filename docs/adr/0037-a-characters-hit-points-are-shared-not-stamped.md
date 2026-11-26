# A Character's hit points are shared, not stamped

A party walks from the cellar to the street. On the cellar's Map Durga ended the fight at
12 of 48 hit points; on the street's Map she is at 48, because she was stamped there fresh,
or at whatever she had the last time the party stood in that street. A Stat Block lives
beside its Map, keyed by `Pawn.ID` (ADR-0009), and a Pawn is a copy of its Character taken at
the Stamp (ADR-0007), so a hero's wounds are a property of the battle map they happened on.
The DM keeps the real number in their head and retypes it on every Map. The same drift
ADR-0024 removed for a Character's definition — two copies that disagree — was left in place
for what the evening does to it.

## The link ADR-0007 refused, for three fields

A Character with a note now carries its **current and temporary hit points and its
exhaustion level**, kept by the app in the Workspace beside the Party. A Player Pawn stamped
from it does not hold copies of these: it reads and writes them through its `characterID`.
Every Pawn of Durga, on every Map, shows the same 12 of 48, and healing her on one Map heals
her on all of them.

That is exactly the link ADR-0007 rejected, and its reason still holds for everything else.
`<map>.fog.json` remains readable without a roster, because none of these fields was ever in
it (ADR-0009). What changes is that `stats.json` is no longer the whole truth about a Player
Pawn: for three fields it defers to the Character. ADR-0007 called the rename a link buys "a
thing a DM does approximately never"; a party carrying its wounds from one room to the next
is a thing a DM does every session.

Copying at the edges — a Stamp copying the Character's current numbers in, a fight ending
copying them back, a Map opening refreshing its Player Pawns — was the alternative that kept
ADR-0007 intact in name. It was rejected because it is two copies again, with a rule for
keeping them in step that has to be right at every edge, and an unanswerable case where it is
not: two Pawns of Durga end up at different numbers, and nothing says which one is her.

## What stays the Pawn's

Conditions and concentration are not shared. Prone on the cellar's Map means nothing on the
street's, and since Conditions expire on nobody's schedule, carrying them would make every
one stick until the DM remembered it on a Map where it had never been applied. Armour class,
maximum hit points and initiative bonus are the note's, as before (ADR-0024).

A Character with **no note** has no shared numbers. Its Pawns keep their own Stat Blocks as
today. Sharing a current total without a shared maximum would make the Health Bar's fraction
depend on which Map it was drawn on, and linking a note is one step in the roster.

A Pawn whose Character is deleted keeps the numbers it last showed on its own Map, so the
Pawn's own Stat Block is still written alongside the Character's. ADR-0007 promised that such
a Pawn loses a badge and nothing else; dropping its hit points would break that promise in
the one place a DM would notice.

Two Pawns of one Character share one set of numbers. ADR-0007 kept repeated Stamps for "a
mirror image or a summon", but a summon or a Simulacrum is a Creature placed by hand, and the
duplicates of the Mirror Image spell have no hit points to track.

## The Combat Log stays authoritative during a fight

ADR-0008 is unchanged: while an Encounter runs, a Player's numbers are what the Log folds to,
and every edit is a Change. Stopping the fight writes the result to the Character rather than
to the Map's `stats.json`.

A fight is paused, not stopped, when the DM opens another Map, and the Character can be healed
or hurt on that other Map meanwhile. When the paused fight resumes, the Character wins: each
shared number that moved is recorded as a Change in the resumed Turn, so the Log and the
Character agree and the Log says what happened. Letting the Log win would silently undo the
DM's heal; refusing edits to a Character in a paused fight would block the DM at the table
over a fight nobody is running.

## Consequences

Without a reset, persistence turns every session's start into five manual edits. A **Long
Rest** on the Party restores every Character with a note to its maximum hit points, clears its
temporary hit points and lowers its exhaustion by one, as the 2024 rules do. It covers only the active Party, asks
first, and is refused while a fight runs on the open Map. A short rest has no gesture: its
healing is Hit Dice the players roll.

Changes to a Character's shared numbers made outside a fight, and every Long Rest, are written
to the Session Log while a Session runs. They used to go unrecorded, which was harmless while
a Stat Block was local to one Map's battle. Once wounds travel, they are part of the evening,
and the Session Log is what the DM Realm import reads.

The Party roster shows each Character's numbers with the DM's Health Bar, since a Character
now has a current state to show.

When this first ships no Character has numbers yet. Each starts at full — its note's maximum,
no temporary hit points, no exhaustion — rather than taking the numbers of whichever linked
Pawn the app happened to open first. A release lands between sessions, usually after a rest,
and a real exception is one edit.

`Pawn.characterID` is no longer purely advisory. Drawing, fog, lighting and discovery still
never branch on it; the Stat Block of a Player Pawn now does.

## Considered Options

- **Copies at the edges** — rejected above: two copies with a rule to keep them in step, and
  no answer when two Pawns of one Character disagree.
- **Write the numbers into the Character's note** — rejected: a number that changes several
  times a minute would make MapForge an editor of the DM's prose, and the notes are where the
  definition is written (ADR-0024), not the evening. The DM Realm import carries the evening's
  record into the notes at the end of a Session.
- **Keep them per Map and let the notes' Party State reconcile them later** — rejected: it
  leaves two Maps disagreeing about Durga during the session, which is when the DM needs one
  answer.
- **Share Conditions and concentration too** — rejected above.
- **Share numbers for a Character without a note** — rejected above.
- **A way to cut one Pawn loose from its Character** — not built: no case the table meets
  needs it yet.
- **On resume, the Log wins / edits are refused** — rejected above.
