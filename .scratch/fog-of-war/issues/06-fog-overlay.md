# 06 — Fog Overlay and its off switch

Status: ready-for-human
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

- 2026-09-02 (implemented): `FogShading`, `FogCanvas`, the overlay on both surfaces, and the off switch. 14 unit tests.

  `FogCanvas` is shared by the Player Display and the Control Window; only the opacity function differs. That is deliberate — two separately-written renderers could disagree about what is hidden, and the DM's whole job depends on knowing exactly what the players cannot see. Players get `FogShading.player` (unlit is black); the DM gets `.control`, a weaker tint over a fully-lit Map, with the same ordering so the two never tell different stories.

  Darkness is filled once and the lit polygons subtracted with `.destinationOut`, dim first then bright, so bright wins where two Lights meet — matching `Visibility.level`. Drawing them the other way round would leave a dim patch between two torches.

  `AppState.litRegions` returns nothing when no Grid has been declared. Light radii are in Grid squares, so without one every region would be sized against a default that is almost certainly wrong, and darkness in the wrong places is worse than no darkness. The Control Window already warns (issue 03's `undeclaredGridWarning`).

  Two of my acceptance assertions were wrong before the code was: one probed a point exactly on a Light's rim, where lit-or-not is a coin flip, and one rebuilt its `FogDocument` on every access so fresh UUIDs defeated the cache it was meant to be testing. Both are the same trap — asserting on a boundary — and both are noted in the tests now.

  Not verified: the UI tests still could not run here.

- 2026-09-02 (review): two real rendering defects, both of which the reviews and I found independently.

  **The range gradient was dead code.** `FogShading.falloffOpacity` was written, documented and tested — and nothing drew with it, so every torch ended in exactly the hard circle the issue forbids. Tests that exercise a pure function no renderer calls cannot fail when the rendering is wrong. `LitRegion` now carries the Light's origin so `FogCanvas` can shade each band with a radial gradient.

  **Overlapping regions double-subtracted.** `.destinationOut` multiplies, so two overlapping dim polygons filled at the same alpha left the overlap *brighter* than either alone — a visible seam precisely where two torches meet, the inverse of the failure issue 05's case list warned about. Each band now fills at full strength with the removal alpha applied once to the layer.
