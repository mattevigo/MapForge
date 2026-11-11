# Changelog

Versions follow [Semantic Versioning](https://semver.org). `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `project.yml` are the single source of truth; the About
panel reads them from the built app.

## 2.0.0 — 2026-11-11

### Upgrading from 1.2

- MapForge now keeps your game in a **Workspace**: a folder you choose once, where your Maps
  live in whatever subfolders you arrange, and where `.mapforge/` holds what the app knows
  that is not about one Map. The app asks which Workspace you are running before anything
  else, and returns to the last one opened —
  [ADR 0011](docs/adr/0011-the-dms-game-lives-in-a-workspace-folder.md).
- **Open Map…** opens only Maps inside the open Workspace. A Map from anywhere else is
  refused, and the app says what to do: move it into the Workspace in Finder and open it
  again — [ADR 0026](docs/adr/0026-a-map-is-opened-from-inside-the-workspace.md). This is
  why the version is 2.0.0.
- Your Parties come with you. The first Workspace you open takes the roster 1.2 kept in
  `~/Library/Application Support/MapForge/`, and the app tells you it did. If the move
  fails, nothing is deleted, and the next Workspace opened tries again.
- A recent Workspace is reopened through a bookmark, so one renamed or moved in Finder is
  still found — [ADR 0025](docs/adr/0025-a-workspace-is-reached-through-its-bookmark.md).

### Encounters

- Run a fight from the Control Window's new Combat tab. Start an **Encounter** with the
  Pawns you tick, and **Initiative** is rolled for every Combatant, ready to overtype with
  the numbers the players call out. Return settles the **Order**, and you step through it
  Turn by Turn and Round by Round.
- Each Pawn can keep a **Stat Block**: armour class, hit points, Conditions, exhaustion and
  concentration. It is kept beside the Map, never in the fog file.
- **Bench** a Combatant that has died, fled or stepped aside, rather than striking it
  through. It stays listed under the Order, and benching the one whose Turn it is ends that
  Turn.
- Every Turn goes into the Encounter's **Combat Log**, along with the Pawns' moves on the
  Map. Nothing in it is rewritten: a mistake is fixed by a **Correction** appended after it —
  [ADR 0010](docs/adr/0010-corrections-are-appended-never-edited.md). A fight left
  unfinished is still open when the app returns.
- The **Encounter Difficulty** rates the fight from your notes, live: the Creatures' XP set
  against the party's XP budgets, drawn as a bar before Play and kept above the controls
  while the fight runs. It names every Pawn it could not count, and why —
  [ADR 0032](docs/adr/0032-the-encounter-difficulty-is-reckoned-from-the-notes-live.md).

### The evening's record

- A **Session** is one evening at the table, started from the Live Toolbar. It runs until
  you stop it, even if the app quits. Its **Session Log** records the Pawns' moves and the
  **Comments** you type in the **Comment Bar**, each naming the Map it happened on. During
  an Encounter the Session Log falls silent and the Combat Log takes over —
  [ADR 0014](docs/adr/0014-the-session-log-falls-silent-during-an-encounter.md).
- The **Log View** reads the evening back, with the Session Log and each Combat Log spliced
  in order — [ADR 0016](docs/adr/0016-the-log-view-splices-it-does-not-merge.md).
- Record a **Roll**, a Saving Throw or an Ability Check against its Difficulty Class, as the
  dice fell. MapForge records it and never rolls it for you —
  [ADR 0017](docs/adr/0017-a-roll-is-recorded-not-resolved.md). A Pawn's Rolls are on its
  right-click menu, and the **Modifier** is offered from its note: the Saving Throws of a
  Character or a Monster, and Ability Checks from the note's Skills —
  [ADR 0029](docs/adr/0029-the-modifier-is-offered-from-the-note.md).

### Your notes

- The **Bestiary** reads Monsters from the `statblock` blocks in your markdown notes,
  anywhere in the Workspace, in the format of the Obsidian Fantasy Statblocks plugin —
  [ADR 0020](docs/adr/0020-monsters-are-read-from-the-dms-notes.md). A Monster that
  extends another is its base with the changes. Search it from the Edit Pawn sheet: OK
  stamps the Monster onto the Pawn, and the next Pawn added is the same Monster.
- A **Character** can be tied to its note and takes its numbers from it —
  [ADR 0024](docs/adr/0024-a-characters-numbers-are-read-from-its-note.md). A Pawn's page
  opens in a popover beside its name, and can be pinned into a panel of its own.
- The **Treasury** reads every note whose frontmatter says `item: true` —
  [ADR 0031](docs/adr/0031-an-item-says-so-in-its-frontmatter.md). A **Treasure** can be
  told which **Item** it is, and is relabelled from the Item's initials.
- A note that could not be read is reported beside the search. MapForge never changes your
  notes.

### Faces

- A Pawn can wear a **Face**: a square cut from a picture, drawn in place of its colour on
  both screens. You can cut one by hand, or take the one a Monster's, Character's or Item's
  note gives. The cut is kept in the Workspace —
  [ADR 0028](docs/adr/0028-a-face-is-a-cut-kept-in-the-workspace.md). Re-cutting asks
  whether it is for this Pawn or every one.

### On the Map

- Pawns and Lights are added, edited, moved and deleted in the **Live View**, without
  leaving the table's view. **Add** arms one placement, and the next click lands it,
  inheriting from the last one of its Kind. The Wall Editor is left for Walls alone.
- A **Selection**: ⇧-click Pawns and Lights, or drag a rectangle on the bare Map, then drag
  any member to move them all. Esc lets go.
- One **Magnifier** for the whole Control Window, kept across every mode: two fingers pan, a
  pinch zooms, and what the table sees does not move.
- The Control Window shows the whole Map, with the **Viewport** drawn on it in green, and
  the Viewport can be panned from the Live View.
- **Map Fit** shows the whole Map on the Player Display, letterboxed, as a live departure
  from True Scale — [ADR 0030](docs/adr/0030-map-fit-is-a-live-departure-from-true-scale.md).
- A Measurement can be kept to yourself. One begun from a Pawn is drawn in the Pawn's
  colour, and a Line begun from a Pawn stays where it was drawn when the Pawn moves on.
- A Light can be given a name, which you see and the table never does.
- Your Pawns are drawn on the Control Window even with no Player Display connected.

### Distances and languages

- The **Distance Unit** is metres, at 1.5 m per square, or feet, at 5 ft, and every
  distance the app writes or asks for is in it, sight and Light radii included. Notes
  written in the other unit are flagged —
  [ADR 0027](docs/adr/0027-the-distance-unit-is-the-macs-the-notes-are-checked-against-it.md).
- The **Interface Language** can be English, Italian, German, French, Spanish, Brazilian
  Portuguese or Greek. Rulebook terms are the ones the official edition prints in that
  language, and stay in English where there is none —
  [ADR 0022](docs/adr/0022-rulebook-terms-are-the-tables-not-ours.md).

### Mac App Store

- The app declares what it accesses, ready for the Mac App Store.

## 1.2.0 — 2026-09-11

### Party

- Define the cast once and stop re-entering it: a **Party** is a named roster of
  **Characters**, each a name, a colour, a sight range and whether it is Big. Parties live
  with the DM rather than with any Map, in
  `~/Library/Application Support/MapForge/parties.json`, so they outlive the Map a session
  happens to be run on.
- Start a session by dragging: the active Party sits at the top of the Control Window's live
  panel, and dragging a Character onto the Map **Stamps** a Pawn from it — placed free-form
  under the cursor, live, and written to the Map's fog file on drop rather than on the
  debounce. A drop outside the image creates nothing.
- A Stamp is a copy, never a link. The Pawn takes the Character's fields at drag time and
  then leads its own life, so renaming or deleting a Character afterwards leaves every Pawn
  already on a Map untouched and the fog file readable without the roster —
  [ADR 0007](docs/adr/0007-characters-are-stamped-not-linked.md). Stamp the same Character
  five times and get five working Pawns; the roster shows a `×2`-style placed count for the
  current Map only.
- Authoring is inline, in the panel: a "+" appends an editable row with the same four
  controls the Pawn inspector uses. Roster edits are not Map edits — they stay out of the
  fog undo history, and ⌘Z after a Stamp does not remove the Pawn.
- The Party group appears only once a Map is open, so the drag source is never offered with
  nowhere to drop.

### Icon

- MapForge has an app icon: the forge and a lit dungeon with the fog still rolling over half
  of it.

## 1.1.0 — 2026-09-11

### Measurement

- Measure distances on the Map mid-play: right-click to pick Cone, Square, Circle or Line,
  click where the measurement starts, move the mouse to aim and size it, click again to
  settle it so it stops following the cursor, and click once more to clear it. Each click
  advances one step, and the menu opens on the shape you used last. Esc backs out of a
  measurement you have not placed yet.
- Pin a measurement to keep it on screen: right-click on the shape itself and the menu
  offers Pin instead of the list of shapes. Pinned measurements stay until you unpin them —
  right-click the shape again — so two spell areas can sit side by side, or a route already
  walked can stay up while you measure what is left. The table sees them exactly as it sees
  the live one.
- A Line is a polygonal chain: keep clicking to add points and the running total follows
  the whole path, so a route around a table answers "can I get there this turn" rather
  than just how far away the far wall is. Right-click finishes it and frees the cursor,
  and the finished chain stays up until the next click. It is the one shape that does not
  round to whole squares — each point lands exactly where you put it.
- Clicking a Pawn measures from that Pawn — the shape follows it as it is dragged, and
  ends when the Pawn does. Anywhere else measures from exactly the point clicked; the
  token's own outline is the whole of its hit area, and nothing snaps to the Grid.
- Type an exact distance instead of hunting for the pixel that happens to be 9 m away — the
  number holds while the aim keeps following the cursor.
- Distances read in metres, at 1.5 m to the Grid square. Dragged distances snap to whole
  squares; a typed one does not.
- The table sees the shape *and* its distance, so a measurement settles the range argument
  rather than moving it — the first thing on the Player Display that is instrumentation
  rather than world, and a deliberate one:
  [ADR 0005](docs/adr/0005-the-player-display-shows-the-measurement.md).
- A Cone is as wide at its mouth as it is long (5e's rule), and a Square is a side length
  rather than a radius, because a spell card says "a 20-foot cube".

### Solo Sight

- See the Map as one character alone lights it: isolating a Pawn puts out every other
  Pawn's Light, and the rest of the party is then drawn only where the light that remains
  reaches it — a party member around a corner is genuinely absent from the Player Display.
  The Map's own Lights keep burning, because a brazier is the room rather than another
  character's influence.
- Shown to the table, not only to the DM: a scout goes ahead and the players see what the
  scout's own light finds. The Control Window keeps its readable tint and still draws every
  Pawn, dimming the ones the table has lost, so the DM can see who the mode is costing them.
- One click in the live row beside the eye. At most one Pawn is isolated at a time; the
  mode is never persisted, never undoable, and ends itself on a Map switch, on its Pawn
  being deleted or hidden, and on entering the Fog editing mode.
- The first per-observer rule in the app, and the first thing to make a Pawn's sight and its
  illumination distinguishable — see
  [ADR 0004](docs/adr/0004-solo-sight-is-a-per-observer-view.md).

### Light Markers

- A Light is no longer invisible: a warm dot marks where each of the Map's own Lights
  stands, so the source of a lit region can be seen rather than inferred — on both screens,
  and without opening the Fog editing mode mid-session.
- Players see a marker only where the Light is burning *and* the spot is already lit, the
  same rule a Creature follows, so a doused lantern placed for later never gives away a room
  the party has not reached. The DM sees every Light, doused ones faded.

## 1.0.0 — 2026-09-09

First official build. Everything a DM needs to run a session from a Mac with one HDMI
screen on the table.

### Map Presenter

- Open a Map (PNG, JPEG or WebP) from the Control Window and present it on the Player
  Display at True Scale — one Grid square is one physical inch, sized from the display's
  EDID.
- Player Display picker: choose which connected screen shows the Map, remembered across
  sessions by Display Identity. Auto-selected when exactly one external display is
  connected.
- Grid Fit: declare the Map's Grid by dragging a square over one grid square of the
  artwork, with zoom, ⌥-drag pan and arrow-key nudging in the preview.
- Viewport panning: choose which region of a Map larger than the screen the players see,
  mirrored live on the Player Display.
- The Control Window has no close button, so a stray click cannot end the session; ⌘Q
  quits, flushing any unsaved fog first.

### Fog of War

- Trace Walls, place Lights and Pawns on a Map in a dedicated Fog editing mode. Wall
  vertices snap to each other; nothing snaps to the Grid.
- Visibility is computed from Walls and Lights as exact polygons (ADR-0002): every point
  is bright, dim or unlit.
- Fog Overlay on the Player Display hides unlit regions from players; the Control Window
  shows the same Visibility as a translucent tint so the DM always sees the whole Map.
  Toggle it live.
- Fog, and the Grid with it, persist per Map in `<map>.fog.json` next to the image
  (ADR-0003).
- ⌫ deletes the selected Wall, Light or Pawn; every authoring edit is undoable.

### Pawns, Creatures and Treasure

- A Pawn carries a label, a colour and one sight radius, and lights the Map as far as it
  sees.
- Pawn Kind: Player, Creature or Treasure. Creatures and Treasure emit no Light and are
  drawn under the Fog Overlay, so the players discover them where the light reaches.
- A Creature can be hidden outright from the Player Display without deleting it.
- Big: a Pawn whose token spans 2×2 squares.
- Live play panel down the side of the Control Window: rename, hide and toggle every
  Pawn and Light without leaving the table view.

### Known gaps

- Calibration against a measured ruler, a watched Library folder, Blackout and Map
  rotation are described in `CONTEXT.md` but not built; True Scale relies on the display
  reporting its physical size.
- The UI test target does not run reliably on every machine
  (`.scratch/table-ready/issues/06-ui-tests-running.md`). The 500 unit tests are green.
- The build is ad-hoc signed for personal use, not notarised. macOS may ask you to
  allow it in System Settings → Privacy & Security on first launch.
