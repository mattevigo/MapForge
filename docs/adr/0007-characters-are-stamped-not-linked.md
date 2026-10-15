# Characters are stamped onto a Map, not linked to it

A DM re-creates the same four or five player tokens on every Map: click to place, then type
the label, pick the colour, set the sight range. The party is the one cast that never
changes, and it was the one thing the app made you re-enter every time. A **Party** of
**Characters**, defined once and dragged onto the Map, removes that.

The question the feature turns on is what the dragged thing leaves behind. A Pawn could
*reference* its Character — store a `characterID` and read the name and colour back out of
the roster — or it could be a **copy** taken at the moment of the drag. We copy.

## The Map's file has to stand on its own

`<map>.fog.json` currently holds everything needed to draw a Map's fog: every Wall, every
Light, every Pawn with its own label and colour. Nothing in it points outside itself. A
reference would end that — the roster would live in Application Support, and a sidecar
carried to another Mac, or restored from a backup, or simply opened after the DM deleted an
old campaign, would render tokens with no names.

That property is worth more than the convenience a link buys. The one thing a link gives you
is rename-once-change-everywhere, and a DM renames a player character approximately never.

## A Pawn diverges the moment it exists

A stamped Pawn is immediately not its Character: it has a position, it may have its torch
doused, it may be hidden from the table, it may have been renamed live in the sidebar. The
Character has none of those, and cannot: it is not on a Map. Two types that share four
fields at one instant and nothing afterwards are not one type seen twice.

So editing a Character does not prompt to update placed Pawns, and deleting one does not
cascade. Both are silent, and that silence is the decision, not an oversight.

## The back-pointer that remains is advisory

`Pawn` still gains an optional `characterID`, which looks like the link we just rejected. It
is not one: no drawing, no fog, no persistence and no behaviour reads it. It exists so the
Party roster can show that three of five Characters have Pawns on this Map — the glance a DM
takes at the start of a session. A Pawn whose `characterID` names a deleted Character loses
a badge and nothing else, which is exactly the blast radius an advisory field should have.
ADR-0028 adds the one reader the DM triggers: re-cutting a Character's Face for *every* one of
its Pawns reaches those on the open Map by this field. A Pawn whose Character is gone is then
re-cut for itself alone.

Matching on the label instead would have avoided the field entirely, and was rejected because
renaming a Pawn live is a thing the sidebar already lets you do; the count would silently go
wrong precisely when a DM was busiest.

## Consequences

`Pawn`'s hand-written `Codable` takes one more `decodeIfPresent` key, which is the migration
shape it already uses for `isHidden` and `isBig`. Old files decode with `characterID` nil and
are never rewritten differently.

Stamping is **live**: it works on the ordinary preview, outside "Edit Fog…", and is not
undoable. It follows `movePawn` rather than `addPawn`, because placing the party is something
a DM does at the table when the session starts, not while authoring fog. Gating it behind the
mode would have replaced one ritual with another, which is the whole complaint the feature
answers. The drop flushes to disk immediately rather than waiting out the autosave debounce,
as a drag-end already does.

The same Character can be stamped repeatedly, producing Pawns that share a label. Refusing
the second one was considered and rejected: a mirror image or a summon is real, and
auto-renaming the duplicate would silently edit a name the DM chose. The roster's count makes
an accidental double visible without forbidding a deliberate one.

The Party is app state, not Map state — a JSON file in Application Support, with the active
Party remembered in `UserDefaults` beside the Player Display. Putting it in the sidecar would
have made a DM's campaign roster a property of one battle map.

## Considered Options

- **A Pawn references its Character** — rejected above: it makes `<map>.fog.json` unreadable
  without the roster, to buy a rename that never happens.
- **No `characterID` at all, match on label** — rejected: live renaming a Pawn is supported
  and would silently break the roster's count.
- **Characters of any Pawn Kind, not just Players** — rejected for now. The pain is the fixed
  cast; Creatures are per-encounter, and placing six goblins is already served by a new Pawn
  copying the last one placed. A monster library is a second feature, and folding it in here
  would double the drop target's ambiguity for a weaker payoff.
- **Stamping inside "Edit Fog…", joining the undo history** — rejected: see Consequences.
  Making it work in *both* modes, undoable in one and not the other, was rejected too — it
  makes "can I undo this?" depend on invisible state.
- **The Party lives next to the campaign folder the DM chose** — rejected: it needs a file
  picker and a persisted security-scoped bookmark, the same machinery that made the Library
  issue `wontfix`. **Reversed by ADR-0011**: the app is not sandboxed, so the bookmark was
  never needed and this rejection rested on a cost that did not exist.
- **Characters carry a portrait** — deferred, not rejected. It reaches into token rendering,
  True Scale sizing and the sidecar format, and deserves its own decision rather than riding
  along with reuse. **Settled by ADR-0028**: a Character may carry a Face, which the Stamp
  copies like everything else.

## Amended: the Combat tab reads it too

`characterID` is now read by **two** things: the roster's count, and the Combat tab, which
follows a Player Pawn's `characterID` to its Character, and the Character's note, to show
the DM that Character's page (its actions, spells and traits) beside the Stat Block. That is
the advisory read ADR-0020 allows a Creature's `monsterName`, made for Players. It reads the
Characters' notes, not the Bestiary, so ADR-0020's one live read of the Bestiary stays one;
the two pages are read the same way, each from its own reading of the Workspace.

The page is looked up live, each time it is drawn, rather than from a note name copied onto
the Pawn at the Stamp. A copy would have left every Pawn already on a Map without a page:
they were stamped before Characters had notes, and ADR-0024 starts every Character unlinked.
A Character the DM links tonight should reach the Pawns already standing on tonight's Map.

The blast radius is unchanged in kind. A Pawn whose Character is deleted, unlinked, or whose
note has gone loses a page of reference and nothing else. Its label, colour, sight and Stat
Block are still its own, `<map>.fog.json` still reads without a roster, and nothing about
drawing, lighting, discovery or persistence branches on the field.
