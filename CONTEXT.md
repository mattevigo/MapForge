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
A point source that illuminates the Map out to a bright radius and a dim radius, measured in Grid squares. Blocked by Walls, and independently switchable on or off. Drawn as a Light Marker where players can see it.
_Avoid_: lamp, torch, emitter, light source

**Pawn**:
A token on the Map with a label and a colour, drawn for players whether or not the Fog Overlay is active — unless its Pawn Kind is one the players must discover, or Solo Sight is on. A Pawn is also a Light: its range of sight and its range of illumination are the same thing, except under Solo Sight, where one Pawn's sight decides what the whole table can see. It has **one** radius — its sight — unlike a Light, which has a bright and a dim band; DnD gives a character a sight range, not a band of dim vision. The region fades out over one further square purely so its edge is not a hard cut. Moving a Pawn during play is a live action and is not undoable; moving one while authoring fog is an edit and is.
_Avoid_: token, miniature, figure, character, marker

**Pawn Kind**:
What a Pawn is: a **Player**, a **Creature**, or a **Treasure**. The three are mutually exclusive, so one enum on Pawn rather than a boolean each. Only two things branch on it — whether the Pawn emits Light, and which side of the Fog Overlay it draws on — and both follow from whether the players *discover* it.
_Avoid_: type, category, role

**Creature**:
A Pawn the players discover rather than one they carry: it emits no Light, and it is drawn under the Fog Overlay so darkness hides it from players. The DM always sees Creatures, and can hide one outright — a hidden Creature is invisible to players however well lit it is. A Pawn Kind, not a separate type.
_Avoid_: monster, enemy, NPC, mob

**Treasure**:
A chest, a hoard, a body — something the players find rather than fight. Discovered exactly as a Creature is: no Light, hidden by darkness, revealed where the light reaches it. It differs only in being drawn as a rounded square rather than a disc, and in being listed in its own group, because a DM reasons about loot and monsters separately. Size stays orthogonal — a Treasure can be Big.
_Avoid_: loot, chest, item, object

**Big**:
A Pawn whose token occupies 2×2 Grid squares instead of 1×1 — an ogre, not a goblin. Independent of Pawn Kind: a big hoard is as meaningful as a big monster. Purely visual: its Light radii and its sight are still measured from its point, because a creature's size does not change how far it sees or how far its torch reaches.
_Avoid_: large, size category, huge

**Visibility**:
The three-valued result of tracing every Light against every Wall — each point of the Map is bright, dim, or unlit. Computed in Map space and unaffected by panning the Viewport.
_Avoid_: light map, shadow map, fog data, mask

**Fog Overlay**:
The darkness drawn over the Map from its Visibility, hiding unlit regions from players. Players see it on the Player Display; the Control Window instead shows the Map fully lit with the same Visibility as a translucent tint, so the DM always sees everything. Switchable off entirely.
_Avoid_: fog of war, darkness layer, shroud, mask

**Solo Sight**:
Isolating one Pawn so the table sees the Map as that character alone lights it: every *other* Pawn stops emitting Light, and each Pawn is then drawn only where the light that remains reaches it, exactly as a Creature is. The Map's own Lights keep burning — a brazier is the room, not another character's influence. At most one Pawn is isolated at a time. A live performance action, shown on both screens, never persisted: the Control Window keeps its readable tint and still draws every Pawn, dimming the ones the table has lost.
_Avoid_: field of view, line of sight, per-player fog, spotlight, focus mode

**Light Marker**:
The dot drawn where a Light stands, so the source of a lit region can be seen rather than inferred. On both screens. Players see one only where the Light is burning *and* the spot is already lit — the rule a Creature follows — so an unlit fixture never gives away a room the party has not reached. The DM sees every Light, doused ones included, because a DM who cannot find their own torches cannot run the fight.
_Avoid_: light source, torch icon, lamp, emitter dot

**Measurement**:
A distance the DM asks about mid-play, drawn on the Map as a shape from an Origin and labelled with its length. At most one exists at a time, and it is never persisted — a question asked during a turn and dismissed after it, like Solo Sight rather than like a Wall.
_Avoid_: measure, ruler, template, marker

**Measurement Shape**:
Which shape a Measurement takes: a **Cone**, a **Square**, a **Circle** or a **Line**. Circle is drawn around the Origin as a radius; Square is drawn around the Origin as a *side length*, because that is how a spell describes a cube. Cone is a length from the Origin towards the cursor. The readout names which it is — "6 m radius" against "6 m across" — so the distinction is read rather than assumed.
_Avoid_: measure type, tool, template shape

**Line**:
The one Measurement Shape that is a **polygonal chain** rather than a region: a run of points from the Origin, whose readout is the length of the whole path. It answers the movement question — can I get there this turn, going round the table rather than through it — where the other three answer straight-line range. Alone among the shapes it does not snap to whole squares, because rounding every vertex would compound the error along a long path.
_Avoid_: linear, ruler, path, polyline

**Measurement Origin**:
Where a Measurement starts: either a point on the Map, or a Pawn — in which case it starts at that Pawn's centre and follows it as the Pawn moves. A Measurement anchored to a Pawn ends when that Pawn does.
_Avoid_: anchor, start point, source

**Distance Unit**:
The unit the table speaks distances in — currently **metres**, at 1.5 m per Grid square. Grid squares remain the unit distances are *stored* in; the Distance Unit is applied when a distance is shown. Feet is the other unit this is meant to become, which is why it is a choice and not a constant.
_Avoid_: units, scale, measurement system
