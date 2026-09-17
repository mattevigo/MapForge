# A Roll is recorded, not resolved

A DM wants next week to know that the rogue failed the Dexterity save in Round 3. Today the
app has nowhere to put that: the Combat Log records mutations to a Stat Block, and a Roll
mutates nothing.

Two things follow from that sentence, and they are the whole decision: a Roll is a `Change`
despite changing nothing, and the app does not know enough to compute one.

## A Roll is a `Change`, and the fold ignores it

ADR-0008 made the tracker a fold over the Combat Log and said every `Change` carries the
value before and after. A Roll has no before and no after. That reads like a reason to give
Rolls their own `LogLine` case, and it is not.

`LogLine`'s `Kind` is a plain `Codable` enum: an unknown `line` value **throws**, and
`CombatLogStore` drops the line with `try?`. A new top-level line type is therefore a silent
data-loss bug for any build older than the one that wrote it. `Change`'s `Kind` decodes an
unknown `type` to `.unrecognised` and keeps reading (`CombatLog.swift:94-97`). One of these
two vocabularies is extensible and the other is not, and the file format is the thing we are
least able to change later.

The invariant survives because it was always narrower than its wording. `Change.moved` and
`Change.noteAdded` already carry no before/after, and `CombatLogFold.apply` already skips
both with a comment saying why: "Recorded for the record, not for the state"
(`CombatLogFold.swift:185-189`). A Roll is the third member of a category that already
existed and had simply never been named. So ADR-0008 is not amended, it is read correctly:
every Change that *mutates a value* carries both ends of it.

The cost is that `Change` now means "a thing recorded during a Turn" rather than "a
mutation", and the name no longer describes every case. Renaming it would rename it on disk
in every Log already written, which ADR-0008's own `combatantRemoved`/"benched" precedent
(`CombatLogFold.swift:180-183`) settles: the wire name stays.

A Roll made during a fight lands in the open Turn's `changes`, even when the Pawn rolling is
not the Combatant whose Turn it is — the rogue saves against the dragon's breath on the
dragon's Turn. ADR-0008 already blessed this: "a Turn records what happened during it, not
what happened to one Pawn", and every `Change` carries its own `combatantID`.

Outside a fight the same act writes a `SessionLine`, and the call site does not branch:
`SessionControl` drops the write while an Encounter runs, exactly as `commitPawnMove` already
relies on (`AppState+Combat.swift:229-241`). ADR-0014's rule — exactly one recorder is live —
is what makes one button safe to press in either state.

## The app holds no ability scores

The obvious feature is the one we are not building: six ability scores and a proficiency
bonus on `StatBlock`, from which the modifier computes itself.

It was rejected because of who fills it in. A DM types HP and AC for a creature because the
fight needs them; nothing makes them type six more numbers, and a modifier computed from
blank fields is wrong with confidence. Every Creature already on a Map would become
incomplete the moment the field existed. And the number the DM wants recorded is the one the
player said out loud — which already includes the item, the spell and the circumstance that
no character sheet in this app would have known about.

So the Modifier is one typed number. The Roll records what was said at the table, which is
the same standard Initiative is already held to: rolled as 1d20 plus a bonus, and "editable
at any time" because "overtyping a number the players call out is faster than typing into an
empty field".

For the same reason the app never generates the d20. The dialog is a grid of twenty faces and
the DM clicks the one the die showed. There is no RNG in this feature at all.

## What is not stored

**The outcome.** Success is `d20 + modifier >= DC`, computed on read. A stored boolean is a
second copy of a derivable fact, and ADR-0008 exists because two copies of one truth drift.

**The Ability of an Ability Check.** A Skill implies it — Stealth is Dexterity — so it is
derived at render time. Copying it into the line would let a Log disagree with itself.

**Advantage and disadvantage.** Not in this version: the DM records the die that counted.
This is the most likely regret, and it is a safe one — `Change.unrecognised` means a later
version can add the field and older builds keep reading, so the decision is reversible in the
only way that matters for a file format.

## Consequences

`StatBlock` is untouched, so no `stats.json` migrates. Both Log formats gain cases that older
builds degrade gracefully on. The tracker shows nothing new, because a Roll folds to nothing.

Exhaustive switches to extend: `Change.combatantID`, both Codable halves, `CombatLogFold.apply`
(skip, beside `.moved`/`.noteAdded`), `LogRowText.describe`, `LogViewModel.rows` and
`combatRows`, `SessionFold.fold`, `SessionLine.map`.

The Roll sheet writes to a Log and never to a Stat Block. It does not apply what the result
implies — a failed Dexterity save means half damage and the app does not know how much. The
DM applies it with the Hit field that already exists. One control, one action.

## Considered Options

- **A new `LogLine` case** — rejected: `LogLine` has no `unrecognised` fallback, so a Log
  containing Rolls is silently truncated by any older build.
- **Ability scores on `StatBlock`, modifier computed** — rejected: it doubles the feature,
  makes every existing Creature incomplete, and computes from fields a DM has no reason to
  fill. Revisit if the typed Modifier proves tiresome at the table; remembering the last
  Modifier per Pawn is the cheaper next step.
- **The app rolls the d20** — rejected: the table has dice, and Initiative already treats the
  spoken number as authoritative.
- **Store the success/failure verdict** — rejected: derivable, and a stored derivable fact is
  the drift ADR-0008 was written against.
- **Rolls only in the Session Log** — rejected: ADR-0014 silences it during a fight, which is
  when most saves happen.
- **A required Difficulty Class** — rejected: a DM who has not yet decided the DC would type
  a fake one, and a fake number in an append-only file is worse than no number.
