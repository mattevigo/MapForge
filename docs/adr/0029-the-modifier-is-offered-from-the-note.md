# The Modifier is offered from the note

ADR-0017 made the Modifier one typed number and rejected "ability scores on `StatBlock`,
modifier computed", for two reasons. The first was who fills them in: a DM has no reason to
type six more numbers per creature, so a computed modifier would be "wrong with confidence".
The second was that the number worth recording is the one said aloud at the table, which
already includes the item, the spell and the circumstance. The ADR named its own revisit:
"if the typed Modifier proves tiresome at the table".

ADR-0020 and ADR-0024 have since removed the first reason. Every Monster and every Character
with a note already has its numbers written there, and the app reads them. In the live vault
every one of those notes carries `stats:`, every Character note lists all six saves as totals,
and every note lists its proficient skills as totals. Nobody has to fill anything in. The
second reason still holds.

So the Roll sheet **offers** a Modifier and the DM confirms or overtypes it. That is the
standard Initiative is already held to: it is rolled with the bonus, and the DM overtypes
whatever the players call out.

## Where the offer comes from

- **The Pawn's memory, read live.** A Player's Pawn reaches its Character's note, and a
  Creature reaches its Monster's note, through the link the Combat tab's page already uses.
  The note is read when the sheet opens. Nothing is copied onto the Pawn, so `StatBlock` and
  `stats.json` are untouched, as ADR-0017 required. A Pawn whose note is gone is offered
  nothing, and the DM types the number as before: it loses a suggestion and nothing else.
- **The note's own bonus first.** A save or skill the note lists gives its number as written.
- **Otherwise the Ability's modifier.** Notes list only proficient skills, and a Monster lists
  only proficient saves (47 of 58 list none). For anything unlisted, the offer is
  `floor((score − 10) / 2)` of the Ability rolled, taken from `stats:`. A Skill's Ability is the
  one `Skill.ability` already gives.
- **Names are matched, not trusted.** A save or skill name matches when it equals the official
  rulebook name in any of the app's shipped languages, ignoring case, accents and the ` ●`
  the vault uses to mark a proficient save. This follows ADR-0022: rulebook terms are the
  table's, and the language a note is written in has nothing to do with the Mac's. An entry
  that matches nothing is ignored silently, and the fallback above applies.

## What the offer is not

It is **not recorded**. The Roll stores the number that was in the field when Record was
pressed, exactly as before. The Log does not say whether that number was offered or typed: a
stored provenance flag would describe the sheet, not the table.

It is **not sticky against the DM**. The offer follows the save or skill the DM picks until the
DM types into the field. From then on the DM's number stays, so a blessed +6 survives a
change of mind about which save it was.

It is **labelled**. A caption names the note it came from, and says whether the number is the
note's own bonus or an Ability's modifier, because a 0 the DM must type over looks the same as
a note's honest +0.

## Consequences

`Monster` and `CharacterNote` gain six ability scores, read from `stats:` (and inherited through
`extends:` like every other key). They are read and never stored. The **Ability** entry in
`CONTEXT.md` changes from "the app holds no Ability scores" to "a Pawn has none, and the note's
are read only to offer a Modifier".

`Monster.Proficiency` stops being purely descriptive. Its name is now matched onto `Ability` or
`Skill`, which reverses the comment that said it never would be.

A hero whose class adds to every skill is offered too little on the skills the note does not
list. Lodovico Mezzacorda, a level-5 Bard with Jack of All Trades, is offered +3 for Survival
rather than +4. The DM overtypes it, or the note lists the skill. The app does not learn class
features.

## Considered Options

- **Lock the Modifier to the computed number**: rejected for ADR-0017's surviving reason. The
  note cannot know about Bless or the attuned belt.
- **Copy saves and skills onto the Pawn at Stamp**: rejected. It would migrate `stats.json` for
  a suggestion, and it would bring back the stale copy that ADR-0024 was written against.
- **Offer nothing when the note lists no bonus**: rejected. Most Monsters list no saves, so the
  feature would barely reach the Creatures whose saves the DM actually rolls.
- **Report unmatched save or skill names as note problems**: rejected. The cost of a mismatch
  is a suggestion the DM overtypes, and the reference page shows the note's own list anyway.
- **Match abbreviations** (`Sag`, `DEX`): rejected. Every note in the live vault uses full names,
  and an abbreviation table per language is a vocabulary of our own (ADR-0022).
- **Remember the last Modifier per Pawn**: the "cheaper next step" ADR-0017 suggested. It is
  superseded: the note gives the right number on the first Roll, and memory would give it only
  on the second.
