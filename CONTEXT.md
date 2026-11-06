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
Rendering a Map so its physical dimensions on the Player Display match its declared real-world dimensions exactly (1 inch of map = 1 inch of screen). The way a Map is drawn unless the DM has switched on Map Fit, and what every launch starts with.
_Avoid_: 1:1, actual size, life size

**Map Fit**:
Showing the whole Map on the Player Display as large as it fits, in its own proportions: centred, black letterbox along the two sides it does not reach, and never a crop. The counterpart of True Scale, switched on and off from the Live Toolbar, and never saved — not per Map, not per display, not across launches. It switches itself off when the Player Display goes, since there is nothing left to fit the Map to. The Map's declared size and its Grid stand as they are, and Map Fit ignores them: the image's own shape is what it keeps, so a Map smaller than the screen is enlarged and a larger one shrunk, never distorted. Everything placed on the Map — Pawns, Lights, Fog, Measurements — stays in Map space and scales with the artwork, and a Measurement still reads its true distance in squares. Distinct from Grid Fit, which declares the Grid and changes nothing on the Player Display.
_Avoid_: fit to screen, stretch, zoom to fit, scaling

**Player Display**:
The external (HDMI) screen showing only the Map, fullscreen, with no controls. Auto-selected when exactly one external display is connected.
_Avoid_: TV, second screen, presentation screen

**Control Window**:
The DM-facing window on the Mac's own display: map selection, viewport control, blackout, rotation.
_Avoid_: dashboard, admin window, DM screen

**Workspace**:
The folder a DM keeps their game in, chosen once: its Maps sit inside it, in whatever subfolders they arrange — one campaign or a shelf of them — and `.mapforge/` at its root holds what the app knows that is not about a Map, its Parties first among them. A Workspace is a home, not a campaign: it draws no line between the campaigns inside it, because the DM already draws that line in Finder and a second one in the app would be a second thing to keep in step. One is open at a time, and the last one opened is the one the app returns to. It replaces the **Library**, a watched folder of Maps that was described but never built.
_Avoid_: library, project, campaign, campaign folder, vault, collection, catalog

**Manifest**:
`.mapforge/workspace.json`, the file whose presence makes a folder a Workspace. It records the layout's version and what wrote it, and nothing else — the Workspace is named by its folder, so there is no name here to drift out of step with the one in Finder. A folder without a Manifest is an ordinary directory the DM may adopt; a Workspace whose Manifest is unreadable is not a Workspace the app will guess at.
_Avoid_: index, config, metadata, workspace file

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
The region of a Map currently visible on the Player Display. It belongs to True Scale. Under Map Fit the players see the whole Map, so the Viewport *is* the whole Map: the green rectangle covers all of it and its toggle is unavailable, since there is nothing to pan — an armed rectangle puts itself away. Map Fit never moves the Viewport, so switching it off returns the table to exactly the region it had. At True Scale most Maps exceed the screen, so the DM moves the Viewport from the Live View, where it is always drawn as a green rectangle over the whole Map — knowing what the players can see is not a question a DM should press a button to answer. A toggle decides whether that rectangle can be **dragged**, not whether it is drawn: idle it is an outline the clicks pass through, armed it is filled and moves. Moving it is a live action the table watches as it happens, so it has no Cancel, exactly as dragging a Pawn has none.
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
A point source that illuminates the Map out to a bright radius and a dim radius, measured in Grid squares. Blocked by Walls, and independently switchable on or off. Drawn as a Light Marker where players can see it. It carries a **name** — the DM's own, like a Pawn's label and never drawn on the Player Display, so a Light can be called "trapped brazier" without the name crossing the room. The name is assigned when the Light is placed and is what the roster identifies it by; before names existed a Light was known by its position in that list, so deleting one silently renamed another. Like a Pawn, a Light is placed, edited and **moved** in the Live View, never in the Wall Editor: the DM drags its Light Marker, the darkness follows on both screens as they do, and a drag past the image edge stops at the edge — a Light beyond it could never be clicked again. Moving one is a live action and is not undoable; unlike a Pawn's move it is recorded in no Log, because a torch is the room and the Logs are about who was in it.
_Avoid_: lamp, torch, emitter, light source

