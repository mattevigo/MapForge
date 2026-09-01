# 03 — Lights

Status: ready-for-agent
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
