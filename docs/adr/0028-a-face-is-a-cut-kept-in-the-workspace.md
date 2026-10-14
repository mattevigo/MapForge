# A Face is a cut kept in the Workspace; the note names its picture in the fence

A Pawn may be drawn as a **Face**: a square the DM cuts from a picture. The app keeps the cut
square, copied into `.mapforge/`, and never a link to the picture it came from. A Monster or
Character note names its picture with Fantasy Statblocks' own `image:` key inside the
`statblock` fence. That key is the only place the app looks. It never looks at a picture
embedded in the note's body. This settles what ADR-0007 deferred: "Characters carry a portrait
— deferred, not rejected."

The cut is kept rather than the picture because a cut needs somewhere to live in any case:
"which square of this picture" is the DM's choice, made once per Monster or Character, and the
picture alone does not record it. Keeping only the square also means the Map never depends on
the vault's attachments staying where they are. The DM's notes move, get renamed and get
re-imported, and DM Realm replaces a note's pictures when it re-imports one. A Face cut last
month must survive all of that, the same way a Pawn's numbers survive the Monster's note
changing (ADR-0007, ADR-0020).

The fence is where the notes tell the app things. The body is prose: a Location embeds its map,
and a Monster's note may embed its lair. ADR-0023 already obeys the fence's `bestiary: false`
rather than guessing from folders, and ADR-0024 refuses to guess a Character's note from its
name. `image:` is the plugin's own key, so Obsidian draws the same picture the Pawn will wear,
and DM Realm can write it without MapForge inventing a key of its own.

## Consequences

- `image:` takes a wikilink only. A web address is ignored, because opening a game must not
  need the network. A bare name that matches more than one picture in the Workspace gives no
  Face, and the app says so. Obsidian's rules for picking one depend on settings the app
  cannot see. A path-qualified link is always exact, and DM Realm writes one whenever a bare
  name is not unique.
- A note that names a picture the Workspace lacks gives no Face, and the app says so where it
  already reports a note's problems.
- Until DM Realm writes `image:` into its fences, notes give no Faces. The body embeds
  already there are not read.
- Faces are copies, so every Pawn already on a Map keeps its Face when a note or picture
  changes. There is one exception, made by the DM: re-cutting the Face of a Monster or
  Character re-cuts the Pawns on the open Map that took their Face from it.
- `.mapforge/` now holds pictures as well as JSON, so it grows with every Face. A Face that no
  Pawn, Character or Monster uses any more can be removed without loss.

## Considered Options

- **Keep a path to the picture and the crop rectangle, and cut it at draw time.** Rejected: a
  moved or re-imported picture silently strips every Face on every Map, and the Map stops
  being readable without the vault's attachments.
- **Embed the picture in the fog file.** Rejected: the fog file is meant to stay small and
  readable (ADR-0003), and a Character's Face would be copied into every Map it is stamped on.
- **Read the first picture in the note's body when the fence has no `image:`.** Rejected:
  "first picture" is a guess. A Location's map or a lair's picture would become a Face.
- **A MapForge-only key, such as `mapforge_face:`.** Rejected: Obsidian would not draw it, and
  it would be a second statement of a picture the note already names.