**Pawn**:
A token on the Map with a label and a colour, drawn for players whether or not the Fog Overlay is active — unless its Pawn Kind is one the players must discover, or Solo Sight is on. Its **colour** is what the table identifies it by, unless it has a Face, which then covers the colour and is identified instead; its **label** is the DM's own bookkeeping and is never drawn on the Player Display, so a Pawn can be named for the DM's notes without the name crossing the room. A Pawn is also a Light: its range of sight and its range of illumination are the same thing, except under Solo Sight, where one Pawn's sight decides what the whole table can see. It has **one** radius — its sight — unlike a Light, which has a bright and a dim band; DnD gives a character a sight range, not a band of dim vision. The region fades out over one further square purely so its edge is not a hard cut. Every change to a Pawn — moving it, adding it, editing its fields, deleting it — is a live action in the Live View and is not undoable; the Edit Pawn sheet's Cancel is the escape instead. A Pawn cannot be edited in the Wall Editor at all. A Pawn never leaves the Map: a drag past the image edge stops at the edge, as a Stamp outside it is refused, because a Pawn beyond the implicit Walls is meaningless to Visibility and, on the clipped mirror, unreachable. A Pawn Stamped from a Character remembers which one, but only so the roster can show how many of its Pawns are on this Map, the DM can be shown that Character's page while it fights and offered its bonus when it rolls, and a Face re-cut for every one of its Pawns reaches them — the memory is advisory, and a Pawn whose Character is gone, or has no note, loses a badge, a page and a suggestion and is otherwise in no way diminished.
_Avoid_: token, miniature, figure, character, marker

**Live View**:
The Control Window's ordinary state: the **whole Map**, with Pawns, Light Markers, the Fog Overlay tint and Measurements drawn over it, and the Viewport drawn on it as a green rectangle. Everything a DM does to a Pawn or a Light happens here — adding, editing, moving, deleting — because there is no moment in a session when the DM wants to leave the table's view to change a token. It showed only what the Player Display showed until the rectangle replaced that: a DM who can see just the Viewport cannot see what is about to walk into the room, and cannot place anything outside it without panning there first.
_Avoid_: preview, preview mode, normal mode, play mode, mirror

**Magnifier**:
The Control Window's private zoom: the DM looks closer without the Viewport moving, so the Player Display keeps showing exactly what it showed. There is **one** Magnifier for the whole Control Window, not one per mode — the Live View, the Wall Editor and Grid Fit all show the Map at the same magnification, so a DM who zooms into a room and opens the Wall Editor is still looking at that room, and still is after closing it. Arming the Viewport does not end it either: the rectangle is drawn on the magnified Map and stays true there. Nor does a Cancel, a new Grid, or a visit to the Log View — Cancel undoes edits, and where the DM was looking is not an edit. Only two things end it: opening a different Map, and zooming back out — the zoom's floor is the whole Map, so there is nowhere past it to be stuck. Never persisted. It answers the same gestures everywhere: the mouse wheel or a trackpad pinch zooms, and ⌘-scroll zooms on any device, which is how a Magic Mouse zooms at all; a two-finger swipe, a wheel tilted sideways, the held middle button (the cursor a closed hand) or ⌥-drag slides the artwork, as far as its own edges. Sliding it never moves the Viewport, even with the rectangle armed and under the cursor — moving what the table sees is a deliberate primary-button drag the table watches, and a swipe is too easy to make by accident. It said so on screen once, in a "Zoomed — Reset" button that appeared beside Grid Fit while it was on; the button is gone and the artwork's own size is what tells the DM.
_Avoid_: zoom, preview zoom, magnification

**Wall Editor**:
The prep-time mode for tracing Walls, entered deliberately and left again. It is the one place Wall geometry can be authored, and the only thing it authors: Pawns and Light Markers are drawn in it for reference — a Wall is traced against the room its tokens stand in — but cannot be selected, moved or edited there. Its edits are undoable, unlike the Live View's, because tracing is slow precise work and a misplaced vertex is a mistake rather than a move.
_Avoid_: fog editor, edit fog, fog mode, authoring mode

**Add**:
Arming the Live View to place one new thing — a Light, or a Pawn of any Kind — chosen before it is placed and landed by the next click on the Map. The Kind is settled at the moment of arming rather than in an editor afterwards, so a DM adding four goblins arms once per goblin and never opens a form. What is placed inherits from the last thing of that Kind placed, so the second goblin is already the right colour, size and Face — and the same Monster, taken afresh from the Bestiary at full hit points and with the Monster's own Face rather than copied from its sibling's wounds; and the second Borsa is the same Item, with the Item's own Face rather than its sibling's. A Monster or Item that has left the notes is not inherited, and the new Pawn is a plain Creature or Treasure. At most one thing is armed at a time, Measurement included, and Esc backs out.
_Avoid_: create, insert, new, place, spawn

