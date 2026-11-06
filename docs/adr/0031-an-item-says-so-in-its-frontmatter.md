# An Item says so in its frontmatter

A Treasure can be said to be an **Item**, as a Creature can be said to be a Monster. An Item is
a definition read from the DM's notes, such as a Borsa or a Gemma di Fuoco, and it is never on
a Map. The **Treasury** is every Item read from the Workspace, as the Bestiary is every
Monster. It is read once, when the Workspace opens, in the same walk as the Bestiary, and it is
never written down (ADR-0020, ADR-0023).

A Monster says what it is with its `statblock` fence. An item note has no fence, because it has
no numbers. DM Realm writes its item notes into Reference `Equipment` and `Magic_Items`, into
Homebrew's, and into an Adventure's `Items`. Their frontmatter holds only a translated source
key (`fonte:`), their body starts with `# <name>`, and their picture is embedded in the body.
Nothing in such a note says "item" in a way the app can read without guessing.

So the note says it in its frontmatter, with two English keys:

```yaml
---
fonte: XPHB p. 225, v2.36.1
item: true
image: "[[Riferimento/Allegati/Borsa.webp]]"
---
# Borsa
```

- `item: true` makes the note an Item, wherever it lives.
- `image:` is the Item's picture, read exactly as a fence's `image:` is (ADR-0028).
- The Item's name is the note's first `#` heading, which is where DM Realm writes the
  translated name. A note with no heading is named after its file, with `_` read as spaces.

DM Realm's side of this contract is the user's to do, not the app's: adding `item` and `image`
to its English keys, writing them on import, and backfilling the notes it already wrote.
MapForge is built against the contract above.

## Why the frontmatter

The frontmatter is where an Obsidian note says things about itself, and Obsidian shows it as
the note's properties. The body is prose, as it is for a Monster (ADR-0028). An item note's body
embeds its picture under its description, but "the first picture in the body" is a guess, and
ADR-0028 has already refused that guess.

**No fence.** A `statblock` fence with nothing but a name and a picture would draw an empty
Fantasy Statblocks block in the middle of every item note. It would also make every item a
candidate Monster, which ADR-0023 would then have to tell apart.

**No folders.** ADR-0023 refused to read Monsters from named folders, because DM Realm's folder
names are translated into the Workspace's language and the DM may rename them. Items live in at
least three folders in each language. The note says what it is, as `bestiary: false` does.

**English keys.** DM Realm translates the keys it writes for the DM to read, such as `fonte:`.
`item` and `image` are written for MapForge to read, so they stay the same in every language,
as Fantasy Statblocks' own keys do.

## Consequences

- Yams reads the frontmatter, as it reads a fence (ADR-0019). The app now knows about YAML in
  two places, `StatblockReader` and `ItemReader`. It still writes none.
- Only the two keys are read. Any other frontmatter is the DM's, and a note without
  `item: true` is never an Item. A `statblock` fence never makes one.
- Two Items with one name are reported like two Monsters with one name: the first by path wins,
  and the other is skipped and listed with its reason. A frontmatter that is not YAML, or is not
  a list of fields, is skipped and listed too, but only when it writes `item` as a key
  anywhere in it: on a line of its own, in a list, or in a flow mapping such as
  `{item: true, …}`. `item` must be a word of its own, so `magic-item:` and `items:` are not
  it. The app cannot otherwise tell that the note was meant as an Item, and a tavern's broken
  tag list is none of the Treasury's business. YAML that cannot be read cannot be told key from
  value either, so an `item:` inside a value counts too. A note listed that was not meant as
  an Item is a smaller harm than one missing from the search without a word.
- A Treasure remembers its Item by name, in `itemName`. That memory is advisory, as
  `monsterName` is. A label taken from an Item's initials follows the Monster's rule exactly.
- ADR-0028's one exception reaches Items too: re-cutting an Item's Face for every one re-cuts
  the Item's kept cut and the Treasures on the open Map that took their Face from it, found by
  `itemName`.
- Until DM Realm writes `item: true`, the Treasury is empty and says so.

## Considered Options

- **Read Items from DM Realm's item folders.** Rejected for the reasons ADR-0023 gives: the
  folder names are translated and renamed, and a list of them is the vault's layout copied into
  the app.
- **A `statblock` fence with `item: true`.** Rejected: Obsidian would draw an empty statblock
  in every item note, and the fence is the Bestiary's notation.
- **Translated keys, such as `oggetto: true`.** Rejected: one contract per language, and DM
  Realm translates keys for people, not for programs.
- **Treat every note in an item folder as an Item, with the body's first picture as its
  picture.** Rejected: both halves are guesses, and ADR-0028 refuses the second.
