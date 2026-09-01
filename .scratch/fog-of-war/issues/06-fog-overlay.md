# 06 — Fog Overlay and its off switch

Status: ready-for-agent
Blocked by: 04, 05

Draw the Visibility from issue 05 on both displays, and let the DM switch it off.

**Player Display** — the Map with darkness composited over it. Unlit regions black, dim regions partially darkened, bright regions untouched. Drawn with `SwiftUI.Canvas` and blend modes: fill black, punch out the lit polygons. `PlayerView` is currently a single `Image` in a `ZStack` with no Canvas, CALayer or Metal anywhere in the codebase, so this is the first compositing the app does.

**Control Window** — the same Visibility as a translucent tint over a **fully-lit** Map, so the DM sees everything and knows what the players cannot. A DM as blind as the players cannot run the game.

Details:

- A gradient at each Light's range limit, so a torch fades out instead of ending in a suspicious circle. Wall shadow edges stay hard — that is the information players need, and blurring it makes "can I see round that corner" ambiguous.
- **The off switch** is a single control that removes the Fog Overlay from the Player Display entirely. Pawns keep rendering (issue 04) — turning off fog is not turning off tokens.
- True Scale is untouched. The overlay is drawn in the same Viewport-relative transform as the Map, so panning moves Map and darkness together with no drift. Nothing here may change how the Map itself is scaled or positioned.
- Panning must stay smooth: the overlay redraws from cached Visibility, never recomputes it.

Scope:

- No animated transition when fog is toggled or a Light switches. An instant cut matches Blackout's intent and avoids a frame budget nobody needs.
- Letterbox around the Map stays plain black, as it is today — the implicit boundary Walls (issue 02) already stop Light reaching it.

Acceptance: with a torch inside a traced room, players see the room lit, the doorway wedge, and black beyond — while the Control Window shows the whole Map with that same darkness as a tint the DM can see through. Panning the Viewport at drag rate stays smooth. Switching the overlay off reveals the full Map with Pawns still on it.

## Comments

- 2026-09-01 (grilling session): designed via `/grill-with-docs`. Blackout and rotation were considered as interactions and dropped — both are `wontfix` in `map-presenter` and do not exist to interact with.
