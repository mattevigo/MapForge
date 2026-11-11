# Combat state lives outside the fog document

A Pawn now has hit points, an armour class, an initiative bonus and a set of Conditions.
`<map>.fog.json` already holds every Pawn, so putting them on `Pawn` and letting the existing
sidecar carry them is one afternoon's work. We do not.

This runs against ADR-0003, which moved the Grid **into** the fog file on the argument that
Light and Pawn radii are measured in Grid squares and a file that persists a measurement
without its unit is incomplete. A reader who has just absorbed that will reasonably ask why
hit points go the other way. The answer is that the two cases differ in the thing that
mattered there.

## The fog file has no use for a Stat Block

The Grid belonged in the fog file because the fog file's own contents were unreadable without
it — `brightSquares: 6` means nothing until you know how big a square is. Nothing in
`<map>.fog.json` needs to know an ogre has 59 hit points. Fog is walls, lights and positions;
combat is numbers about creatures. There is no computation in the fog document that reads a
Stat Block and no rendering that depends on one.

They also live on different clocks. A fog document is authored once and edited rarely, under
an explicit mode with an undo stack. Combat state changes several times a minute during a
session and is never undone, only corrected. Merging a file that changes twice a year with
one that changes twice a minute means the autosave debounce, the load-failure guard and the
version number all serve two masters with different needs.

And the fog file should stay portable. A DM sharing a map with its walls and lights traced is
sharing prep work; they are not necessarily sharing that their players' cleric is at 3 hit
points. Keeping the fight out of the artwork's sidecar keeps that a choice.

## Keyed by `Pawn.ID`, not held on `Pawn`

Given a separate file, the Stat Block could still be a field on the in-memory `Pawn`, stripped
on write by `FogStore` and re-attached on load. Call sites would read `pawn.stats` and never
think about it. That was rejected: two stores mutating one type, each responsible for half its
fields, is a trap that springs the first time somebody adds a third writer.

Instead the Stat Blocks are a dictionary keyed by `Pawn.ID`, and the ergonomics are recovered
with an accessor on `AppState` rather than a field. This also survives the case the field
version breaks on: a Pawn deleted from the Map mid-Encounter. With a field, its numbers vanish
with it, and the Combat Log ends up naming a Combatant nothing can describe. With a dictionary
the record outlives the token, which is what ADR-0008 requires of everything.

The key is a `Pawn.ID`, which makes this a link of exactly the kind ADR-0007 refused for
Characters. That refusal stands and does not apply here: it protected `<map>.fog.json`'s
ability to stand alone, and it still does — the arrow points from combat to fog, never back.
A fog file with no combat folder is complete. A combat folder whose fog file is gone is
orphaned, and that is the correct direction for the dependency, because a map without a fight
is a map and a fight without a map is nothing.

## One folder beside the Map

`<map>.combat/` holds `stats.json` and the Encounter logs, rather than scattering
`<map>.encounter.json` and `<map>.combat-log-*.jsonl` across the DM's map directory. A map
folder that grows four files per image becomes unbrowsable, and "delete everything about
fights on this map" should be one gesture. `<map>.fog.json` keeps its place as a sibling of
the image; it was there first and moving it would break existing files for tidiness.

## Consequences

Deleting a Pawn leaves its Stat Block behind, and nothing collects it. This is deliberate for
the duration of an Encounter and merely untidy afterwards; a sweep of Stat Blocks whose Pawns
are gone can happen when an Encounter ends, and should not happen while one runs.

Two files must be written for one user action when a Pawn is both moved and damaged. They are
independent writes with independent failure, and neither is the other's prerequisite.

`Pawn` is untouched. After a feature that adds hit points, armour class, five kinds of hit
point total, fourteen Conditions and an exhaustion level, the type whose doc comment argues
for one struct with a flag has exactly the fields it had before.

## Considered Options

- **Stat Block fields on `Pawn`, in `<map>.fog.json`** — rejected above: different clocks,
  different audiences, and a fog file that starts carrying the party's wounds.
- **`Pawn.stats` in memory, split on write** — rejected: two stores owning one type, and a
  deleted Pawn taking the Combat Log's subject with it.
- **Stat Blocks in the Combat Log only, folded on read** — rejected. Tempting, since ADR-0008
  makes the Log authoritative for everything *during* an Encounter. But a Stat Block exists
  before the first Encounter and between Encounters, when no Log is open, and a DM filling in
  monster hit points during prep is not in a fight.
- **Stat Blocks on `PartyCharacter` only** — rejected as insufficient, not wrong: Characters
  need them (see ADR-0007's copy rule, which now copies more fields), but Creatures have no
  Character to hang them on and Creatures are most of a fight.
- **Application Support, keyed by map path** — rejected: it breaks when the DM moves a map
  file, and it separates a fight from the map it happened on.
