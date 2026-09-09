# Changelog

Versions follow [Semantic Versioning](https://semver.org). `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `project.yml` are the single source of truth; the About
panel reads them from the built app.

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
