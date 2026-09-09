# 06 — Viewport control and rotation

Status: wontfix
Blocked by: 05

Control Window shows the whole Map scaled to fit with a draggable Viewport frame sized to exactly what the Player Display shows at True Scale (accounting for rotation and calibration). Dragging the frame pans the Player Display live, free-form, no animation. Rotation buttons step 90° and persist to the Sidecar; letterbox any uncovered screen area in black.

Acceptance: the frame's content and the Player Display content match 1:1; rotation survives relaunch.

## Comments

- 2026-08-29: the pan half lands early as **Viewport panning** (issue 09) — dedicated mode with a draggable, never-resizable Viewport rectangle, live panning, mirror preview outside the mode, in-memory only. Remaining here: rotation (90° steps, Sidecar persistence) and re-checking the Viewport size math once Calibration (issue 04) exists.

- 2026-08-31 (wontfix): retired unimplemented on user's request while closing out the tracker — the shipped scaffolding + Grid Fit + Viewport panning slice covers the current need. Reopen by resetting Status if the feature is picked up again.
