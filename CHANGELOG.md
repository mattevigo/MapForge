# Changelog

Versions follow [Semantic Versioning](https://semver.org). `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `project.yml` are the single source of truth; the About
panel reads them from the built app.

## Unreleased

### Measurement

- Measure distances on the Map mid-play: right-click where you want to measure from and
  pick Cone, Square, Circle or Line from the menu, move the mouse to aim and size the
  shape, left-click to settle it so it stops following the cursor, and left-click again to
  clear it. The menu opens on the shape you used last.
- Right-clicking a Pawn measures from that Pawn — the shape follows it as it is dragged,
  and ends when the Pawn does. Anywhere else measures from exactly the point clicked; the
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
  (`.scratch/table-ready/issues/06-ui-tests-running.md`). The 302 unit tests are green.
- The build is ad-hoc signed for personal use, not notarised. macOS may ask you to
  allow it in System Settings → Privacy & Security on first launch.
