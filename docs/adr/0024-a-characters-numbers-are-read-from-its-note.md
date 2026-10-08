# A Character's numbers are read from its note

A Character carried its armour class, maximum hit points and initiative bonus in
`.mapforge/parties.json`, typed in the app. The DM's notes carry the same numbers in each
Character's statblock. Two copies drifted, as two copies do. Within weeks of migrating the
vault, MapForge had Durga at 36 hit points against her note's 48, and Krathos at AC 14
against 16. ADR-0020 settled the same question for Monsters: the notes are the only place
the numbers are written. This applies that answer to Characters.

## Numbers from the note, the rest from the app

A Character's armour class, maximum hit points, initiative bonus and size are **read from its
note** when the Workspace opens, alongside the Bestiary, and cannot be typed in the app. What
the notes do not hold stays the app's: the Character's **name**, which is the DM's short label
for its Pawns, its **colour** and its **sight**.

Sight is not read from `senses`, even when a note gives darkvision. A Pawn's sight is also the
light it sheds for the whole table. Darkvision is not light, and the notes write it as free
text that varies between Workspaces and carries conditions ("with the goggles worn").

## The DM says which note is a Character's own

A Character remembers its note by the fence's `name`, as a Pawn remembers its Monster
(ADR-0020): a name, not a path. The DM picks the note from a search in the roster's
Character editor, which then shows the note's numbers read-only. The app never links a Character by guessing
from its name, not even on upgrade, when "Durga" plainly means Durga Pietraferma. Existing
Characters therefore start unlinked, and the numbers typed into `parties.json` are dropped
rather than kept as a fallback.

A Character's note is a fence with any of the keys only a Character has: `player`,
`species`, `class` or `level`. `player` alone would miss a Character nobody plays yet. A
fence marked `bestiary: false`, such as a past Build kept for the record, is not a Character
either, so a hero has one note. Two live notes with the same `name` are skipped and listed, as Monsters
are.

## Without a note, no numbers

A Character whose note is missing, renamed, or was never written keeps its name, colour and
sight. It has **no** numbers, and the roster marks it unlinked. Its Pawns are stamped without
numbers, for the DM to type on the Pawn. This is the Monster rule again: whoever loses their
notes loses a page, nothing else, and there is still only one source.

## The Party is still the table's

Which Characters make up a Party stays a choice made in the app. The notes have their own
lists: a Campaign's group, which names the dead, and the Characters marked active, which
names the absent. Neither is the six people at the table tonight.

Stamping is unchanged (ADR-0007). A Pawn is a copy, so a note edited after a Stamp reaches the
Character and the next Stamp, never a Pawn already on a Map.

## Considered Options

- **Keep typing numbers in the app, with a "refresh from note" action**: rejected. It is
  still two copies, and refreshing is the step that gets forgotten.
- **Typed numbers when there is no note**: rejected. It brings back the stale copy in exactly
  the cases nobody is watching.
- **Remember the last numbers read**: rejected for the reasons ADR-0020 rejected a cache.
- **Link existing Characters automatically by name**: rejected by the DM. Linking is the
  DM's decision, and a guess that happens to be right this time is still a guess.
- **Read the Party from the Campaign's group**: rejected, as above.
- **Derive sight from darkvision**: rejected, as above.
- **Show the Character's page in the Combat tab**: not rejected. It is a later update.