**Character**:
A member of the party, defined once and reused across every Map: a name, a colour, a sight range, whether it is Big, and the combat numbers a Stamp copies into its Pawn's Stat Block — armour class, maximum hit points and initiative bonus. Its numbers and its size are written in the DM's notes, as a Monster's are, and only read by the app, never typed into it — a Character who levels up is changed in the notes and met changed the next time the Workspace opens. What the notes do not hold is the app's own: its name, its colour and its sight. The name is the DM's label for it, and need not be the note's — "Durga" reads her numbers from Durga Pietraferma's note — because the Character remembers which note is its own separately from what it is called. Which note that is, the DM says — the app never guesses it from a name, however alike the two are. A note the DM marked as not in the bestiary — a Character's past build kept for the record — is no Character either, so a hero has one note and one set of numbers. A Character whose note cannot be found, or who never had one, keeps its name, colour and sight and has no numbers: its Pawns are stamped without them, for the DM to type on the Pawn, exactly as a Creature whose Monster has left the notes loses the page and nothing else. Its sight is never read from the notes, darkvision included, because a Pawn's sight is also the light it sheds for the whole table. Always a Player — the cast a DM re-places every session — never a Creature or a Treasure, which are per-encounter and stay placed by hand. It may carry a Face, cut by the DM, which wins over the one its note names; a Character is drawn exactly as the Pawn it stamps is. It is a definition, not a token; it is never on a Map, and a Pawn is what appears there.
_Avoid_: PC, hero, player character, actor, token template

**Party**:
A named roster of Characters — a campaign's cast, defined once, and chosen in the app: who sits at the table is the table's decision, not the notes', which may list the dead and the absent among a campaign's heroes. Parties belong to a Workspace rather than to any Map, so they outlive the Map a session happens to be run on, and a DM running several campaigns out of one Workspace keeps a Party for each. One Party is active at a time, and the active one is what the Control Window offers; the rest keep existing, unlisted. Deleting a Party is a change to the roster and never touches a Pawn already on a Map.
_Avoid_: group, team, roster, campaign

**Stamp**:
Creating a Pawn from a Character by dragging the Character onto the Map. The Pawn is a **copy**, not a link: it takes the Character's name, colour, sight and size at that moment and then leads its own life. Renaming or deleting the Character afterwards leaves every Pawn already stamped from it untouched — the Map's own file stays self-contained and readable without the roster. Stamping is a live action like moving a Pawn, not an edit like tracing a Wall: it needs no mode and is not undoable. The same Character may be stamped any number of times, and each Pawn bears the same label. The word is also used of a Monster: a Creature said to be one is **stamped** with the Monster's numbers — the same copy-not-link, landing on a Pawn that already exists rather than creating one.
_Avoid_: instantiate, spawn, place, drop, add to map

**Pawn Kind**:
What a Pawn is: a **Player**, a **Creature**, or a **Treasure**. The three are mutually exclusive, so one enum on Pawn rather than a boolean each. Only two things branch on it — whether the Pawn emits Light, and which side of the Fog Overlay it draws on — and both follow from whether the players *discover* it.
_Avoid_: type, category, role

**Creature**:
A Pawn the players discover rather than one they carry: it emits no Light, and it is drawn under the Fog Overlay so darkness hides it from players. The DM always sees Creatures, and can hide one outright — a hidden Creature is invisible to players however well lit it is. A Pawn Kind, not a separate type.
_Avoid_: monster (that is the definition, not the Pawn), enemy, NPC, mob

