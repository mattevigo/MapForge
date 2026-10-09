# The Distance Unit is the Mac's; the notes are checked against it

The DM chooses whether the table speaks metres or feet, and the choice is stored **per Mac**,
in Settings beside the Interface Language. Until they choose, it follows the Mac's region. The
Workspace stores no unit. Its unit is whatever its notes are written in, and when a Monster's
or Character's note gives its Speed or Senses in the other unit, the app says so: in the
caption under the Monster and Character note searches, and on that note's reference page. The
warning only informs. The note is never rewritten and still stamps, because armour class, hit
points and initiative have no unit. When every note that names a unit agrees on the other one,
the caption offers to switch the Distance Unit in one click.

This looks like it breaks ADR-0012, which puts what the game knows in `.mapforge/`, and the
unit the notes are written in is plainly a fact about the game. It goes on the Mac because it
behaves like the Interface Language, not like a Party. It is the people at the table who speak
metres or feet, the same people whatever campaign is open. A Workspace holding several
campaigns, which ADR-0011 allows, would otherwise need one unit for all of them anyway. The
notes are still the authority on what the game is written in, so the app checks them against
the Mac rather than storing a second copy of that fact that could drift from them.

## Consequences

A Workspace copied to a Mac set to the other unit opens with warnings until the DM changes
Settings, or takes the one-click switch the caption offers.

Both units name the Grid square: 1.5 m and 5 ft. They are never converted into each other, so
switching the unit re-reads every stored distance in squares and never changes one. The Logs
keep squares on disk and are unaffected.

## Considered Options

- **Per Workspace, in `.mapforge/`** — rejected. It would duplicate what the notes already
  say, and a Workspace that holds a metric campaign and an imperial one could hold only one
  answer.
- **Derived from the Interface Language** — rejected. Every non-English edition is metric, but
  the English interface writes *metres* (ADR-0022), and an Italian table running an American
  adventure could not choose feet.
