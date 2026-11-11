# The Encounter Difficulty is reckoned from the notes, live

The Combat tab shows the DM the **Encounter Difficulty** of the fight they have framed, before
Play and while it runs. It is the DMG 2024's *Combat Encounter Difficulty* procedure, also in
SRD 5.2.1, run backwards. Each Creature is worth the experience points its Monster's Challenge
Rating gives it. Each Player gives the XP budgets that its Character's level gives, for Low,
Moderate and High. The Creatures' total is set against the party's three totals. There is no
group-size multiplier and no band above High, because the 2024 rules have neither.

A budget is a ceiling: the rules say to "spend as much of your XP budget as you can without
going over". Read backwards, a total that fits within the Low budget is **Low**, one that
fits Moderate is **Moderate**, and one that fits High is **High**. A total over the High budget is
**Beyond High**. That is MapForge's own word, because the DM needs to see an overspent fight
named. There is no band below Low: a fight that spends little of the Low budget is still Low,
and the bar shows how little. Any cut-off beneath Low would be one we invented.

The procedure needs two numbers that no Pawn carries. A Creature's Challenge Rating is
`Monster.challengeRating`, read from the note's `cr:`. A Player's level is the Character's
note's `level:`. Both have been text so far, kept as the note wrote it to be shown on a page and
never computed with.

## Read live, through the advisory references

The Encounter Difficulty finds both numbers each time it is drawn. A Creature's `monsterName`
leads to its Monster in the Bestiary, and a Player's `characterID` leads to its Character's
note. These are the references the Monster's page and the Character's page already follow
(ADR-0020, and the ADR-0007 amendment).

So ADR-0020's "the one live read of the Bestiary" now has a second reader. The rule it
protects still holds: **a fight does not change because a markdown file was edited.** The
Encounter Difficulty is reference, not state. Nothing is written of it, the Combat Log never
mentions it, and no Turn, Stat Block or Order depends on it. A Creature whose Monster has left
the notes loses its contribution to a bar and keeps every number it fights with.

The rejected alternative copied the Challenge Rating and the level into the Stat Block at the
Stamp, as armour class and hit points are copied. That would have kept Combat off the
Bestiary. But every Pawn already standing on a Map would have counted for nothing until it was
re-stamped, and ADR-0024 starts every Character unlinked. A copied level would also go stale
the evening a Character levels up in the notes, and a copied Challenge Rating would serve no
purpose other than this one reading. It is the same argument the ADR-0007 amendment made for
the Character's page.

## Computed with, but only when unambiguous

`cr` and `level` are now computed with, which the readers used to refuse. They are read
strictly:
- `cr` counts when it is `0`, `1/8`, `1/4`, `1/2` or a whole number from 1 to 30;
- `level` counts when it is a whole number from 1 to 20.

Anything else is **uncounted**, and the Combat tab says how many Pawns went uncounted. That
covers "10 (13 in lair)", "Guerriero 3 / Ladro 2", a Creature with no Monster and a Player with
no Character. Nothing is guessed from free text. This is the reason `StatblockReader` already
gives for refusing a spell-slot guess: a wrong number looks trustworthy. With no countable
Player there is no budget and so no bands, and the Creatures' total XP is shown on its own.

## Consequences

- The XP-by-Challenge-Rating and XP-budget-per-level tables are rulebook data compiled into
  the app. They are the 2024 ones, as the glossary is pinned to 5.5e (ADR-0022).
- A `cr: 0` Monster is worth 10 XP. The 2024 rules make a CR 0 creature worth 0 or 10 by its
  own stat block, and the notes' `statblock` notation has no XP to say which. 10 is the
  default nearly every CR 0 creature carries, and over-counting a Shrieker by 10 XP is less
  than any CR 1/8 Monster adds.
- The band names Low, Moderate and High are rulebook terms. Each language copies them from
  its SRD 5.2.1 (Italian has Facile, Media, Difficile), and `docs/terminology.md` gains their
  rows. "Beyond High" is MapForge's own term, chosen once per language.
- The Pawn is the unit. Each counted Player Pawn adds a budget and each counted Creature adds
  its worth. A Character stamped twice counts twice, and an allied Creature counts against the
  party unless the DM unticks or Benches it.
- The Encounter Difficulty appears only in the Control Window's Combat tab, never on the Player
  Display.