**Monster**:
A kind of creature as the DM's notes define it — a Gnoll Guerriero, a Wraith — with the numbers and actions the rulebook gives it. It is a definition, not a token: it is never on a Map, never wounded, and four gnoll Pawns share one Monster while each keeps its own Stat Block. It stands to a Creature as a Character stands to a Player's Pawn, and is taken the same way: saying which Monster a Creature is **copies** the Monster's armour class, hit points and initiative bonus into that Pawn's Stat Block, its size into whether the Pawn is Big, and its Face, if its note names a picture, onto the Pawn, and from then on the Pawn leads its own life. Becoming a Monster means arriving whole — hit points at their maximum — so making a Pawn that already has hit points into a Monster heals it, and the app asks before it does; Conditions, exhaustion and temporary hit points are the fight's and are left alone. A Pawn still labelled with the bare number it was born with is relabelled from the Monster's initials — GG1, GG2 for two Gnoll Guerrieri — numbered so that no two labels on the Map match, and so is one still labelled with the initials of the Monster it was before, so a Gnoll Guerriero made into an Ogre stops being GG1; a label the DM typed is never touched. The Pawn remembers which Monster it was, but only so the DM can be shown the Monster's actions while it fights, be offered its bonus when it rolls, and a Face re-cut for every one of its Pawns reaches them — the memory is advisory, and a Creature whose Monster has left the notes loses a page of reference and a suggestion, and nothing else. Only a Creature can be a Monster: a Player's numbers come from its Character, and a Treasure has none. The word covers whatever the notes define this way, a human guard included — it names the role in the app, not the thing's nature. A Monster may be written as another Monster with changes — a named guard who is an Esploratore with more hit points — and is then that Monster with those changes laid over it; the changes replace what they name and leave the rest. The DM writes a Monster in their own notes, in the `statblock` notation those notes already use; that word is the file's syntax and is never a **Stat Block**, which is a Pawn's live numbers.
_Avoid_: statblock, stat block, creature template, bestiary entry, NPC

**Bestiary**:
Every Monster the app has read from the Workspace — the collection a DM searches when saying what a Creature is. It belongs to the Workspace, as a Party does, but unlike a Party it is never authored in the app: the DM's notes are the only place a Monster is written, and the Bestiary is only ever a reading of them. It is read from every note in the Workspace — wherever the DM keeps a Monster, a campaign's own creatures and its named NPCs included — except a note that says it is not one, and a Character's, which is a Character. It is read when the Workspace opens and at no other time — a Monster written mid-evening is met the next time the Workspace is opened — and it is never kept on disk, because a second copy of the notes is a second thing to keep in step with them.
_Avoid_: monster library, compendium, monster cache, catalog, manual

**Treasure**:
A chest, a hoard, a body — something the players find rather than fight. Discovered exactly as a Creature is: no Light, hidden by darkness, revealed where the light reaches it. It differs only in being drawn as a rounded square rather than a disc, and in being listed in its own group, because a DM reasons about loot and monsters separately. Size stays orthogonal — a Treasure can be Big. A Treasure can be said to be an **Item** from the **Treasury**, as a Creature can be said to be a Monster.
_Avoid_: loot, chest, item (that is the definition, not the Pawn), object

**Item**:
A thing as the DM's notes define it — a Borsa, a Gemma di Fuoco. It is to a Treasure what a Monster is to a Creature: a definition, never on a Map, and three Borse on a Map share one Item. A note is an Item when its frontmatter says `item: true`, wherever the note lives; nothing else makes one, a `statblock` fence included. Its name is the note's first heading, or its file name when it has none. Saying which Item a Treasure is **copies**, as a Monster does: a Treasure still labelled with its bare number, or with the initials of the Item it was, is relabelled from the Item's initials — Bo1, Bo2 for two Borse — by the Monster's rule, and a label the DM typed is never touched. Its picture, when its frontmatter names one, becomes the Treasure's Face, as a Monster's does. There are no numbers to copy: an Item has none. The Treasure remembers which Item it was, advisorily, as a Creature remembers its Monster — so that a Face re-cut for every Treasure of that Item reaches it — and forgets it when it stops being a Treasure. Only a Treasure can be an Item.
_Avoid_: object, equipment, loot, magic item (one kind of Item, not the word for all of them)

