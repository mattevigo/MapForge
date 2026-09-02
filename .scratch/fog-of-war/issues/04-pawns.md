# 04 — Pawns

Status: ready-for-human
Blocked by: 01, 03

A Pawn is a token on the Map with a label and a colour, drawn for players whether or not the Fog Overlay is active. A Pawn is also a Light: its range of sight and its range of illumination are the same number.

That collapse is a consequence of the feature being a lighting simulation (see the spec). With no per-observer masks and one shared Player Display, a Pawn that sees 30 ft and a Pawn that lights 30 ft are indistinguishable, so they are modelled as one thing.

Interaction:

- Place a Pawn in the fog editing mode; give it a label and a colour; set its range in **Grid squares**, reusing the Light radius model from issue 03 (bright/dim, dim defaulting to 2×).
- **Dragging a Pawn is a live table action**, not a prep-time one — the party moves. It must work outside the editing mode, at drag rate, with Visibility updating as it moves.
- A Pawn's own light is toggleable like any Light: a character who puts out their torch keeps their token on the Map.
- Pawns render on the Player Display as a filled disc in their colour with their label, sized in Grid squares so a token reads as occupying its square.

Scope:

- Pawns are their own concept, not a fog concept. Visibility *reads* Pawn positions; it does not own them. Turning the Fog Overlay off leaves labelled coloured tokens on the Map, which is what a DM would expect.
- Placement is free-form, not snapped to Grid squares. Revisit if it turns out to matter at the table.
- No per-Pawn vision, no explored-area memory, no line-of-sight from a specific Pawn's point of view — all excluded by the spec's choice of lighting simulation over dynamic vision.

Acceptance: a Pawn with a 30 ft range, dragged across a doorway, lights the next room progressively as it moves through — with Visibility keeping up with the drag, not lagging behind it. With the Fog Overlay off, the same Pawn is still visible to players as a labelled coloured token.

## Comments

- 2026-09-01 (grilling session): designed via `/grill-with-docs`. Modelling Pawn as its own entity rather than a fog-internal one was a deliberate call, so tokens survive the Fog Overlay being switched off.

- 2026-09-02 (implemented): Pawn editing in `FogEdits`, a Pawns tool in `FogOverlay`, `PawnToken`, `PlayerPlacement`, `PawnLayer`, and Pawns rendered on the Player Display. 28 unit tests.

  `PawnToken` is one view shared by the Control Window and the Player Display, so a token cannot look like two different things on the two screens — the DM points at the red circle and the players must be looking at the same red circle.

  Dragging outside the editing mode is `PawnLayer`, deliberately separate from `FogOverlay`: the party moves during play, not during prep, so moving a token must not require entering a mode. Its drag is measured in a named container space, never the token's own — a token placed with `.position()` moves as it is dragged, which is the feedback loop `map-presenter/09` already cost a round of work on.

  `PlayerPlacement` is the one conversion everything Map-space needs: Pawns are stored in image pixels while the Map is drawn in points. Its inverse is tested against `viewPoint` directly, so a dragged token lands exactly under the cursor and forty small drags return to the origin.

  The acceptance test measures lit *area* across the far room, not one point. My first attempt probed a single point on the doorway's centre line, which is visible from the very start — that is what a doorway is — so it failed against correct behaviour. The engine was right and the test was wrong.

  Not verified: the UI tests still could not run — `MapForgeUITests` hangs in this environment.
