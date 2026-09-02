# MapForge

A macOS tool for a DM to present DnD battle maps on an HDMI-attached screen at true physical scale, controlled from a separate window on the Mac's own display.

## Language

**Map**:
A raster image (PNG/JPEG/WebP) with known physical dimensions, shown to players. Physical size derives from its Grid, or from a directly entered real-world size for gridless maps.
_Avoid_: image, battle map, scene

**Grid**:
The square lattice a Map is drawn on. One square is 1 inch physical (the DnD convention for 5 ft). Declaring a Map's size in squares pins its physical dimensions.
_Avoid_: mesh, tiles

**True Scale**:
Rendering a Map so its physical dimensions on the Player Display match its declared real-world dimensions exactly (1 inch of map = 1 inch of screen).
_Avoid_: 1:1, actual size, life size

**Player Display**:
The external (HDMI) screen showing only the Map, fullscreen, with no controls. Auto-selected when exactly one external display is connected.
_Avoid_: TV, second screen, presentation screen

**Control Window**:
The DM-facing window on the Mac's own display: map selection, viewport control, blackout, rotation.
_Avoid_: dashboard, admin window, DM screen

**Library**:
A user-chosen watched folder of Maps. Per-Map settings persist in sidecar metadata so a Map is configured once.
_Avoid_: collection, catalog

**Grid Fit**:
Declaring a Map's Grid by dragging a square over a single grid square of the artwork in the Control Window; the Map's size in squares derives from it. Adjusts the Map's declared size, not the display — that is Calibration.
_Avoid_: calibration, grid detection, auto-grid

**Calibration**:
The per-display correction factor for True Scale. EDID physical size is the default; a measured ruler check overrides it, saved per display.
_Avoid_: DPI setting, scaling

**Display Identity**:
The stable key for a physical display, used to remember which screen is the Player Display and, later, its Calibration. Derived from the display's UUID, not the `CGDirectDisplayID`, which macOS reassigns on replug and across reboots.
_Avoid_: screen ID, display number, monitor name

**Viewport**:
The region of a Map currently visible on the Player Display. At True Scale most Maps exceed the screen, so the DM pans the Viewport from the Control Window.
_Avoid_: camera, crop, window

**Sidecar**:
The per-Map metadata file stored next to the image. Fog — Walls, Lights and Pawns — lives in `<map>.fog.json`; the Grid, rotation and scale settings it was also meant to hold are not persisted at all yet.
_Avoid_: config file, manifest

**Blackout**:
Instantly replacing the Player Display's content with a blank screen, hiding the Map from players.
_Avoid_: curtain, screen off

**Wall**:
A two-sided line segment that blocks Light. Stored in the Map's image pixels, so it stays welded to the artwork when the Grid changes. Four implicit Walls at the image bounds are always present and cannot be edited.
_Avoid_: barrier, occluder, edge, boundary

**Light**:
A point source that illuminates the Map out to a bright radius and a dim radius, measured in Grid squares. Blocked by Walls, and independently switchable on or off.
_Avoid_: lamp, torch, emitter, light source

**Pawn**:
A token on the Map with a label and a colour, drawn for players whether or not the Fog Overlay is active. A Pawn is also a Light: its range of sight and its range of illumination are the same thing. Moving a Pawn during play is a live action and is not undoable; moving one while authoring fog is an edit and is.
_Avoid_: token, miniature, figure, character, marker

**Creature**:
A Pawn the players discover rather than one they carry: it emits no Light, and it is drawn under the Fog Overlay so darkness hides it from players. The DM always sees Creatures, and can hide one outright — a hidden Creature is invisible to players however well lit it is. A flag on Pawn, not a separate kind.
_Avoid_: monster, enemy, NPC, mob

**Big**:
A Pawn whose token occupies 2×2 Grid squares instead of 1×1 — an ogre, not a goblin. Purely visual: its Light radii and its sight are still measured from its point, because a creature's size does not change how far it sees or how far its torch reaches.
_Avoid_: large, size category, huge

**Visibility**:
The three-valued result of tracing every Light against every Wall — each point of the Map is bright, dim, or unlit. Computed in Map space and unaffected by panning the Viewport.
_Avoid_: light map, shadow map, fog data, mask

**Fog Overlay**:
The darkness drawn over the Map from its Visibility, hiding unlit regions from players. Players see it on the Player Display; the Control Window instead shows the Map fully lit with the same Visibility as a translucent tint, so the DM always sees everything. Switchable off entirely.
_Avoid_: fog of war, darkness layer, shroud, mask
