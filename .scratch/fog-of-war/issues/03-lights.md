# 03 — Lights

Status: ready-for-human
Blocked by: 01

Place Lights on a Map and toggle them on and off. A Light has a position, a bright radius, a dim radius, and an on/off state.

Interaction:

- Place a Light by clicking in the fog editing mode; drag to reposition; select to delete.
- Radii are entered in **Grid squares**, not pixels — a Light is a physical thing ("bright 20 ft, dim 40 ft" is how every 5e stat block reads). Dim defaults to twice bright, so a torch is entered as one number.
- Each Light gets an on/off toggle in a **compact live panel** available outside the editing mode. Toggling is the one fog action a DM performs mid-session, with players watching; it must be one click and take effect immediately on the Player Display.
- A Light with dim radius 0 is legal — a sharp-edged source with no falloff band.

Scope:

- White Lights only. Coloured Lights are out of scope.
- No animation — no flicker, no pulsing. A torch that flickers is a distraction on a shared TV and would force Visibility to recompute continuously.
- Radii in squares means a Light has no physical meaning until the Grid is declared. After a relaunch that Grid is gone (`squaresWide` is in-memory only — see issue 01); a Light must degrade visibly rather than silently rendering at a wrong size.

Acceptance: placing a torch (bright 20 ft / dim 40 ft) on a Map with a declared Grid produces a lit circle measuring 4 Grid squares in radius on the Player Display, and switching it off darkens exactly that region with no perceptible delay.

## Comments

- 2026-09-01 (grilling session): designed via `/grill-with-docs`. The bright/dim pair was chosen over a single range: it matches how 5e states every light source and how DMs already think, costs one number and one rendering band, and turning the Visibility mask from boolean to three-valued later would have meant touching the engine, the file format and the editing UI at once.

- 2026-09-01 (implemented): `FogEdits` (replacing issue 02's `WallEdits`), Lights in `FogOverlay`, a radii inspector and an always-visible live toggle row in `ControlView`. 24 unit tests.

  Two shape decisions, both put to the user. Issue 02's walls-only mode became **one fog editing mode with a Walls/Lights tool picker** — the issue's own wording is "the fog editing mode", the Control Window's top row should not grow a button per fog concept, and a DM needs to see a torch against the room they traced to know the room works. All fog draws whatever the tool; the tool decides only what a click does. And the live toggles are an **always-visible row** rather than a popover: "one click, with players watching" cannot afford a click to open a panel first.

  Undo is one history over the whole document, not one per kind — the DM thinks in actions, not in which collection an action touched. Toggling a Light is deliberately *not* undoable: it is a live performance action, and filling the stack with toggles would bury the authoring work behind them. A drag is one step, bracketed by `beginLightDrag`/`endLightDrag`, and a click that begins and ends a drag without moving anything leaves no step at all.

  Lights snap to the Grid but not to Wall endpoints: a torch sits in a room, not on its wall.

  Acceptance is tested through the engine: a 4-square torch lights exactly 4 squares bright and 8 dim, and switching it off empties the region. The "no perceptible delay" half is `VisibilityCache` doing the work — measured at ~14 ms for a far larger scene in issue 05.

  Not verified: the four UI tests still could not run — `MapForgeUITests` hangs in this environment, on `develop` too.
