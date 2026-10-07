# The Bestiary reads the whole Workspace

ADR-0020 read the Bestiary from one folder, named in `.mapforge/config.json`. That fitted a
vault with one `03_Bestiario`. The DM's notes now follow DM Realm's layout, which spreads
statblocks across the Workspace: the Reference monsters, a Campaign's own homebrew creatures,
and the named NPCs of a Campaign or an Adventure each live in their own folder. Those folders'
names are translated into the Workspace's language, and the DM may rename them. One folder
missed the NPCs a Campaign actually puts on the Map, and a list of folders would be a second
record of the vault's layout, kept in step by hand. That is the cost ADR-0020 refused when it
declined a cache.

So the Bestiary is now a reading of **every note in the Workspace**, still taken once, when the
Workspace opens, and still never written down. `bestiaryStatBlockPath` is ignored.

## What is not a Monster

A fence is left out when it marks itself `bestiary: false`. That is Fantasy Statblocks' own
flag, and DM Realm uses it for a Character's past Builds and for its Templates. The vault
already says which fences are not monsters, so the app obeys the vault rather than guessing
from paths. A fence carrying `player` is a Character's (ADR-0024): it is read as a Character
and is never a Monster. Hidden folders (`.git`, `.obsidian`, `.mapforge`) are not read, as
Obsidian does not read them either.

## A Monster written as another

A DM Realm NPC is usually written as `extends: Esploratore` plus the values that change. Such
a Monster is its base with the NPC's keys laid over it, as Fantasy Statblocks resolves it. Each
key the NPC writes replaces the base's value whole, so an NPC's `actions` replace the base's
list rather than adding to it. Chains are followed. A base that no note defines, or a loop, is
**skipped and listed** with its reason, which is how ADR-0020 reports any note it cannot read.

## Numbers are numbers, or nothing

ADR-0020 took the leading integer of `ac` and `hp`. Read that way, a summoned spirit's
`ac: 11 + il livello dell'incantesimo` arrives as AC 11, which is wrong at every spell level
and looks trustworthy. Now `ac`, `hp` and `initiative` count only as a bare integer, or as an
integer followed by a bracket. The old vault's `67 (9d8 + 27)` and `−1 (9)` still count. Any
other value leaves that number empty for the DM to type on the Pawn. The Monster is still in
the Bestiary, with its page.

## Considered Options

- **A list of folders in `config.json`**: rejected. It is the vault's layout copied into a
  second file, and it goes stale on every new Adventure or renamed folder.
- **The whole Workspace, narrowed by the old key when it is present**: rejected. Two rules
  to explain, and DM Realm's Setup writes the key pointing at one folder, which would
  quietly keep the old limit.
- **Leaving `extends` notes out**: rejected. NPCs are exactly the Creatures a Campaign
  places.
- **Keeping the leading integer**: rejected. An empty field asks the DM, while a wrong
  number does not.
