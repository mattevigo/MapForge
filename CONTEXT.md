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
A token on the Map with a label and a colour, drawn for players whether or not the Fog Overlay is active — unless its Pawn Kind is one the players must discover, or Solo Sight is on. A Pawn is also a Light: its range of sight and its range of illumination are the same thing, except under Solo Sight, where one Pawn's sight decides what the whole table can see. It has **one** radius — its sight — unlike a Light, which has a bright and a dim band; DnD gives a character a sight range, not a band of dim vision. The region fades out over one further square purely so its edge is not a hard cut. Moving a Pawn during play is a live action and is not undoable; moving one while authoring fog is an edit and is. Either way a Pawn never leaves the Map: a drag past the image edge stops at the edge, as a Stamp outside it is refused, because a Pawn beyond the implicit Walls is meaningless to Visibility and, on the clipped mirror, unreachable. A Pawn Stamped from a Character remembers which one, but only so the roster can show how many of its Pawns are on this Map — the memory is advisory, and a Pawn whose Character is gone is in no way diminished.
_Avoid_: token, miniature, figure, character, marker

**Character**:
A member of the party, defined once and reused across every Map: a name, a colour, a sight range and whether it is Big. Always a Player — the cast a DM re-places every session — never a Creature or a Treasure, which are per-encounter and stay placed by hand. It carries no portrait: a Character is drawn exactly as the Pawn it stamps is. It is a definition, not a token; it is never on a Map, and a Pawn is what appears there.
_Avoid_: PC, hero, player character, actor, token template

**Party**:
A named roster of Characters — a campaign's cast, defined once. Parties live with the DM rather than with any Map, so they outlive the Map a session happens to be run on. One Party is active at a time, and the active one is what the Control Window offers; the rest keep existing, unlisted. Deleting a Party is a change to the roster and never touches a Pawn already on a Map.
_Avoid_: group, team, roster, campaign

**Stamp**:
Creating a Pawn from a Character by dragging the Character onto the Map. The Pawn is a **copy**, not a link: it takes the Character's name, colour, sight and size at that moment and then leads its own life. Renaming or deleting the Character afterwards leaves every Pawn already stamped from it untouched — the Map's own file stays self-contained and readable without the roster. Stamping is a live action like moving a Pawn, not an edit like tracing a Wall: it needs no mode and is not undoable. The same Character may be stamped any number of times, and each Pawn bears the same label.
_Avoid_: instantiate, spawn, place, drop, add to map

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
A distance the DM asks about mid-play, drawn on the Map as a shape from an Origin and labelled with its length. One is being taken at a time; any number can be **Pinned** alongside it. Never persisted — a question asked during a turn, like Solo Sight rather than like a Wall.
_Avoid_: measure, ruler, template, marker

**Pinned**:
A settled Measurement parked on the Map, which stays until it is unpinned instead of being cleared by the next click. Pinning is what lets a DM hold one answer on screen — a spell area, a route already walked — while measuring the next thing. Shown to the table exactly as the live Measurement is, and cleared with the Map it was taken on.
_Avoid_: locked, saved, sticky, kept

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

**Encounter**:
One fight on one Map, from the moment the DM starts it to the moment they stop it. It holds an Order of Combatants and a Round number, and it writes a Combat Log. A Map accumulates Encounters over a campaign; at most one is live at a time. Stopping one neither heals anyone nor clears their Conditions — a fight ending is not a rest, and the state a party fought three Rounds to reach is the state they are in.
_Avoid_: combat, fight, battle, session

**Combatant**:
A Pawn taking part in the live Encounter: one with an Initiative and a place in the Order. Not a type but a role — a Pawn is a Combatant only on the Map it stands on and only while that Encounter runs. A Treasure is never one, having nothing to do on its turn. A Combatant removed from the Map stops taking Turns but stays listed, because the Combat Log already names it and a monster that died in Round 2 is part of what happened.
_Avoid_: participant, actor, entity, fighter

**Entrant**:
A Pawn on its way into an Encounter — what a Combatant is before it has an Initiative. It exists because joining takes a name, a Kind and a Stat Block from the Map and gives back a place in the Order, and the thing going in is not yet the thing coming out. A Treasure can be offered as an Entrant and is simply refused.
_Avoid_: candidate, applicant, joiner, participant

**Stat Block**:
A Pawn's combat numbers: initiative bonus, armour class, current, maximum and temporary hit points, its Conditions, its exhaustion level and whether it is concentrating. Kept beside the Map but never inside the fog file, because a fog file must stay readable by a DM who has never run a fight on it. Every Pawn may have one, Players and Creatures alike: the two differ in what a DM habitually tracks, not in what the rules permit, so the shape is one shape.
_Avoid_: stats, sheet, character sheet, attributes, vitals

**Initiative**:
A Combatant's place-deciding number, rolled as 1d20 plus its initiative bonus when the Encounter starts. Rolled for every Combatant, Players included — overtyping a number the players call out is faster than typing into an empty field. Editable at any time; changing it does not by itself move anyone, because the Order is the DM's.
_Avoid_: init, roll, initiative score

**Order**:
The sequence Combatants take Turns in. Settled when the Encounter starts by sorting on Initiative, and from then on the DM's to rearrange by hand — ties are not broken by a rule, they are broken by the person running the table. Because the Order is decided rather than derived, it is recorded, not recomputed.
_Avoid_: initiative order, turn order, queue, lineup

**Turn**:
One Combatant acting: everything between the previous advance and the next one. A Turn ends by writing exactly one line to the Combat Log, carrying its Round, its Combatant and every Change made while it ran — including Changes to somebody else, because a Turn records what happened during it, not what happened to one Pawn.
_Avoid_: move, action, step, go

**Round**:
One pass through the whole Order. Advancing past the last Combatant wraps to the first and increments the Round silently, with no confirmation, because the table is waiting. A Round number is a fact about history: it never resets mid-Encounter, not even when Initiative is re-rolled.
_Avoid_: cycle, pass, sequence

**Combat Log**:
The append-only record of an Encounter, one line per Turn. Never rewritten and never deleted from: a mistake is amended by a Correction appended after it, so what happened at the table stays readable next to what the DM later wished had happened. Written at the end of each Turn, which is the most that can be lost to a crash.
_Avoid_: history, journal, transcript, audit, replay

**Change**:
One recorded mutation during a Turn — a hit point edit, a Condition applied, a Pawn moved, a note taken. Carries the Combatant it targets and the value both **before and after**, never a delta, so the Combat Log can be replayed exactly and a Correction is unambiguous about what it corrects.
_Avoid_: event, mutation, delta, edit, update

**Correction**:
A Change appended against a Turn that has already ended. The amended Turn's own line is untouched; the Correction is a new line naming the Turn it targets. Reading the Log folds Corrections onto their Turns. Hit points, Conditions and notes can be corrected; a movement cannot, because where a Pawn stands is the Map's truth and cannot be retroactively somewhere else.
_Avoid_: undo, fix, amend, retcon, revision

**Condition**:
One of the fourteen boolean states of DnD 5.5e a Combatant can be under — Prone, Restrained, Blinded, and the rest. Exhaustion is deliberately not one of them: it is a level from 0 to 6 and is tracked apart. Conditions carry no duration and expire on nobody's schedule: encoding "until the end of your next turn" and its cousins is a system in itself, and half of that system is worse than a DM's memory.
_Avoid_: status, effect, debuff, ailment, state
