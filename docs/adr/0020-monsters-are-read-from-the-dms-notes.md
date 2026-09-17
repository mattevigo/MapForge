# Monsters are read from the DM's notes, copied onto a Pawn, and kept nowhere else

ADR-0007 declined to let a Character be a Creature: "A monster library is a second feature."
This is that feature, and it has an unusual shape for a library — the app has no monster
editor, no monster database and no monster file of its own. A **Monster** is whatever the
DM's markdown notes define inside a ```` ```statblock ```` fence; the **Bestiary** is a
reading of one folder of those notes, held in memory; and a Creature Pawn takes a **copy** of
its Monster's numbers.

## The notes are the only place a Monster is written

The DM already keeps a bestiary — in Obsidian, with tactics, lore and links beside each
statblock, in a vault that is also their Workspace. An editor in the app would be a worse
copy of a tool they already use, and an import would fork their notes on the day it ran. So
the app only reads. `.mapforge/bestiary.json` names the folder, relative to the Workspace
root so that it travels with the Workspace (ADR-0012), and the app never writes that file:
it is hand-edited for now, and a typo in it can cost the DM the Bestiary and nothing else.
This is why it is not a key in `preferences.json`, whose store forgives an unreadable file
by overwriting it.

## Copied, not linked

Saying which Monster a Creature is writes the Monster's armour class, hit points and
initiative bonus into that Pawn's Stat Block, exactly as a Stamp copies a Character's
(ADR-0007, ADR-0009). Combat never reads the Bestiary. A fight must not change because a
markdown file was edited, renamed or left on another Mac, and `<map>.combat/` must describe
its Combatants without the notes being present.

`Pawn` gains an optional Monster **name** — the `name:` string, not a path and not an ID the
files do not have. It is advisory in ADR-0007's sense: it is read to show the Monster's
actions in the Combat tab and to let **Add** give the next Creature the same Monster, and
nothing about drawing, fog, persistence or the fight branches on it. That reference view is
the one live read of the Bestiary, and it is right there because it is reference, not state:
a Creature whose Monster has left the notes loses a panel and keeps every number.

A name rather than a relative path, because `<map>.fog.json` is meant to be portable and a
path would write the DM's vault layout into it, while surviving a rename no better.

## Never persisted

The Bestiary is rebuilt from the notes each time the Workspace opens and is never written to
disk. A cache exists to skip expensive work, and parsing a few dozen — or a few hundred —
small files is milliseconds off the main thread. Against that saving, a cache is a second
copy of the notes that must notice every edit, rename, deletion and `git checkout`, and every
bug in noticing is the app showing a Monster the notes no longer contain. It would also be a
generated file in `.mapforge/`, which ADR-0012 keeps as the DM's own committable data with no
`.gitignore`. And copying already provides the only safety a cache would: no Pawn's numbers
depend on the notes being there.

Persisting is additive if the Bestiary ever grows to thousands of files — the in-memory
shape does not change — so declining it now forecloses nothing.

It is read when the Workspace opens and at no other time: no rescan control and no file
watching. A Monster written mid-prep is met on the next open. Watching was what the
never-built Library promised, and it stays unbuilt.

## Read leniently, reported honestly

The notes are hand-written and already break a strict reader, so the reading takes the
leading integer of `hp` and `ac`, accepts `−` (U+2212) as well as `-` in `initiative`, and
treats an unrecognised `size` as not Big. A file without a fence is simply not a Monster. A
fence that is not YAML, has no `name`, or repeats a `name` already read is **skipped and
listed**, with its reason, in a caption under the search box — the feature's only feedback
channel, since a Monster silently missing from a search is the failure a DM cannot diagnose.

## Considered Options

- **Link a Pawn to its Monster and read numbers live** — rejected: a fight that changes when
  a note is edited, and a combat folder unreadable without the vault.
- **A persisted cache in `.mapforge/`** — rejected above: staleness and diff noise, to save
  milliseconds.
- **An absolute path to a notes folder anywhere on the Mac** — rejected: that is machine
  knowledge (ADR-0012) and breaks when the Workspace is copied. The folder must be inside
  the Workspace.
- **Monsters for Players too** — rejected: a Player's numbers come from its Character, and
  two sources for one Pawn muddles both. Only a Creature can be a Monster.
- **Rolling hit points from `hit_dice`** — rejected: the book's average is what `hp` is for,
  and the DM can overtype one that should differ.
- **Pre-filling a Roll's Modifier from `stats` and `saves`** — out of scope, not rejected. It
  reopens ADR-0017 and the glossary's "the app holds no Ability scores", and deserves its own
  decision.
