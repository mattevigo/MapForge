# The table sees a Health Bar, never a number

Until this decision nothing from a Stat Block reached the Player Display. Hit points, armour
class and Conditions were the DM's, read on the Control Window and nowhere else. A Health Bar
puts one of them in front of the table: a strip under each Player and each Creature, filled in
proportion to its hit points, coloured by one of three tiers — Healthy above half, Bloodied at
half or below, Critical at a quarter or below.

It is admitted under ADR-0005's rule, not as a new one: the Player Display may draw what the
table is *entitled to know*. How hurt the ogre looks is what a DM says aloud anyway — "it's
staggering", "it's barely standing" — and the 2024 rules give that state a name, Bloodied: half its
hit points or fewer. The table is entitled to the impression. It is not entitled to the
number, so no number is ever drawn at the table: the DM keeps the exact fraction and the
digits, in the Pawn's row on the Control Window.

## The shape of the bar

The fill is linear and the tiers halve. A sharp-eyed player can read a linear fill to within a
tenth, and that is accepted: it is still an impression and not a value, and the DM can withhold
any one Pawn's bar. The halving puts the colour changes where a fight's drama is — the second
half of a creature's hit points matters more than the first — and Bloodied at a half is the
rulebook's line, so the table's word and the app's agree (ADR-0022).

Temporary hit points lengthen the fill, never past full, and never change the tier: the rules do
not let them stop a creature being Bloodied.

## Only the table's screen draws it

`PawnToken` is one view for both screens so that the DM points at the red circle and the players
see the same red circle. The Health Bar is drawn *beside* the token, not in it, so that promise
stands: the disc is still the same disc. What the DM's Map lacks, the DM's rows supply — the
exact bar, the tier the table is being shown, and the numbers — so the DM is never the one
person who cannot tell what the table can see.

## The DM can withhold it

Two switches, for two different reasons. A Live Toolbar switch hides every Health Bar from the
Player Display for the evening; it starts on and is not remembered, as ADR-0005's Measurements
switch is not. A switch per Pawn withholds one bar for good — the mimic, the boss whose state is
meant to be a mystery — and is kept with that Pawn's Stat Block, beside the hit points it is
about and out of the fog file (ADR-0009). Neither switch is a Change: whether the table could
see a bar is not something that happened in the fight, and neither Log records it.

## Considered Options

- **Exact numbers at the table** — rejected: the DM's monster numbers are the DM's, and a number
  ends the mystery a fight runs on.
- **Four fixed steps instead of a fill** — the conservative version, legible across a room and
  impossible to read precisely. Rejected for a proportional fill with coloured tiers, which
  carries more without carrying the number.
- **A bar on both screens** — rejected: the DM's Map is busy enough, and the DM's rows are where
  they already read hit points.
- **Players only, no bar on Creatures** — rejected: it answers half the request, and the half it
  drops is the one the table asks about most.
