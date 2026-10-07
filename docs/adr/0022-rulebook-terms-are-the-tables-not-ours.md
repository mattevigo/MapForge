# Rulebook terms are the table's, not ours

MapForge now speaks seven Interface Languages, and its words come from three places that are
translated three different ways. Rulebook terms — Conditions, Abilities, Skills, Saving
Throw, Difficulty Class, Initiative, Round — are the ones the official D&D 5.5e edition prints
in that language, copied verbatim and never improved on. MapForge's own terms — Pawn, Wall,
Fog Overlay, Solo Sight, Viewport — have no book to copy, so each is chosen once per language
and written down in `docs/terminology.md` with the alternatives it beat. The DM's own words —
Monster names from their notes, Pawn labels, Light names, Parties, Comments — are never
translated at all.

## Why the rulebook wins

A Condition's name is not ours to choose, because the table learned it before it opened the
app. An Italian table says *Tiro Salvezza*, and a better-sounding rendering on the Player
Display would be a second word for one thing, read aloud across the room. The Spanish edition
shows how far a free translation drifts: a Condition is an *estado*, a Round an *asalto*, a
Stat Block a *Perfil*, Prone is *Derribado* — none of which a translator working from the
English would reach. The 2024 wording wins over the 2014 where they differ, because the
glossary is pinned to 5.5e. The sources are WotC's own translated SRD 5.2.1 (German, Spanish,
French, Italian) and the Brazilian *Livro do Jogador*.

Conditions are always the rulebook's heading form — masculine singular where the language
inflects — and appear as labels, never agreeing with a Pawn: a Pawn has no gender and a DM's
Gnoll may well be a Guerriera.

## Where there is no official edition

Greek has none: no 5e or 5.5e book, SRD or Starter Set has ever been published in it, and
Greek tables speak Greek around mechanics they keep in English — AC, HP, a Perception check.
So the Greek interface is Greek, and its rulebook terms are English. The rule is the same one
applied honestly: the table's words, not ours. It is also the rule for any later language
without an official edition, until a publisher gives it one.

Spelling is not a term. The English interface is written in British English, as the glossary
is — *Armour Class*, *colour*, *metres* — although the English book is American.

## Consequences

`docs/terminology.md` is the termbase: the rulebook terms side by side with their source,
then one table per language of MapForge's own terms, each with the alternatives it beat, and
a note of which languages a native speaker has reviewed. A change
that first puts a glossary term on screen adds its row for every language. Italian is
reviewed; the others ship as proposed and are corrected in that one place.

Only what is on screen is translated. Manifest, Sidecar and Entrant never reach the DM's eyes
and have no row.

## Considered Options

- **Translate everything freely** — rejected: the app would teach the table words its books
  do not use.
- **Coin Greek rulebook terms, marked unreviewed** — rejected once it was clear no Greek table
  uses them; *Κράση* for Constitution is a word nobody at that table says.
- **Drop Greek** — rejected: MapForge's own terms still need a Greek rendering, and the
  English rulebook terms are what the table would see in any case.
