# 08 — Grid Fit

Status: ready-for-agent
Blocked by: 01

Grid Fit: declare a Map's Grid by dragging a square over a single grid square of the artwork in the Control Window preview, instead of typing a squares-wide count. Derives image-pixels-per-square from the drawn square (1 square = 1 inch physical, per glossary); the Map's squares-wide follows as `imageWidth / pixelsPerSquare`. This is not Calibration (issue 04): it fixes the Map's declared size, not the display's correction factor.

Interaction:

- A "Fit Grid…" affordance enters Grid Fit mode on the existing Control Window preview.
- Drag-to-draw creates an aspect-constrained square overlay; it stays adjustable afterwards (corner handles to resize, body drag to move) until confirmed with Enter or a confirm button. Cancel/Esc exits the mode and reverts the value from before it.
- Precision aids: the derived "Grid squares wide" value updates live next to the overlay while adjusting (e.g. "≈ 29.9"), arrow keys move the square by 1 pt, and ⇧+arrows resize it by 1 pt.
- Snapping is suggested, never silent: when the derived value is within 0.25 squares of an integer (absolute, not relative — relative would keep the affordance permanently visible on large maps), show a one-click "Snap to N?" affordance; accepting it also resizes the overlay to match. The gesture's raw value is never changed without the user acting.
- The existing "Grid squares wide" numeric field remains visible, showing the derived value and staying hand-editable as the escape hatch.
- Player Display re-renders live as the value changes (existing `squaresWide.didSet` behavior).

Scope:

- In-memory only; no persistence this increment. The derived pixels-per-square / squares-wide slots into the Sidecar when issue 03 builds it.
- Grid maps only. Gridless variant (draw over a known-length feature and type its real length) is a possible extension, out of scope here.
- Single-square selection only; multi-square spans were considered and rejected in favor of the live readout + suggested snap.

Acceptance: on a real VTT map image, dragging a square over one printed grid square and confirming yields a squares-wide value that makes the grid overlay (issue 03) — or, pending that, a physical ruler check on the Player Display — line up with the artwork; a 1-inch square measures 2.54 cm on a calibrated display.

## Comments

- 2026-08-29 (implementation review): two-axis review applied. Snap tolerance changed from "~5% relative" to 0.25 squares absolute (relative degenerated to always-on for maps ≥ 10 squares wide); arrow-key spec reworded to what was built (arrows move, ⇧ resizes — no per-handle selection); Cancel/Esc revert documented as required by live value application. Needs a human check on real hardware: Enter/Esc while the overlay has keyboard focus, and ruler verification of a snapped square on the Player Display.
- 2026-08-29 (grilling session): designed via /grill-with-docs. Decisions: concept is grid declaration by selection, not display calibration; square target is 1 inch (2.54 cm), matching the glossary — not 2.5 cm; lands ahead of the 02→07 chain because it only needs the POC preview and AppState. Glossary term **Grid Fit** added to CONTEXT.md.