**Treasury**:
Every Item the app has read from the Workspace — the collection a DM searches when saying what a Treasure is. The Bestiary's sibling, and on the same terms: read in the same walk over the notes, when the Workspace opens and at no other time, never authored in the app and never kept on disk. A note marked as an Item that cannot be read, or that names an Item another note already defines, is skipped and listed with its reason, never dropped in silence.
_Avoid_: inventory (that is a Character's), item library, catalog, loot table

**Big**:
A Pawn whose token occupies 2×2 Grid squares instead of 1×1 — an ogre, not a goblin. Independent of Pawn Kind: a big hoard is as meaningful as a big monster. Purely visual: its Light radii and its sight are still measured from its point, because a creature's size does not change how far it sees or how far its torch reaches.
_Avoid_: large, size category, huge

**Face**:
A square cut from a picture, which a Pawn is drawn as in place of its colour. Any Pawn Kind may have one. It covers the whole token — neither the colour nor the label is drawn over it, on either screen — and the token keeps its shape, a disc or a rounded square, so the Face is what the table identifies that Pawn by. The DM, who must still tell GG2 from GG3, is shown the label on the Control Window only while the pointer rests on the token. It is hidden exactly as the rest of the token is: by darkness, by hiding, by Solo Sight. The colour stays the Pawn's underneath, unseen, so removing the Face shows it again. The DM **cuts** it, choosing which square of the picture to keep, and what the app keeps is that square, copied into the Workspace — never the picture itself, so a picture moved, replaced or deleted afterwards leaves every Face cut from it intact. A Face reaches a Pawn five ways: cut by hand for that Pawn; carried by a Character, cut by hand for it, and copied by the Stamp; named by a Monster's or Character's note, whose `statblock` names a picture under `image:` as a link to a note's picture, never a web address — cut once for that Monster or Character, the centred square until the DM cuts another, and given to every Pawn that takes it; named by an Item's note, whose frontmatter names a picture under `image:` read the same way — cut once for that Item and given to every Treasure that becomes it; or inherited under Add from the last Pawn of its Kind placed. A Character's own Face wins over its note's. A note that names a picture the Workspace does not hold, or names it by a file name two pictures share, gives no Face, and the app says so; it never guesses a picture from a name. Like everything a Pawn takes from a definition, a Face is a copy: a new picture in the note reaches the Pawns that take it afterwards, never the ones already on a Map. The one exception is the DM's own: re-cutting a Face that came from a Monster, a Character or an Item asks whether to re-cut it for this Pawn alone or for the definition — and the latter re-cuts every Pawn on this Map that took its Face from it, as well as every Pawn that takes it afterwards. A Face a Pawn took from the Monster it *was* goes when it becomes another Monster — replaced by the new Monster's, or by its colour if the new one has none — exactly as a label taken from the old Monster's initials does, and a Face a Treasure took from the Item it was goes the same way when it becomes another Item; a Face the DM cut for that Pawn by hand, or one a Character gave, is never touched.
_Avoid_: portrait, image, avatar, picture, token art, icon

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
A distance the DM asks about mid-play, drawn on the Map as a shape from an Origin and labelled with its length. One is being taken at a time; any number can be **Pinned** alongside it. Never persisted — a question asked during a turn, like Solo Sight rather than like a Wall. The table sees it by default, because it usually answers a question the players asked; a switch on the Control Window withholds it for the kind a DM takes for themselves, where the distance is the tactical fact they are deciding whether to reveal. The DM sees their own either way.
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
The unit the table speaks distances in — **metres**, at 1.5 m per Grid square, or **feet**, at 5 ft — chosen by the DM, and from then on every distance the app writes or asks for is in it, a Pawn's sight and a Light's radii included. Both are names for the Grid square, not conversions of each other, so a 6 m fireball is a 20 ft fireball as the two editions print it, never the 19.7 ft a tape measure would say. Grid squares remain the unit distances are *stored* in; the Distance Unit is only how a distance is shown, not part of what happened, so changing it re-reads every distance already on screen or in a Log. Chosen per Mac, as the Interface Language is, and until it is chosen it follows the Mac's region. The Workspace holds no unit of its own: its unit is whatever the DM's notes are written in, and those are expected to speak the Distance Unit too. A Monster or Character whose note gives its speed or senses in the other unit is read and stamped all the same — the app says so and never rewrites the note, because the notes are the DM's.
_Avoid_: units, scale, measurement system, measures

**Encounter**:
One fight on one Map, from the moment the DM starts it to the moment they stop it. It holds an Order of Combatants and a Round number, and it writes a Combat Log. A Map accumulates Encounters over a campaign; at most one is live at a time. Stopping one neither heals anyone nor clears their Conditions — a fight ending is not a rest, and the state a party fought three Rounds to reach is the state they are in. An Encounter sits *inside* a Session — the evening it is one fight of — so one cannot be started before the Session has: a fight begun during prep would be a Combat Log no evening points at, and the Log View could never show it. The rule is about starting; a fight already running is not ended by it. While it runs it is the only thing recording: the Session Log falls silent and resumes when the fight stops.
_Avoid_: combat, fight, battle

**Combatant**:
A Pawn taking part in the live Encounter: one with an Initiative and a place in the Order. Not a type but a role — a Pawn is a Combatant only on the Map it stands on and only while that Encounter runs. A Treasure is never one, having nothing to do on its turn. A Pawn taken out of the Order stops being a Combatant and becomes Benched; the Combat Log still names it, because a monster that died in Round 2 is part of what happened whatever the tracker shows now.
_Avoid_: participant, actor, entity, fighter

**Benched**:
On the Map but not in the Order: a Creature that has died or fled, a summon that has not been added yet, a Treasure, a Pawn the DM has simply set aside. Benched Pawns are listed under the Order rather than hidden, because a DM needs to see the whole room and not only the part of it taking Turns. Being Benched says nothing about being alive — a Combatant at 0 hit points is Unconscious whether it is Benched or not, and the two are decided separately. A Benched Pawn returns to the Order by rolling Initiative afresh, exactly as one joining for the first time does.
_Avoid_: removed, inactive, sidelined, out, reserve

**Entrant**:
A Pawn on its way into an Encounter — what a Combatant is before it has an Initiative. It exists because joining takes a name, a Kind and a Stat Block from the Map and gives back a place in the Order, and the thing going in is not yet the thing coming out. A Treasure can be offered as an Entrant and is simply refused.
_Avoid_: candidate, applicant, joiner, participant

**Stat Block**:
A Pawn's combat numbers: initiative bonus, armour class, current, maximum and temporary hit points, its Conditions, its exhaustion level and whether it is concentrating. Kept beside the Map but never inside the fog file, because a fog file must stay readable by a DM who has never run a fight on it. Every Pawn may have one, Players and Creatures alike: the two differ in what a DM habitually tracks, not in what the rules permit, so the shape is one shape.
_Avoid_: stats, sheet, character sheet, attributes, vitals

**Initiative**:
A Combatant's place-deciding number, rolled as 1d20 plus its initiative bonus when the Encounter starts. Rolled for every Combatant, Players included — overtyping a number the players call out is faster than typing into an empty field. Editable at any time. Typing a number does not by itself move anyone — a DM Tabbing down the column types them all first — and **Return settles the Order**: every row goes where its number puts it, animated, and ties keep the order they already had, so a tie the DM broke by dragging stays broken. The settled Order is recorded, not recomputed, because the Order is the DM's.
_Avoid_: init, roll, initiative score

**Order**:
The sequence Combatants take Turns in. Settled when the Encounter starts by sorting on Initiative, settled again whenever the DM presses Return in the Initiative column, and otherwise the DM's to rearrange by hand — ties are not broken by a rule, they are broken by the person running the table, and a settle never reorders a tie. Because the Order is decided rather than derived, it is recorded, not recomputed.
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
One thing recorded during a Turn — a hit point edit, a Condition applied, a Pawn moved, a note taken, a Roll made. Carries the Combatant it is about.

Where a Change *mutates* a value it carries that value both **before and after**, never a delta, so the Combat Log can be replayed exactly and a Correction is unambiguous about what it corrects. Not every Change mutates one: a movement, a note and a Roll are **records rather than mutations** — the fold skips them, because where a Pawn stands is the Map's own truth, a note is something to read, and a Roll changes nothing at all. The name is older than the distinction and is kept, because renaming it would rename it on disk in every Log already beside a DM's Maps.
_Avoid_: event, mutation, delta, edit, update

**Correction**:
A Change appended against a Turn that has already ended. The amended Turn's own line is untouched; the Correction is a new line naming the Turn it targets. Reading the Log folds Corrections onto their Turns. Hit points, Conditions and notes can be corrected; a movement cannot, because where a Pawn stands is the Map's truth and cannot be retroactively somewhere else.
_Avoid_: undo, fix, amend, retcon, revision

**Condition**:
One of the fourteen boolean states of DnD 5.5e a Combatant can be under — Prone, Restrained, Blinded, and the rest. Exhaustion is deliberately not one of them: it is a level from 0 to 6 and is tracked apart. Conditions carry no duration and expire on nobody's schedule: encoding "until the end of your next turn" and its cousins is a system in itself, and half of that system is worse than a DM's memory.
_Avoid_: status, effect, debuff, ailment, state

**Session**:
One evening at the table, from the moment the DM starts it to the moment they stop it. It is the enclosing thing an Encounter happens inside: a Session may hold several fights, or none, and it spans whatever Maps the party walks across. It belongs to the Workspace rather than to any Map, because an evening outlives the Map it happens to begin on. At most one runs at a time, and it ends only when the DM stops it — quitting the app leaves it running, to be found still open when the app returns, exactly as an unfinished Encounter is. Starting one needs a Workspace, having nowhere to write without one; it does not need a Map. Starting is one click and stopping asks first — not because anything is lost, since the Log is always kept, but because starting again opens a *new* Log and the Log View shows only the current one, so an evening ended by accident leaves the screen.
_Avoid_: game night, play session, meeting, run, sitting

**Session Log**:
The append-only record of a Session, held at the Workspace level rather than beside any Map. It records Pawn movements and the DM's Comments, each Line naming the Map it happened on — by a path relative to the Workspace root, so that two Maps of the same name in different folders are told apart and the name survives the Workspace being moved to another Mac — so a Line can be read without replaying the file above it. It records *only* what happens outside a fight: when an Encounter starts, the Session Log writes one line naming that Encounter's Combat Log and then falls silent, so exactly one recorder is live at any instant and no event is written twice.
_Avoid_: session file, journal, diary, history, timeline

**Line**:
One thing that happened, as recorded: a single entry in a Session Log or a Combat Log, and literally one line of the file. The word spans both logs deliberately — a Comment and a Turn are the same kind of thing to a DM reading back over the evening, however different they are to the code that wrote them. A Line is the unit the Log View scrolls through and the unit an append adds.
_Avoid_: entry, record, event, item, row

**Log View**:
What the Control Window shows in the Map's place when the DM asks to read the evening: the current Session's Lines, oldest at the top, with each Encounter's Turns spliced into the silence its pointer marks. It takes the Live View's place and the Live Toolbar's with it, so nothing on screen is about the Player Display while it is open — the Live Panel and the Comment Bar stay, because a DM reading back over the night is the DM about to write the next Line of it. It shows the Session running *now* and no other: older evenings are a campaign's history, which is a different thing to want and asks different questions. Never a way to change what happened — a mistake in a Log is answered by a Correction, never by an edit here.
_Avoid_: log, timeline, history view, journal, replay, scrollback

**Comment**:
A line of the DM's own text, typed into the Comment Bar and appended to the Session Log. It is about the moment, not about anybody: unlike a Change it carries no target. The line format reserves a place for the Pawn the DM had selected when they typed — recorded beside the text rather than as a subject, so a later reader could see what was being looked at without the Comment claiming to be about it — but nothing fills it yet, there being no Pawn selection in the Live View to read. Distinct from the note taken during a fight, which is a Change on a Combatant's Turn and lands in the Combat Log.
_Avoid_: note, annotation, message, remark, log entry

**Comment Bar**:
The row beneath the Map in the Control Window, the width of the Map rather than of the window: one text field and a send button, Return sending. Its one fixed-height row is the whole of it — no scrollback, because the Map must never resize mid-click. It is the only control that enforces the boundary between preparing a Map and running a Session: it is disabled until a Session starts, and disabled again while an Encounter runs, when the Combat tab's note box is the live one instead. Its placeholder says which of the three it is in.
_Avoid_: comment field, input bar, chat, console, footer

**Setup Toolbar**:
The rows above the Map — the Map's width, not the window's — holding what only the DM sees the result of: Open Map, the Workspace, the screen picker, Grid Fit, the Wall Editor, Add, and the Log. It was named for a phase, for what a DM touches "before the players arrive", and the Log View broke that reading: reading back over the evening is a mid-session act and belongs here all the same. The line is the audience, not the hour — nothing in this row changes what is on the Player Display. Nothing in it is disabled once a Session starts, because a DM sometimes must trace a wall mid-evening; the Log is what disables the rest, the three Map buttons having no Map to act on while it is open.
_Avoid_: map toolbar, top bar, prep bar, controls

**Live Toolbar**:
The row above the Map holding what the table sees the result of: the Fog switch, the Measurement visibility switch, the Viewport toggle, the Map Fit toggle, and the Session control. The counterpart to the Setup Toolbar, and the reason the pair is named at all — these are the switches that change what the players are looking at, now. It is replaced along with the Map when the Log View opens, so there is no Session control while reading: every switch here is about the Player Display, and a DM reaching for one has already decided to look at the Map again.
_Avoid_: players toolbar, player bar, table bar, session bar

**Roll**:
A d20 result the DM records at the table, with the number it showed, the Modifier added to it and the Difficulty Class it was against. A Roll is a **record, not a resolution**: the app never generates the number and never applies what the result implies. The dice are the table's; remembering them is the app's. Two kinds exist — a Saving Throw and an Ability Check — and they differ only in what is being rolled against, never in how they are recorded. A Roll changes nothing, which is why it is recorded beside the Changes of a Turn rather than folded into the tracker's state, exactly as a note is.
_Avoid_: dice roll, check, throw, d20, result

**Saving Throw**:
A Roll a Pawn makes to resist something happening to it, named by the Ability it uses — a Dexterity save against a fireball, a Wisdom save against fear. One of the six Abilities, chosen at the moment of rolling. Distinct from an Ability Check in what it means at the table, not in what is stored: both carry a Difficulty Class, a d20 and a Modifier.
_Avoid_: save, ST, resistance roll

**Ability Check**:
A Roll a Pawn makes to attempt something, named by the Skill it uses — Stealth to hide, Perception to notice. The Skill implies its Ability (Stealth is Dexterity), so the Ability is never chosen separately and never stored separately: it is a fact about the Skill, and a Skill that changed its Ability would change it for every Roll ever recorded, which is what makes it derived rather than copied.
_Avoid_: skill check, ability roll, test

**Ability**:
One of the six: Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma. Named in full in the domain and abbreviated only where a control is too narrow for the word. A Pawn has no Ability *scores* and the app never asks for one — a Pawn has no Strength number — because what a DM needs mid-fight is the total bonus that applied to this Roll, not a character sheet they must first fill in. The scores a Character's or Monster's note writes are read with the rest of the note, and used only to offer a Modifier where the note gives no bonus of its own: never stored, never typed, never shown as a sheet.
_Avoid_: stat, attribute, ability score

**Skill**:
One of the eighteen proficiencies of DnD 5.5e — Acrobatics, Athletics, Stealth, and the rest — each permanently tied to one Ability. Named in an Ability Check and never anywhere else.
_Avoid_: proficiency, expertise, talent

**Difficulty Class**:
The number a Roll's total must reach to succeed. **Optional**: a DM who asks for a Perception check before deciding what it beats, or who keeps the number secret, records the Roll without one, and the Log reports the total with no verdict. Forcing a number here would invite a made-up one.
_Avoid_: DC, target number, threshold

**Modifier**:
Everything added to the d20 on a Roll — ability bonus, proficiency, expertise, active effects — as a single number the DM confirms. One number rather than its parts, because the total is what was said aloud at the table. When the rolling Pawn's Character or Monster has a note, the Modifier is **offered** from it — the bonus the note gives for that save or that Skill, read when the Roll is taken, never copied onto the Pawn — and the DM overtypes it as freely as an Initiative the players call out, because the note cannot know about the blessing or the belt. Where the note gives no bonus for that save or Skill — it lists only what the creature is proficient in — the offer is the plain modifier of the Ability rolled, from the scores the note writes; a hero whose class adds to every Skill is offered a little less, and the DM overtypes it or lists the Skill in the note. The offer follows the save or Skill the DM picks until the DM types a number, which is then never overwritten, and the sheet says which note the offer came from. Nothing about the offer is recorded: the Roll keeps the number, not where it came from. A Pawn with no note, and a Treasure, is offered nothing, and the DM types it as before.
_Avoid_: bonus, adjustment, plus

**Interface Language**:
The language MapForge speaks: every word the app itself writes, on the Control Window and the Player Display alike. Rulebook terms are the ones the official D&D edition prints in that language, never our own rendering, because the table already speaks them — and in a language no official edition exists for, they stay in English, which is what that table speaks instead. Everything the DM wrote — Monster names from their notes, Pawn labels, Light names, Parties, Characters, Comments — is never translated: it is theirs, not the app's. Chosen per Mac, not per Workspace.
_Avoid_: locale, localisation, translation, app language
